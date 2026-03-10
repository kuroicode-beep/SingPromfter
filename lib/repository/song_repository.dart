import 'dart:io';
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

  Future<Directory> get _lyricsDir async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/lyrics');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> get _mrDir async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/mr');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<Song>> loadSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSongsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return Song.decodeList(raw);
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
    final lyricsPath = await writeLyricsFile(id: id, lyrics: lyrics);
    final tracks = <BackingTrack>[];

    if (sourceTrackPaths != null) {
      for (final entry in sourceTrackPaths.entries) {
        final slot = entry.key;
        if (slot < 1 || slot > 3) continue;
        final source = entry.value;
        if (source.trim().isEmpty) continue;
        final fileName = await copyBackingTrack(
          id: id,
          slot: slot,
          sourcePath: source,
        );
        tracks.add(BackingTrack(slot: slot, fileName: fileName, label: 'MR$slot'));
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

  Future<String> writeLyricsFile({
    required String id,
    required String lyrics,
  }) async {
    final lyricsFile = File('${(await _lyricsDir).path}/$id.txt');
    await lyricsFile.writeAsString(lyrics);
    return lyricsFile.path;
  }

  Future<String> copyBackingTrack({
    required String id,
    required int slot,
    required String sourcePath,
  }) async {
    final dir = await _mrDir;
    final ext = sourcePath.contains('.') ? sourcePath.split('.').last : 'mp3';
    final fileName = '$id-slot$slot.$ext';
    final dest = File('${dir.path}/$fileName');
    await File(sourcePath).copy(dest.path);
    return fileName;
  }

  Future<String> copyMr({
    required String id,
    required String sourcePath,
  }) async {
    return copyBackingTrack(id: id, slot: 1, sourcePath: sourcePath);
  }

  Future<String?> getBackingTrackPath(String fileName) async {
    final dir = await _mrDir;
    final file = File('${dir.path}/$fileName');
    return await file.exists() ? file.path : null;
  }

  Future<String?> getMrPath(String mrFileName) => getBackingTrackPath(mrFileName);

  Future<void> deleteSong(Song song) async {
    final lyricsPath = song.lyricsPath;
    final lyricsFile = File(lyricsPath);
    if (await lyricsFile.exists()) {
      await lyricsFile.delete();
    } else {
      final legacyLyricsFile = File('${(await _lyricsDir).path}/${song.id}.txt');
      if (await legacyLyricsFile.exists()) await legacyLyricsFile.delete();
    }

    for (final track in song.backingTracks) {
      final mrFile = File('${(await _mrDir).path}/${track.fileName}');
      if (await mrFile.exists()) await mrFile.delete();
    }
  }
}

