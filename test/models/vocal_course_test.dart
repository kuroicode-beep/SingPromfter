// file: test/models/vocal_course_test.dart
//
// 4주 코스 주차 계산과 주간/월간 달성 집계.
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/vocal_course.dart';
import 'package:singpromfter_app/models/vocal_routine.dart';

DailyGoalLog completeLog(DateTime day) {
  final routine = VocalRoutines.mini;
  return DailyGoalLog(
    date: dateKey(day),
    routineId: routine.id,
    completedStepIds: {for (final s in routine.steps) s.id},
  );
}

void main() {
  group('VocalCourse.weekFor', () {
    final start = DateTime(2026, 8, 3); // 월요일

    test('시작 주는 1주차, 7일 뒤 2주차, 4주 뒤엔 다시 1주차(2회차)', () {
      expect(VocalCourse.weekFor(start, DateTime(2026, 8, 3)).number, 1);
      expect(VocalCourse.weekFor(start, DateTime(2026, 8, 9)).number, 1);
      expect(VocalCourse.weekFor(start, DateTime(2026, 8, 10)).number, 2);
      expect(VocalCourse.weekFor(start, DateTime(2026, 8, 31)).number, 1);
      expect(VocalCourse.cycleFor(start, DateTime(2026, 8, 31)), 2);
    });

    test('시작일 이전이면 1주차로 본다', () {
      expect(VocalCourse.weekFor(start, DateTime(2026, 8, 1)).number, 1);
    });
  });

  group('주간/월간 달성 집계', () {
    test('이번 주(월요일 시작)에 완주한 날만 센다', () {
      // 2026-08-05(수) 기준 — 월·화 완주, 지난주 완주는 무시.
      final logs = {
        for (final d in [
          DateTime(2026, 8, 3),
          DateTime(2026, 8, 4),
          DateTime(2026, 7, 31),
        ])
          dateKey(d): completeLog(d),
      };
      expect(
        completedDaysThisWeek(logs: logs, today: DateTime(2026, 8, 5)),
        2,
      );
    });

    test('이번 달 완주 일수', () {
      final logs = {
        for (final d in [
          DateTime(2026, 8, 1),
          DateTime(2026, 8, 3),
          DateTime(2026, 7, 30),
        ])
          dateKey(d): completeLog(d),
      };
      expect(
        completedDaysThisMonth(logs: logs, today: DateTime(2026, 8, 5)),
        2,
      );
    });

    test('요일 점 — 완주 true·미완주 false·미래 null', () {
      final logs = {
        dateKey(DateTime(2026, 8, 3)): completeLog(DateTime(2026, 8, 3)),
      };
      final dots = weekCompletionDots(
        logs: logs,
        today: DateTime(2026, 8, 5),
      );
      expect(dots[0], isTrue); // 월 완주
      expect(dots[1], isFalse); // 화 미완주
      expect(dots[2], isFalse); // 수(오늘) 아직 미완주
      expect(dots[3], isNull); // 목 미래
      expect(dots, hasLength(7));
    });
  });
}
