// file: lib/services/backup_service.dart
//
// 곡 메타데이터, 가사, 반주 파일을 zip으로 백업/복원한다.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';

import '../constants/app_version.dart';
import '../models/backing_track.dart';
import '../models/song.dart';
import '../repository/song_repository.dart';

class BackupService {
  final SongRepository _repo;

  /// 이 빌드가 읽고 쓸 수 있는 백업 포맷 버전.
  static const int backupFormatVersion = 2;

  const BackupService(this._repo);

  Future<BackupResult?> exportAll({String appVersion = AppVersion.current}) async {
    final songs = await _repo.loadSongs();
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'SingPromfter 백업 저장',
      fileName:
          'singpromfter_backup_${DateTime.now().toIso8601String().replaceAll(':', '-')}.zip',
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (savePath == null) return null;

    final archive = Archive();
    final manifest = {
      'version': backupFormatVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'appVersion': appVersion,
      'songCount': songs.length,
      'contents': {
        'meta': 'songs.json',
        'lyricsDir': 'txt/',
        'tracksDir': 'mp3/',
      },
    };
    _addText(archive, 'backup_manifest.json', jsonEncode(manifest));

    final backupSongs = <Map<String, dynamic>>[];
    for (final song in songs) {
      final meta = song.toMetaJson();
      final lyricsName = _baseName(song.lyricsPath);
      meta['lyricsPath'] = 'txt/$lyricsName';
      backupSongs.add(meta);
      _addText(archive, 'txt/$lyricsName', song.lyricsText);

      for (final track in song.backingTracks) {
        final path = await _repo.getBackingTrackPath(track.fileName);
        if (path == null) continue;
        final file = File(path);
        if (await file.exists()) {
          _addBytes(archive, 'mp3/${track.fileName}', await file.readAsBytes());
        }
      }
    }

    _addText(
      archive,
      'songs.json',
      const JsonEncoder.withIndent('  ').convert(backupSongs),
    );

    final bytes = ZipEncoder().encode(archive);
    await File(savePath).writeAsBytes(bytes);
    return BackupResult.success(path: savePath, songCount: songs.length);
  }

  Future<ImportResult?> importFromPicker(List<Song> currentSongs) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      dialogTitle: 'SingPromfter 백업 파일 선택',
    );
    if (picked == null || picked.files.isEmpty) return null;
    final path = picked.files.first.path;
    if (path == null) {
      return const ImportResult.failure('백업 파일 경로를 읽을 수 없습니다.');
    }
    return importFromZip(path, currentSongs);
  }

  Future<ImportResult> importFromZip(
    String zipPath,
    List<Song> currentSongs,
  ) async {
    try {
      final archive = ZipDecoder().decodeBytes(
        await File(zipPath).readAsBytes(),
      );
      // 매니페스트를 실제로 검증한다. 상위 버전 백업을 구버전 앱이 잘못
      // 해석해 데이터를 잃는 상황을 막는다. (매니페스트가 없으면 구버전 백업으로 간주)
      final manifestError = _validateManifest(archive);
      if (manifestError != null) {
        return ImportResult.failure(manifestError);
      }

      final songsFile = archive.findFile('songs.json');
      if (songsFile == null) {
        return const ImportResult.failure('백업 파일에 songs.json이 없습니다.');
      }

      final rawSongs = utf8.decode(songsFile.content as List<int>);
      final list = jsonDecode(rawSongs) as List<dynamic>;
      final nextSongs = List<Song>.from(currentSongs);
      var renamedCount = 0;

      for (final item in list) {
        final json = (item as Map).cast<String, dynamic>();
        final sourceSong = Song.fromMetaJson(json);
        final title = _uniqueTitle(sourceSong.title, nextSongs);
        if (title != sourceSong.title) renamedCount += 1;

        final lyricsArchivePath = json['lyricsPath'] as String? ?? '';
        final lyricsText = _readText(archive, lyricsArchivePath);
        final lyricsPath = await _repo.writeLyricsFile(
          title: title,
          lyrics: lyricsText,
        );
        final tracks = <BackingTrack>[];

        for (final track in sourceSong.backingTracks) {
          final file = archive.findFile('mp3/${track.fileName}');
          if (file == null) continue;
          final fileName = _repo.buildBackingTrackFileName(title, track.slot);
          final target = File(
            '${(await _repo.getBackingTrackDir()).path}/$fileName',
          );
          await target.writeAsBytes(file.content as List<int>);
          // copyWith로 복사해 startMs/endMs 같은 트림 값이 유실되지 않게 한다.
          tracks.add(track.copyWith(fileName: fileName));
        }

        nextSongs.add(
          sourceSong.copyWith(
            title: title,
            lyricsPath: lyricsPath,
            lyricsText: lyricsText,
            backingTracks: tracks,
            updatedAt: DateTime.now(),
          ),
        );
      }

      await _repo.saveSongs(nextSongs);
      return ImportResult.success(
        songs: nextSongs,
        importedCount: list.length,
        renamedCount: renamedCount,
      );
    } catch (e) {
      return ImportResult.failure('백업 가져오기 중 오류가 발생했습니다: $e');
    }
  }

  /// 백업 매니페스트 버전을 확인한다. 문제가 없으면 null을 반환한다.
  String? _validateManifest(Archive archive) {
    final manifestFile = archive.findFile('backup_manifest.json');
    if (manifestFile == null) return null; // 매니페스트 이전 버전 백업 — 허용

    try {
      final decoded = jsonDecode(
        utf8.decode(manifestFile.content as List<int>),
      );
      if (decoded is! Map) return null;
      final version = (decoded['version'] as num?)?.toInt();
      if (version != null && version > backupFormatVersion) {
        return '백업 파일 버전이 $version이라 이 앱 버전(최대 $backupFormatVersion)에서는 '
            '가져올 수 없습니다. 앱을 최신 버전으로 업데이트해 주세요.';
      }
      return null;
    } catch (_) {
      // 매니페스트가 깨져 있어도 songs.json이 읽히면 복원을 시도한다.
      return null;
    }
  }

  void _addText(Archive archive, String name, String text) {
    _addBytes(archive, name, utf8.encode(text));
  }

  void _addBytes(Archive archive, String name, List<int> bytes) {
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  String _readText(Archive archive, String name) {
    final file = archive.findFile(name);
    if (file == null) return '';
    return utf8.decode(file.content as List<int>).trim();
  }

  String _uniqueTitle(String title, List<Song> songs) {
    final normalized = songs
        .map((song) => song.title.trim().toLowerCase())
        .toSet();
    if (!normalized.contains(title.trim().toLowerCase())) return title;
    var index = 2;
    while (true) {
      final candidate = '$title (가져오기 $index)';
      if (!normalized.contains(candidate.trim().toLowerCase())) {
        return candidate;
      }
      index += 1;
    }
  }

  String _baseName(String path) => path.split(RegExp(r'[\\/]')).last;
}

class BackupResult {
  final bool success;
  final String? path;
  final int songCount;
  final String? message;

  const BackupResult._({
    required this.success,
    this.path,
    this.songCount = 0,
    this.message,
  });

  const BackupResult.success({required String path, required int songCount})
    : this._(success: true, path: path, songCount: songCount);

  const BackupResult.failure(String message)
    : this._(success: false, message: message);
}

class ImportResult {
  final bool success;
  final List<Song>? songs;
  final int importedCount;
  final int renamedCount;
  final String? message;

  const ImportResult._({
    required this.success,
    this.songs,
    this.importedCount = 0,
    this.renamedCount = 0,
    this.message,
  });

  const ImportResult.success({
    required List<Song> songs,
    required int importedCount,
    required int renamedCount,
  }) : this._(
         success: true,
         songs: songs,
         importedCount: importedCount,
         renamedCount: renamedCount,
       );

  const ImportResult.failure(String message)
    : this._(success: false, message: message);
}
