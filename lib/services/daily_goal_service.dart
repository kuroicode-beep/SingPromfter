// file: lib/services/daily_goal_service.dart
//
// 일일 루틴 체크 기록의 저장·조회.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/vocal_routine.dart';

class DailyGoalStore {
  static const int schemaVersion = 1;

  Future<File> get _file async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/data');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/daily_goals.json');
  }

  Future<Map<String, DailyGoalLog>> load() async {
    try {
      final file = await _file;
      if (!await file.exists()) return {};
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return {};

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};
      final version = (decoded['schemaVersion'] as num?)?.toInt() ?? 1;
      if (version > schemaVersion) {
        debugPrint('daily_goals.json 버전($version)이 높아 읽지 않는다.');
        return {};
      }
      final logs = decoded['logs'];
      if (logs is! List) return {};

      final result = <String, DailyGoalLog>{};
      for (final entry in logs.whereType<Map<dynamic, dynamic>>()) {
        final log = DailyGoalLog.fromJson(entry.cast<String, dynamic>());
        if (log.date.isNotEmpty) result[log.date] = log;
      }
      return result;
    } catch (e, stack) {
      debugPrint('daily_goals.json 로드 실패: $e\n$stack');
      return {};
    }
  }

  Future<void> save(Map<String, DailyGoalLog> logs) async {
    try {
      final file = await _file;
      final payload = {
        'schemaVersion': schemaVersion,
        'logs': logs.values.map((l) => l.toJson()).toList(),
      };
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
      );
    } catch (e, stack) {
      debugPrint('daily_goals.json 저장 실패: $e\n$stack');
    }
  }
}

class DailyGoalService {
  final DailyGoalStore _store;

  Map<String, DailyGoalLog> _logs = {};

  DailyGoalService({DailyGoalStore? store})
    : _store = store ?? DailyGoalStore();

  Map<String, DailyGoalLog> get logs => Map.unmodifiable(_logs);

  Future<void> load() async {
    _logs = await _store.load();
  }

  /// 오늘 기록. 없으면 기본 루틴으로 새로 만든다.
  DailyGoalLog today({DateTime? now, String? routineId}) {
    final key = dateKey(now ?? DateTime.now());
    return _logs[key] ??
        DailyGoalLog(
          date: key,
          routineId: routineId ?? VocalRoutines.short.id,
        );
  }

  int streak({DateTime? now}) =>
      calculateStreak(logs: _logs, today: now ?? DateTime.now());

  /// 최근 [days]일 중 달성한 날 수.
  int completedInLast(int days, {DateTime? now}) {
    final today = now ?? DateTime.now();
    var count = 0;
    for (var i = 0; i < days; i++) {
      final log = _logs[dateKey(today.subtract(Duration(days: i)))];
      if (log == null) continue;
      if (log.isComplete(VocalRoutines.byId(log.routineId))) count += 1;
    }
    return count;
  }

  Future<void> put(DailyGoalLog log) async {
    _logs = {..._logs, log.date: log};
    await _store.save(_logs);
  }

  Future<DailyGoalLog> toggleStep(DailyGoalLog log, String stepId) async {
    final next = log.toggle(stepId);
    await put(next);
    return next;
  }

  Future<DailyGoalLog> changeRoutine(DailyGoalLog log, String routineId) async {
    // 루틴을 바꾸면 이전 단계 체크는 의미가 없으므로 비운다.
    final next = log.copyWith(routineId: routineId, completedStepIds: {});
    await put(next);
    return next;
  }

  /// 곡 연습 1회로 아직 남은 곡 단계(루틴곡 → 목표곡 순)를 하나 체크한다.
  ///
  /// 루틴곡이 이미 완료면 목표곡을 체크한다 — 두 곡 단계 모두
  /// 실제 연습으로 채워지도록 한다.
  Future<DailyGoalLog?> autoCompleteNextSongStep({DateTime? now}) async {
    final routine = await autoCompleteSongStep(
      kind: RoutineStepKind.routineSong,
      now: now,
    );
    if (routine != null) return routine;
    return autoCompleteSongStep(
      kind: RoutineStepKind.targetSong,
      now: now,
    );
  }

  /// 곡을 실제로 연습하면 해당 단계를 자동으로 체크한다.
  ///
  /// 수동 체크만 있는 루틴 앱과 달리 "실제로 부른 것"만 인정되므로
  /// 트레이닝 기록의 신뢰도가 올라간다.
  Future<DailyGoalLog?> autoCompleteSongStep({
    required RoutineStepKind kind,
    DateTime? now,
  }) async {
    final log = today(now: now);
    final routine = VocalRoutines.byId(log.routineId);
    final step = routine.steps.where((s) => s.kind == kind).firstOrNull;
    if (step == null || log.isDone(step.id)) return null;

    final next = log.markDone(step.id);
    await put(next);
    return next;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
