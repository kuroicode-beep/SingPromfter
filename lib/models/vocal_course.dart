// file: lib/models/vocal_course.dart
//
// 4주 보컬 트레이닝 코스 — 주차별 테마와 주간 목표.
//
// 널리 통용되는 발성 교육 순서(호흡 지지 → 음정·음역 → 딕션·리듬 →
// 곡 통합)를 주 단위로 배치한 자체 코스다. 30일 커리큘럼형 프로그램들의
// "주차 테마 + 매일 짧게" 구조를 참고했고 특정 유료 프로그램의 복제가
// 아니다. 4주를 마치면 1주차부터 다시 돈다(심화 반복).
import 'vocal_routine.dart';

class CourseWeek {
  final int number;
  final String theme;
  final String focus;
  final String tip;

  /// 이 주에 루틴을 완주해야 하는 날 수(주간 목표).
  final int targetDays;

  const CourseWeek({
    required this.number,
    required this.theme,
    required this.focus,
    required this.tip,
    required this.targetDays,
  });
}

class VocalCourse {
  VocalCourse._();

  static const List<CourseWeek> weeks = [
    CourseWeek(
      number: 1,
      theme: '호흡과 지지',
      focus: '복식호흡을 몸에 붙이는 주. 루틴의 호흡 단계에 가장 정성을 들입니다.',
      tip: '어깨가 아니라 배가 움직여야 해요. 날숨을 조금씩 길게 — 8박 → 12박.',
      targetDays: 4,
    ),
    CourseWeek(
      number: 2,
      theme: '음정과 음역',
      focus: '스케일·사이렌 집중. 무리하지 않는 범위에서 반음씩 넓힙니다.',
      tip: '높은 음은 크게가 아니라 가볍게. 녹음해서 [음정 체크]로 확인해 보세요.',
      targetDays: 4,
    ),
    CourseWeek(
      number: 3,
      theme: '딕션과 리듬',
      focus: '가사가 또렷하게 들리는 주. 딕션 단계와 박자 맞추기에 집중합니다.',
      tip: '혀·턱 힘 빼기가 절반이에요. 프롬프터로 부르며 박자 어긋나는 줄을 찾아보세요.',
      targetDays: 4,
    ),
    CourseWeek(
      number: 4,
      theme: '곡 완성',
      focus: '목표곡 통합 주. 배운 것을 곡 하나에 전부 얹어 완성도를 올립니다.',
      tip: '어려운 구간만 끊어 반복한 뒤 전체를 이어 부르세요. 녹음 → AI 보정과 비교도 좋아요.',
      targetDays: 5,
    ),
  ];

  /// 코스 시작일 기준 오늘이 몇 주차인지(1~4, 4주 후엔 다시 1주차).
  static CourseWeek weekFor(DateTime startDate, DateTime today) {
    final days = today.difference(_dateOnly(startDate)).inDays;
    if (days < 0) return weeks.first;
    return weeks[(days ~/ 7) % weeks.length];
  }

  /// 코스 몇 회차인지(1부터). 4주를 다 돌면 2회차.
  static int cycleFor(DateTime startDate, DateTime today) {
    final days = today.difference(_dateOnly(startDate)).inDays;
    if (days < 0) return 1;
    return days ~/ (7 * weeks.length) + 1;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

/// 이번 주(월요일 시작)에 루틴을 완주한 날 수. (순수 함수)
int completedDaysThisWeek({
  required Map<String, DailyGoalLog> logs,
  required DateTime today,
}) {
  final monday = DateTime(
    today.year,
    today.month,
    today.day,
  ).subtract(Duration(days: today.weekday - 1));
  var count = 0;
  for (var i = 0; i < 7; i++) {
    final day = monday.add(Duration(days: i));
    if (day.isAfter(today)) break;
    final log = logs[dateKey(day)];
    if (log != null && log.isComplete(VocalRoutines.byId(log.routineId))) {
      count++;
    }
  }
  return count;
}

/// 이번 달에 루틴을 완주한 날 수. (순수 함수)
int completedDaysThisMonth({
  required Map<String, DailyGoalLog> logs,
  required DateTime today,
}) {
  var count = 0;
  for (var day = 1; day <= today.day; day++) {
    final log = logs[dateKey(DateTime(today.year, today.month, day))];
    if (log != null && log.isComplete(VocalRoutines.byId(log.routineId))) {
      count++;
    }
  }
  return count;
}

/// 이번 주 월~일 각 날의 완주 여부(오늘 이후는 null). (순수 함수)
List<bool?> weekCompletionDots({
  required Map<String, DailyGoalLog> logs,
  required DateTime today,
}) {
  final monday = DateTime(
    today.year,
    today.month,
    today.day,
  ).subtract(Duration(days: today.weekday - 1));
  return [
    for (var i = 0; i < 7; i++)
      () {
        final day = monday.add(Duration(days: i));
        if (day.isAfter(today)) return null;
        final log = logs[dateKey(day)];
        return log != null &&
            log.isComplete(VocalRoutines.byId(log.routineId));
      }(),
  ];
}
