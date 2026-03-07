import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

const _kSongsKey = 'singpromfter_songs';

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

  Future<Song> addSong({
    required String id,
    required String title,
    required String lyrics,
    String? sourceMrPath,
  }) async {
    String? mrFileName;
    if (sourceMrPath != null) {
      mrFileName = await copyMr(id: id, sourcePath: sourceMrPath);
    }
    final lyricsFile = File('${(await _lyricsDir).path}/$id.txt');
    await lyricsFile.writeAsString(lyrics);

    return Song(id: id, title: title, lyrics: lyrics, mrFileName: mrFileName);
  }

  Future<String> copyMr({
    required String id,
    required String sourcePath,
  }) async {
    final dir = await _mrDir;
    final ext = sourcePath.split('.').last;
    final fileName = '$id.$ext';
    final dest = File('${dir.path}/$fileName');
    await File(sourcePath).copy(dest.path);
    return fileName;
  }

  Future<String?> getMrPath(String mrFileName) async {
    final dir = await _mrDir;
    final file = File('${dir.path}/$mrFileName');
    return await file.exists() ? file.path : null;
  }

  Future<void> deleteSong(Song song) async {
    final lyricsFile = File('${(await _lyricsDir).path}/${song.id}.txt');
    if (await lyricsFile.exists()) await lyricsFile.delete();
    if (song.mrFileName != null) {
      final mrFile = File('${(await _mrDir).path}/${song.mrFileName}');
      if (await mrFile.exists()) await mrFile.delete();
    }
  }
}
