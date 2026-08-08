// file: lib/services/recording_library_service.dart
//
// 녹음 테이크 목록의 저장·필터. 순수 로직과 I/O를 나눠 둔다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/recording_take.dart';
import '../utils/korean_text.dart';

/// 목록 필터 — 순수 함수라 파일 없이 테스트한다.
class RecordingFilter {
  RecordingFilter._();

  static List<RecordingTake> apply(
    List<RecordingTake> takes, {
    String query = '',
    RecordingFilterMode mode = RecordingFilterMode.all,
    String? songId,
  }) {
    final trimmed = query.trim();
    return takes.where((take) {
      if (songId != null && take.songId != songId) return false;

      switch (mode) {
        case RecordingFilterMode.all:
          break;
        case RecordingFilterMode.rated:
          if (!take.isRated) return false;
        case RecordingFilterMode.commented:
          if (!take.hasComment) return false;
        case RecordingFilterMode.keep:
          if (!take.isKeep) return false;
      }

      if (trimmed.isEmpty) return true;
      return KoreanText.matches(take.songTitle, trimmed) ||
          KoreanText.matches(take.comment, trimmed);
    }).toList(growable: false);
  }

  /// 최근 녹음이 위로 오도록 정렬한다.
  static List<RecordingTake> sortByNewest(List<RecordingTake> takes) {
    final sorted = List<RecordingTake>.from(takes)
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return List.unmodifiable(sorted);
  }
}

class RecordingStore {
  /// v2: 반주 조각·믹스 설정·분리 보컬 필드 추가 (additive — v1 파일 그대로 읽힘).
  static const int schemaVersion = 2;

  Future<Directory> get recordingsDir async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/data/recordings');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> get _indexFile async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/data');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/recordings.json');
  }

  Future<List<RecordingTake>> load() async {
    try {
      final file = await _indexFile;
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return [];
      final version = (decoded['schemaVersion'] as num?)?.toInt() ?? 1;
      if (version > schemaVersion) {
        debugPrint('recordings.json 버전($version)이 높아 읽지 않는다.');
        return [];
      }
      final takes = decoded['takes'];
      if (takes is! List) return [];
      return takes
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => RecordingTake.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (e, stack) {
      debugPrint('recordings.json 로드 실패: $e\n$stack');
      return [];
    }
  }

  Future<void> save(List<RecordingTake> takes) async {
    try {
      final file = await _indexFile;
      final payload = {
        'schemaVersion': schemaVersion,
        'takes': takes.map((t) => t.toJson()).toList(),
      };
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
      );
    } catch (e, stack) {
      debugPrint('recordings.json 저장 실패: $e\n$stack');
    }
  }

  Future<String> pathFor(String fileName) async =>
      '${(await recordingsDir).path}/$fileName';

  Future<void> deleteFile(String fileName) async {
    try {
      final file = File(await pathFor(fileName));
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('녹음 파일 삭제 실패($fileName): $e');
    }
  }
}

class RecordingLibraryService {
  final RecordingStore _store;

  List<RecordingTake> _takes = [];

  RecordingLibraryService({RecordingStore? store})
    : _store = store ?? RecordingStore();

  List<RecordingTake> get takes => RecordingFilter.sortByNewest(_takes);

  Future<void> load() async {
    _takes = await _store.load();
  }

  Future<void> add(RecordingTake take) async {
    _takes = [..._takes, take];
    await _store.save(_takes);
  }

  Future<void> update(RecordingTake take) async {
    _takes = _takes.map((t) => t.id == take.id ? take : t).toList();
    await _store.save(_takes);
  }

  Future<void> remove(RecordingTake take) async {
    // 보컬 원본과 함께 부속 파일(반주 조각·믹스·분리 보컬)도 지운다.
    await _store.deleteFile(take.fileName);
    for (final attached in [
      take.accompanimentFileName,
      take.mixedFileName,
      take.separatedFileName,
    ]) {
      if (attached != null && attached.isNotEmpty) {
        await _store.deleteFile(attached);
      }
    }
    _takes = _takes.where((t) => t.id != take.id).toList();
    await _store.save(_takes);
  }

  Future<String> pathFor(RecordingTake take) => _store.pathFor(take.fileName);

  Future<Directory> directory() => _store.recordingsDir;
}
