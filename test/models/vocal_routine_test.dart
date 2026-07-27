import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/vocal_routine.dart';

DailyGoalLog logFor(DateTime day, {Set<String>? done, String? routineId}) {
  final routine = VocalRoutines.byId(routineId);
  return DailyGoalLog(
    date: dateKey(day),
    routineId: routine.id,
    completedStepIds: done ?? routine.steps.map((s) => s.id).toSet(),
  );
}

void main() {
  group('VocalRoutines', () {
    test('30분·60분 프리셋의 합계가 이름과 맞는다', () {
      expect(VocalRoutines.short.totalMinutes, 30);
      expect(VocalRoutines.long.totalMinutes, 60);
    });

    test('표준 구성 순서를 따른다 (호흡 → 워밍업 → 스케일 → 곡)', () {
      final kinds = VocalRoutines.short.steps.map((s) => s.kind).toList();
      expect(kinds.first, RoutineStepKind.breathing);
      expect(kinds[1], RoutineStepKind.warmup);
      expect(kinds[2], RoutineStepKind.scale);
      expect(kinds, contains(RoutineStepKind.routineSong));
      expect(kinds, contains(RoutineStepKind.targetSong));
    });

    test('모든 단계에 안내 문구가 있다', () {
      for (final routine in VocalRoutines.all) {
        for (final step in routine.steps) {
          expect(step.guide, isNotEmpty, reason: '${routine.id}/${step.id}');
          expect(step.minutes, greaterThan(0));
        }
      }
    });

    test('곡 단계만 자동 체크 대상이다', () {
      expect(RoutineStepKind.routineSong.isSongStep, isTrue);
      expect(RoutineStepKind.targetSong.isSongStep, isTrue);
      expect(RoutineStepKind.breathing.isSongStep, isFalse);
      expect(VocalRoutines.short.songSteps, hasLength(2));
    });

    test('알 수 없는 id는 기본 루틴', () {
      expect(VocalRoutines.byId('bogus').id, VocalRoutines.short.id);
      expect(VocalRoutines.byId(null).id, VocalRoutines.short.id);
    });
  });

  group('DailyGoalLog', () {
    final routine = VocalRoutines.short;

    test('토글은 켜고 끈다', () {
      var log = DailyGoalLog(date: '2026-07-28', routineId: routine.id);
      final stepId = routine.steps.first.id;

      expect(log.isDone(stepId), isFalse);
      log = log.toggle(stepId);
      expect(log.isDone(stepId), isTrue);
      log = log.toggle(stepId);
      expect(log.isDone(stepId), isFalse);
    });

    test('markDone은 이미 켜져 있으면 그대로 둔다', () {
      final stepId = routine.steps.first.id;
      final log = DailyGoalLog(
        date: '2026-07-28',
        routineId: routine.id,
      ).markDone(stepId);
      expect(identical(log.markDone(stepId), log), isTrue);
    });

    test('모든 단계를 마쳐야 달성이다', () {
      var log = DailyGoalLog(date: '2026-07-28', routineId: routine.id);
      for (final step in routine.steps.take(routine.steps.length - 1)) {
        log = log.markDone(step.id);
      }
      expect(log.isComplete(routine), isFalse);
      log = log.markDone(routine.steps.last.id);
      expect(log.isComplete(routine), isTrue);
    });

    test('진행률을 계산한다', () {
      var log = DailyGoalLog(date: '2026-07-28', routineId: routine.id);
      expect(log.progress(routine), 0);
      log = log.markDone(routine.steps.first.id);
      expect(log.progress(routine), closeTo(1 / routine.steps.length, 1e-9));
    });

    test('JSON 왕복', () {
      final log = DailyGoalLog(
        date: '2026-07-28',
        routineId: VocalRoutines.long.id,
        completedStepIds: {'a', 'b'},
        note: '메모',
      );
      final restored = DailyGoalLog.fromJson(log.toJson());
      expect(restored.date, '2026-07-28');
      expect(restored.routineId, VocalRoutines.long.id);
      expect(restored.completedStepIds, {'a', 'b'});
      expect(restored.note, '메모');
    });
  });

  group('dateKey', () {
    test('0을 채운 yyyy-MM-dd', () {
      expect(dateKey(DateTime(2026, 7, 8)), '2026-07-08');
      expect(dateKey(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });

  group('calculateStreak', () {
    final today = DateTime(2026, 7, 28);

    test('연속 달성일을 센다', () {
      final logs = {
        for (var i = 0; i < 3; i++)
          dateKey(today.subtract(Duration(days: i))):
              logFor(today.subtract(Duration(days: i))),
      };
      expect(calculateStreak(logs: logs, today: today), 3);
    });

    test('중간에 빠진 날이 있으면 거기서 끊긴다', () {
      final logs = {
        dateKey(today): logFor(today),
        // 어제 없음
        dateKey(today.subtract(const Duration(days: 2))):
            logFor(today.subtract(const Duration(days: 2))),
      };
      expect(calculateStreak(logs: logs, today: today), 1);
    });

    test('미완료 기록은 연속으로 치지 않는다', () {
      final logs = {
        dateKey(today): logFor(today, done: {'partial'}),
      };
      expect(calculateStreak(logs: logs, today: today), 0);
    });

    test('기록이 없으면 0', () {
      expect(calculateStreak(logs: const {}, today: today), 0);
    });
  });
}
