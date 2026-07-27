// file: lib/repository/song_meta_store.dart
//
// 곡 메타데이터를 data/songs.json에 저장하고 가사 파일을 함께 로드한다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';

/// songs.json 스키마 버전을 다루다 생긴 문제를 호출자에게 알린다.
class SongMetaSchemaException implements Exception {
  final String message;

  const SongMetaSchemaException(this.message);

  @override
  String toString() => message;
}

class SongMetaStore {
  /// 이 빌드가 읽고 쓸 수 있는 songs.json 스키마 버전.
  ///
  /// v1: 최상위가 곡 배열 (버전 필드 없음)
  /// v2: `{"schemaVersion": 2, "songs": [...]}` 봉투
  static const int schemaVersion = 2;

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

      final entries = decodeEntries(raw);
      final songs = <Song>[];
      for (final json in entries) {
        final lyricsText = await _readLyricsForMeta(json);
        songs.add(Song.fromMetaJson(json, lyricsText: lyricsText));
      }
      return songs;
    } on SongMetaSchemaException {
      // 상위 버전 파일을 구버전 앱이 덮어써 데이터를 잃는 상황을 막기 위해
      // 삼키지 않고 호출자에게 그대로 전달한다.
      rethrow;
    } catch (e, stack) {
      debugPrint('songs.json 로드 실패: $e\n$stack');
      return [];
    }
  }

  /// v1(맨 배열)과 v2(봉투)를 모두 읽는다. 상위 버전은 거부한다.
  @visibleForTesting
  static List<Map<String, dynamic>> decodeEntries(String raw) {
    final decoded = jsonDecode(raw);

    if (decoded is List) {
      // v1 레거시 — 다음 저장 때 v2 봉투로 승격된다.
      return _castEntries(decoded);
    }

    if (decoded is Map<String, dynamic>) {
      final map = decoded.cast<String, dynamic>();
      final version = (map['schemaVersion'] as num?)?.toInt() ?? schemaVersion;
      if (version > schemaVersion) {
        throw SongMetaSchemaException(
          '곡 데이터 버전이 $version이라 이 앱 버전(최대 $schemaVersion)에서는 열 수 없습니다. '
          '앱을 최신 버전으로 업데이트해 주세요.',
        );
      }
      final songs = map['songs'];
      if (songs is List) {
        return _castEntries(songs);
      }
      return const [];
    }

    return const [];
  }

  static List<Map<String, dynamic>> _castEntries(List<dynamic> raw) {
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<void> save(List<Song> songs) async {
    final file = await _songsFile;
    final payload = {
      'schemaVersion': schemaVersion,
      'songs': songs.map((song) => song.toMetaJson()).toList(),
    };
    final raw = const JsonEncoder.withIndent('  ').convert(payload);
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
