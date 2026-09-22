// file: lib/services/daily_goal_service.dart
//
// 일일 루틴 체크 기록의 저장·조회.
//
// 🔴 v5.17.0: 쓰기는 공용 헬퍼(atomic_json_file.dart)로 한다. 연습이 끝날 때 기다리지
// 않고 도는 자동 체크와 손으로 누른 체크가 겹칠 수 있는데, 예전에는 정본을 곧바로
// 덮어썼고 못 읽은 파일을 빈 기록으로 읽었다 — 그 다음 체크가 연속일 기록을 통째로
// 지운다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/vocal_routine.dart';
import 'atomic_json_file.dart';

/// daily_goals.json 본문을 만든다. (순수 함수)
String encodeDailyGoals(Map<String, DailyGoalLog> logs) {
  return const JsonEncoder.withIndent('  ').convert({
    'schemaVersion': DailyGoalStore.schemaVersion,
    'logs': logs.values.map((l) => l.toJson()).toList(),
  });
}

/// daily_goals.json 본문을 날짜별 기록으로 푼다. 못 읽으면 null. (순수 함수)
///
/// 🔴 「못 읽음(null)」과 「빈 기록({})」을 가른다. 빈 파일·잘린 JSON을 빈 기록으로
/// 읽으면 다음 체크가 기록 전체를 지운다. 상위 버전은 null이 아니라
/// [AtomicSchemaException]이다 — null이면 헬퍼가 「깨진 파일」로 보고 첫 저장에서
/// `.corrupt-`로 옮긴 뒤 구버전 봉투로 갈아 끼운다.
Map<String, DailyGoalLog>? decodeDailyGoals(String raw) {
  final text = stripBom(raw);
  if (text.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) return null;
    final version = (decoded['schemaVersion'] as num?)?.toInt() ?? 1;
    if (version > DailyGoalStore.schemaVersion) {
      throw AtomicSchemaException(
        'daily_goals.json 버전($version)이 이 앱 버전(최대 '
        '${DailyGoalStore.schemaVersion})보다 높아 읽지 않습니다. 앱을 업데이트해 주세요.',
      );
    }
    final logs = decoded['logs'];
    if (logs is! List) return null;

    final result = <String, DailyGoalLog>{};
    for (final entry in logs.whereType<Map<dynamic, dynamic>>()) {
      final log = DailyGoalLog.fromJson(entry.cast<String, dynamic>());
      if (log.date.isNotEmpty) result[log.date] = log;
    }
    return result;
  } on AtomicSchemaException {
    rethrow;
  } catch (e) {
    debugPrint('daily_goals.json 해석 실패: $e');
    return null;
  }
}

class DailyGoalStore {
  static const int schemaVersion = 1;

  /// 데이터 폴더의 뿌리(기본: 문서 폴더). 테스트는 임시 폴더를 준다.
  final Future<Directory> Function() _baseDirBuilder;

  late final AtomicJsonFile<Map<String, DailyGoalLog>> _goals;

  DailyGoalStore({
    Future<Directory> Function()? baseDirBuilder,
    Duration ioRetryDelay = kAtomicIoRetryDelay,
  }) : _baseDirBuilder = baseDirBuilder ?? getApplicationDocumentsDirectory {
    _goals = AtomicJsonFile<Map<String, DailyGoalLog>>(
      fileBuilder: () => _file,
      encode: encodeDailyGoals,
      decode: decodeDailyGoals,
      isEmpty: (logs) => logs.isEmpty,
      label: 'daily_goals.json',
      // 못 열고 시작한 기록으로 저장해도 정본에만 있던 날짜가 사라지지 않게 한다.
      rescue: AtomicRescue.mapByKey<DailyGoalLog>(),
      ioRetryDelay: ioRetryDelay,
    );
  }

  /// 마지막 [load]가 기록을 어디서 읽었는지(정본·백업·읽지 못함).
  AtomicLoadState get lastLoadState => _goals.lastLoadState;

  Future<File> get _file async {
    final base = await _baseDirBuilder();
    final dir = Directory('${base.path}/data');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/daily_goals.json');
  }

  /// 기록을 읽는다. 정본을 못 읽으면 `.bak`에서 되살리고, 둘 다 안 되면 {}.
  ///
  /// 상위 버전 파일은 빈 기록이지만 [lastLoadState]가 unreadable로 서고, 헬퍼가
  /// 그 정본을 어떤 저장으로도 덮지 않는다(save는 false).
  Future<Map<String, DailyGoalLog>> load() async {
    try {
      return await _goals.load() ?? {};
    } on AtomicSchemaException catch (e) {
      debugPrint('$e');
      return {};
    }
  }

  /// 기록을 저장한다. 디스크에 닿았으면 true. 호출 순서대로 한 줄에 선다.
  Future<bool> save(Map<String, DailyGoalLog> logs) => _goals.save(logs);
}

class DailyGoalService {
  final DailyGoalStore _store;

  Map<String, DailyGoalLog> _logs = {};

  DailyGoalService({DailyGoalStore? store})
    : _store = store ?? DailyGoalStore();

  Map<String, DailyGoalLog> get logs => Map.unmodifiable(_logs);

  /// 마지막 [load]가 기록을 어디서 읽었는지(정본·백업·읽지 못함).
  AtomicLoadState get loadState => _store.lastLoadState;

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

  /// 그날의 기록을 바꿔 끼우고 저장한다. 디스크에 닿았으면 true.
  Future<bool> put(DailyGoalLog log) {
    _logs = {..._logs, log.date: log};
    return _store.save(_logs);
  }

  /// 따라하기 세션이 끝낸 단계를 체크한다(이미 체크돼 있으면 그대로).
  Future<DailyGoalLog> markStepDone(String stepId, {DateTime? now}) async {
    final log = today(now: now);
    final next = log.markDone(stepId);
    if (!identical(next, log)) await put(next);
    return next;
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
