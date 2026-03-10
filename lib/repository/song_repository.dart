import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/backing_track.dart';
import '../models/prompter_settings.dart';
import '../models/queue_item.dart';
import '../models/song.dart';

const _kSongsKey = 'singpromfter_songs';
const _kSettingsKey = 'singpromfter_settings';
const _kQueueKey = 'singpromfter_queue';
const _kLastSongIdKey = 'singpromfter_last_song_id';

class SongRepository {
  SongRepository._();
  static final SongRepository instance = SongRepository._();

  Future<Directory> get _dataDir async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/data');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> get _lyricsDir async {
    final dir = Directory('${(await _dataDir).path}/txt');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> get _mrDir async {
    final dir = Directory('${(await _dataDir).path}/mp3');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> get _legacyLyricsDir async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/lyrics');
  }

  Future<Directory> get _legacyMrDir async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/mr');
  }

  Future<List<Song>> loadSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSongsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final songs = Song.decodeList(raw);
      if (kIsWeb) return songs;
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
      // 변경이 있으면 SharedPreferences에 저장
      if (changed) {
        await prefs.setString(_kSongsKey, Song.encodeList(migrated));
      }
      return migrated;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSongs(List<Song> songs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSongsKey, Song.encodeList(songs));
  }

  Future<PrompterSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSettingsKey);
    if (raw == null || raw.isEmpty) return const PrompterSettings();
    try {
      return PrompterSettings.decode(raw);
    } catch (_) {
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
    } catch (_) {
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
    required String lyrics,
    Map<int, String>? sourceTrackPaths,
  }) async {
    final lyricsPath = await writeLyricsFile(title: title, lyrics: lyrics);
    final tracks = <BackingTrack>[];

    if (sourceTrackPaths != null && !kIsWeb) {
      for (final entry in sourceTrackPaths.entries) {
        final slot = entry.key;
        if (slot < 1 || slot > 3) continue;
        final source = entry.value;
        if (source.trim().isEmpty) continue;
        final fileName = await copyBackingTrack(
          title: title,
          slot: slot,
          sourcePath: source,
        );
        tracks.add(
          BackingTrack(slot: slot, fileName: fileName, label: 'MR$slot'),
        );
      }
      tracks.sort((a, b) => a.slot.compareTo(b.slot));
    }

    final now = DateTime.now();
    return Song(
      id: id,
      title: title,
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
    String? lyrics,
    Map<int, String>? sourceTrackPaths,
  }) async {
    final nextTitle = title.trim().isEmpty ? song.title : title.trim();
    final nextLyrics = lyrics ?? song.lyricsText;
    final nextLyricsPath = await writeLyricsFile(
      title: nextTitle,
      lyrics: nextLyrics,
    );

    final nextTracks = <BackingTrack>[];
    final oldTrackNamesToDelete = <String>{};

    for (final slot in [1, 2, 3]) {
      final replacementPath = sourceTrackPaths?[slot];
      final existingTrack = song.trackForSlot(slot);

      if (replacementPath != null && replacementPath.trim().isNotEmpty) {
        final fileName = await copyBackingTrack(
          title: nextTitle,
          slot: slot,
          sourcePath: replacementPath,
        );
        nextTracks.add(
          BackingTrack(slot: slot, fileName: fileName, label: 'MR$slot'),
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
            label: existingTrack.label,
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
        BackingTrack(slot: slot, fileName: renamedFileName, label: 'MR$slot'),
      );
    }

    if (!kIsWeb && song.lyricsPath != nextLyricsPath) {
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
    if (kIsWeb) {
      // Web has no writable local filesystem path for dart:io File.
      return buildLyricsFileName(title);
    }
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
    if (kIsWeb) {
      throw UnsupportedError('웹에서는 로컬 반주 파일 복사를 지원하지 않습니다.');
    }
    final dir = await _mrDir;
    final fileName = buildBackingTrackFileName(title, slot);
    final dest = File('${dir.path}/$fileName');
    await File(sourcePath).copy(dest.path);
    return fileName;
  }

  Future<String> copyMr({
    required String title,
    required String sourcePath,
  }) async {
    return copyBackingTrack(title: title, slot: 1, sourcePath: sourcePath);
  }

  Future<String?> getBackingTrackPath(String fileName) async {
    if (kIsWeb) return null;
    final file = await _findBackingTrackFile(fileName);
    return file?.path;
  }

  Future<String?> getMrPath(String mrFileName) =>
      getBackingTrackPath(mrFileName);

  Future<void> deleteSong(Song song) async {
    if (kIsWeb) return;
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
