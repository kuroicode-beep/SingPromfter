// file: lib/repository/practice_log_store.dart
//
// 연습 세션 로그를 data/practice_log.json에 저장한다.
// songs.json과 분리하는 이유: 즐겨찾기 토글마다 재작성되는 핫 파일에
// 무한히 늘어나는 로그를 섞지 않고, 곡이 삭제돼도 기록은 남기기 위해서다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/practice_session.dart';

class PracticeLogStore {
  /// 처음부터 봉투 형식으로 저장한다(맨 배열 실수 반복 금지).
  static const int schemaVersion = 1;

  Future<Directory> get _dataDir async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/data');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> get _logFile async =>
      File('${(await _dataDir).path}/practice_log.json');

  Future<List<PracticeSession>> load() async {
    try {
      final file = await _logFile;
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return [];
      final version = (decoded['schemaVersion'] as num?)?.toInt() ?? 1;
      if (version > schemaVersion) {
        debugPrint('practice_log.json 버전($version)이 높아 읽지 않는다.');
        return [];
      }
      final sessions = decoded['sessions'];
      if (sessions is! List) return [];
      return sessions
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => PracticeSession.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (e, stack) {
      debugPrint('practice_log.json 로드 실패: $e\n$stack');
      return [];
    }
  }

  Future<void> save(List<PracticeSession> sessions) async {
    try {
      final file = await _logFile;
      final payload = {
        'schemaVersion': schemaVersion,
        'sessions': sessions.map((s) => s.toJson()).toList(),
      };
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
      );
    } catch (e, stack) {
      debugPrint('practice_log.json 저장 실패: $e\n$stack');
    }
  }
}
