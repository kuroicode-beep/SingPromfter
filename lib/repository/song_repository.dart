import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../models/backing_track.dart';
import '../models/prompter_settings.dart';
import '../models/queue_item.dart';
import '../models/song.dart';
import 'song_meta_store.dart';

const _kSongsKey = 'singpromfter_songs';
const _kSettingsKey = 'singpromfter_settings';
const _kQueueKey = 'singpromfter_queue';
const _kLastSongIdKey = 'singpromfter_last_song_id';

class SongRepository {
  SongRepository._();
  static final SongRepository instance = SongRepository._();
  final SongMetaStore _metaStore = SongMetaStore();

  Future<Directory> get _dataDir async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/data');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> getDataDir() => _dataDir;

  /// 가져오기 작업용 임시 폴더. 성공했을 때만 라이브러리로 옮기므로
  /// 반쯤 받아진 파일이 목록에 노출되지 않는다.
  Future<Directory> getTmpDir() async {
    final dir = Directory('${(await _dataDir).path}/tmp');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> get _lyricsDir async {
    final dir = Directory('${(await _dataDir).path}/txt');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> getLyricsDir() => _lyricsDir;

  Future<Directory> get _mrDir async {
    final dir = Directory('${(await _dataDir).path}/mp3');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> getBackingTrackDir() => _mrDir;

  Future<Directory> get _legacyLyricsDir async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/lyrics');
  }

  Future<Directory> get _legacyMrDir async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/mr');
  }

  /// 상위 버전 songs.json을 만나 로드를 거부한 경우의 안내 문구.
  /// 설정되면 saveSongs가 파일을 덮어쓰지 않는다.
  String? _schemaError;

  String? get schemaLoadError => _schemaError;

  Future<List<Song>> loadSongs() async {
    try {
      if (await _metaStore.exists()) {
        return await _metaStore.load();
      }

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSongsKey);
      if (raw == null || raw.isEmpty) return [];
      final songs = Song.decodeList(raw);

      // lyricsText가 비어있는 곡은 파일에서 읽어 마이그레이션
      bool changed = false;
      final migrated = await Future.wait(
        songs.map((song) async {
          if (song.lyricsText.isNotEmpty) return song;
          String text = '';
          // 1) lyricsPath 시도
          final f1 = File(song.lyricsPath);
          if (await f1.exists()) text = (await f1.readAsString()).trim();
          // 2) 기본 lyrics 디렉토리 시도
          if (text.isEmpty) {
            final f2 = File('${(await _lyricsDir).path}/${song.id}.txt');
            if (await f2.exists()) text = (await f2.readAsString()).trim();
          }
          if (text.isEmpty) {
            final f3 = File(
              '${(await _lyricsDir).path}/${buildLyricsFileName(song.title)}',
            );
            if (await f3.exists()) text = (await f3.readAsString()).trim();
          }
          if (text.isEmpty) {
            final f4 = File('${(await _legacyLyricsDir).path}/${song.id}.txt');
            if (await f4.exists()) text = (await f4.readAsString()).trim();
          }
          if (text.isEmpty) return song;
          changed = true;
          return song.copyWith(lyricsText: text);
        }),
      );
      if (changed) debugPrint('legacy songs 가사 텍스트 마이그레이션 완료');
      await _metaStore.save(migrated);
      await prefs.remove(_kSongsKey);
      return migrated;
    } on SongMetaSchemaException catch (e) {
      // 상위 버전 데이터를 빈 목록으로 착각해 덮어쓰지 않도록
      // 오류를 기억해 두고 저장을 차단한다.
      _schemaError = e.message;
      debugPrint('songs.json 스키마 거부: ${e.message}');
      return [];
    } catch (e, stack) {
      debugPrint('loadSongs 실패: $e\n$stack');
      return [];
    }
  }

  Future<void> saveSongs(List<Song> songs) async {
    if (_schemaError != null) {
      debugPrint('상위 버전 songs.json 보호를 위해 저장을 건너뛴다.');
      return;
    }
    await _metaStore.save(songs);
  }

  Future<PrompterSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSettingsKey);
    if (raw == null || raw.isEmpty) return const PrompterSettings();
    try {
      return PrompterSettings.decode(raw);
    } catch (e, stack) {
      debugPrint('loadSettings 실패, 기본 설정 사용: $e\n$stack');
      return const PrompterSettings();
    }
  }

  Future<void> saveSettings(PrompterSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSettingsKey, PrompterSettings.encode(settings));
  }

  Future<List<QueueItem>> loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kQueueKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return QueueItem.decodeList(raw);
    } catch (e, stack) {
      debugPrint('loadQueue 실패, 빈 큐 사용: $e\n$stack');
      return [];
    }
  }

  Future<void> saveQueue(List<QueueItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kQueueKey, QueueItem.encodeList(items));
  }

  Future<String?> loadLastSongId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLastSongIdKey);
  }

  Future<void> saveLastSongId(String? songId) async {
    final prefs = await SharedPreferences.getInstance();
    if (songId == null || songId.isEmpty) {
      await prefs.remove(_kLastSongIdKey);
      return;
    }
    await prefs.setString(_kLastSongIdKey, songId);
  }

  Future<Song> addSong({
    required String id,
    required String title,
    String artist = '',
    required String lyrics,
    Map<int, String>? sourceTrackPaths,
    Map<int, String>? trackLabels,
    Map<int, int?>? trackStartMs,
    Map<int, int?>? trackEndMs,
  }) async {
    final lyricsPath = await writeLyricsFile(title: title, lyrics: lyrics);
    final tracks = <BackingTrack>[];

    if (sourceTrackPaths != null) {
      for (final entry in sourceTrackPaths.entries) {
        final slot = entry.key;
        if (slot < 1 || slot > AppConstants.maxBackingTrackSlots) continue;
        final source = entry.value;
        if (source.trim().isEmpty) continue;
        final fileName = await copyBackingTrack(
          title: title,
          slot: slot,
          sourcePath: source,
        );
        tracks.add(
          BackingTrack(
            slot: slot,
            fileName: fileName,
            label: _trackLabel(trackLabels, slot, 'MR$slot'),
            startMs: trackStartMs?[slot],
            endMs: trackEndMs?[slot],
          ),
        );
      }
      tracks.sort((a, b) => a.slot.compareTo(b.slot));
    }

    final now = DateTime.now();
    return Song(
      id: id,
      title: title,
      artist: artist.trim(),
      lyricsPath: lyricsPath,
      lyricsText: lyrics,
      backingTracks: tracks,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<Song> updateSong({
    required Song song,
    required String title,
    String? artist,
    String? lyrics,
    Map<int, String>? sourceTrackPaths,
    Map<int, String>? trackLabels,
    Map<int, int?>? trackStartMs,
    Map<int, int?>? trackEndMs,
  }) async {
    final nextTitle = title.trim().isEmpty ? song.title : title.trim();
    final nextLyrics = lyrics ?? song.lyricsText;
    final nextLyricsPath = await writeLyricsFile(
      title: nextTitle,
      lyrics: nextLyrics,
    );

    final nextTracks = <BackingTrack>[];
    final oldTrackNamesToDelete = <String>{};

    for (final slot in AppConstants.backingTrackSlots) {
      final replacementPath = sourceTrackPaths?[slot];
      final existingTrack = song.trackForSlot(slot);

      if (replacementPath != null && replacementPath.trim().isNotEmpty) {
        final fileName = await copyBackingTrack(
          title: nextTitle,
          slot: slot,
          sourcePath: replacementPath,
        );
        nextTracks.add(
          BackingTrack(
            slot: slot,
            fileName: fileName,
            label: _trackLabel(trackLabels, slot, 'MR$slot'),
            startMs: trackStartMs?[slot],
            endMs: trackEndMs?[slot],
          ),
        );
        if (existingTrack != null && existingTrack.fileName != fileName) {
          oldTrackNamesToDelete.add(existingTrack.fileName);
        }
        continue;
      }

      if (existingTrack == null) continue;

      final renamedFileName = buildBackingTrackFileName(nextTitle, slot);
      if (existingTrack.fileName == renamedFileName) {
        nextTracks.add(
          BackingTrack(
            slot: existingTrack.slot,
            fileName: existingTrack.fileName,
            label: _trackLabel(trackLabels, slot, existingTrack.label),
            startMs: trackStartMs?.containsKey(slot) == true
                ? trackStartMs![slot]
                : existingTrack.startMs,
            endMs: trackEndMs?.containsKey(slot) == true
                ? trackEndMs![slot]
                : existingTrack.endMs,
          ),
        );
        continue;
      }

      final sourceFile = await _findBackingTrackFile(existingTrack.fileName);
      if (sourceFile == null) {
        nextTracks.add(
          BackingTrack(
            slot: existingTrack.slot,
            fileName: existingTrack.fileName,
            label: existingTrack.label,
          ),
        );
        continue;
      }

      final renamedPath = '${(await _mrDir).path}/$renamedFileName';
      if (sourceFile.path != renamedPath) {
        await sourceFile.copy(renamedPath);
        oldTrackNamesToDelete.add(existingTrack.fileName);
      }
      nextTracks.add(
        BackingTrack(
          slot: slot,
          fileName: renamedFileName,
          label: _trackLabel(trackLabels, slot, existingTrack.label),
          startMs: trackStartMs?.containsKey(slot) == true
              ? trackStartMs![slot]
              : existingTrack.startMs,
          endMs: trackEndMs?.containsKey(slot) == true
              ? trackEndMs![slot]
              : existingTrack.endMs,
        ),
      );
    }

    if (song.lyricsPath != nextLyricsPath) {
      await _deleteFileIfExists(song.lyricsPath);
      await _deleteFileIfExists(
        '${(await _legacyLyricsDir).path}/${song.id}.txt',
      );
    }

    for (final fileName in oldTrackNamesToDelete) {
      await _deleteBackingTrackByName(fileName);
    }

    return song.copyWith(
      title: nextTitle,
      artist: artist?.trim() ?? song.artist,
      lyricsPath: nextLyricsPath,
      lyricsText: nextLyrics,
      backingTracks: nextTracks,
      updatedAt: DateTime.now(),
    );
  }

  Future<String> writeLyricsFile({
    required String title,
    required String lyrics,
  }) async {
    final lyricsFile = File(
      '${(await _lyricsDir).path}/${buildLyricsFileName(title)}',
    );
    await lyricsFile.writeAsString(lyrics);
    return lyricsFile.path;
  }

  Future<String> copyBackingTrack({
    required String title,
    required int slot,
    required String sourcePath,
  }) async {
    final dir = await _mrDir;
    final fileName = buildBackingTrackFileName(title, slot);
    final dest = File('${dir.path}/$fileName');
    await File(sourcePath).copy(dest.path);
    return fileName;
  }

  Future<String?> getBackingTrackPath(String fileName) async {
    final file = await _findBackingTrackFile(fileName);
    return file?.path;
  }

  Future<void> deleteSong(Song song) async {
    final lyricsPath = song.lyricsPath;
    final lyricsFile = File(lyricsPath);
    if (await lyricsFile.exists()) {
      await lyricsFile.delete();
    } else {
      final legacyLyricsFile = File(
        '${(await _lyricsDir).path}/${song.id}.txt',
      );
      if (await legacyLyricsFile.exists()) {
        await legacyLyricsFile.delete();
      }
      final oldLegacyLyricsFile = File(
        '${(await _legacyLyricsDir).path}/${song.id}.txt',
      );
      if (await oldLegacyLyricsFile.exists()) {
        await oldLegacyLyricsFile.delete();
      }
    }

    for (final track in song.backingTracks) {
      await _deleteBackingTrackByName(track.fileName);
    }
  }

  String buildLyricsFileName(String title) {
    return '${_sanitizeFileStem(title)}.txt';
  }

  String buildBackingTrackFileName(String title, int slot) {
    return '${_sanitizeFileStem(title)}_mr$slot.mp3';
  }

  String _sanitizeFileStem(String input) {
    final sanitized = input
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    return sanitized.isEmpty ? 'song' : sanitized;
  }

  String _trackLabel(Map<int, String>? labels, int slot, String fallback) {
    final label = labels?[slot]?.trim();
    return label == null || label.isEmpty ? fallback : label;
  }

  Future<File?> _findBackingTrackFile(String fileName) async {
    final primary = File('${(await _mrDir).path}/$fileName');
    if (await primary.exists()) return primary;

    final legacy = File('${(await _legacyMrDir).path}/$fileName');
    if (await legacy.exists()) return legacy;

    return null;
  }

  Future<void> _deleteBackingTrackByName(String fileName) async {
    await _deleteFileIfExists('${(await _mrDir).path}/$fileName');
    await _deleteFileIfExists('${(await _legacyMrDir).path}/$fileName');
  }

  Future<void> _deleteFileIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
