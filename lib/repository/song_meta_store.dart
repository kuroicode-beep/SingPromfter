// file: lib/repository/song_meta_store.dart
//
// 곡 메타데이터를 data/songs.json에 저장하고 가사 파일을 함께 로드한다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';

class SongMetaStore {
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

  Future<File> get _songsFile async =>
      File('${(await _dataDir).path}/songs.json');

  Future<bool> exists() async => (await _songsFile).exists();

  Future<List<Song>> load() async {
    final file = await _songsFile;
    if (!await file.exists()) return [];

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      final songs = <Song>[];
      for (final item in list) {
        final json = (item as Map).cast<String, dynamic>();
        final lyricsText = await _readLyricsForMeta(json);
        songs.add(Song.fromMetaJson(json, lyricsText: lyricsText));
      }
      return songs;
    } catch (e, stack) {
      debugPrint('songs.json 로드 실패: $e\n$stack');
      return [];
    }
  }

  Future<void> save(List<Song> songs) async {
    final file = await _songsFile;
    final raw = const JsonEncoder.withIndent(
      '  ',
    ).convert(songs.map((song) => song.toMetaJson()).toList());
    await file.writeAsString(raw);
  }

  Future<String> _readLyricsForMeta(Map<String, dynamic> json) async {
    final id = json['id'] as String? ?? '';
    final path = json['lyricsPath'] as String? ?? '';
    final candidates = <File>[
      if (path.isNotEmpty) File(path),
      if (id.isNotEmpty) File('${(await _lyricsDir).path}/$id.txt'),
    ];

    for (final file in candidates) {
      if (await file.exists()) {
        return (await file.readAsString()).trim();
      }
    }
    return '';
  }
}
