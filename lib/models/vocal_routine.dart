// file: lib/models/vocal_routine.dart
//
// 일일 보컬 루틴. 널리 통용되는 발성 교육 구조(호흡 → 워밍업 → 스케일 →
// 곡 적용)를 따르며 특정 유료 프로그램을 옮긴 것이 아니다.
// 로컬 상수로 두어 런타임 네트워크 의존을 만들지 않는다.

enum RoutineStepKind {
  breathing,
  warmup,
  scale,
  diction,
  routineSong,
  targetSong,
  cooldown,
}

extension RoutineStepKindInfo on RoutineStepKind {
  /// 실제 곡을 재생하는 단계인지. 이 단계는 연습 로그로 자동 체크된다.
  bool get isSongStep =>
      this == RoutineStepKind.routineSong || this == RoutineStepKind.targetSong;

  String get label => switch (this) {
    RoutineStepKind.breathing => '호흡',
    RoutineStepKind.warmup => '워밍업',
    RoutineStepKind.scale => '스케일링',
    RoutineStepKind.diction => '딕션',
    RoutineStepKind.routineSong => '루틴곡',
    RoutineStepKind.targetSong => '목표곡',
    RoutineStepKind.cooldown => '쿨다운',
  };
}

class RoutineStep {
  final String id;
  final RoutineStepKind kind;
  final int minutes;
  final String guide;

  const RoutineStep({
    required this.id,
    required this.kind,
    required this.minutes,
    required this.guide,
  });

  String get title => '${kind.label} $minutes분';
}

class VocalRoutine {
  final String id;
  final String name;
  final List<RoutineStep> steps;

  const VocalRoutine({
    required this.id,
    required this.name,
    required this.steps,
  });

  int get totalMinutes =>
      steps.fold(0, (sum, step) => sum + step.minutes);

  /// 곡 재생으로 자동 체크되는 단계들.
  List<RoutineStep> get songSteps =>
      steps.where((s) => s.kind.isSongStep).toList(growable: false);
}

/// 기본 제공 루틴 3종.
class VocalRoutines {
  VocalRoutines._();

  /// 바쁜 날의 최소 루틴 — "짧아도 매일"이 원칙(꾸준함 > 강도).
  static const mini = VocalRoutine(
    id: 'mini10',
    name: '10분 데일리',
    steps: [
      RoutineStep(
        id: 'mini10-breathing',
        kind: RoutineStepKind.breathing,
        minutes: 3,
        guide: '복식호흡. 코로 4박 들이마시고 "스—" 소리로 8박 내쉬기 ×4회.',
      ),
      RoutineStep(
        id: 'mini10-warmup',
        kind: RoutineStepKind.warmup,
        minutes: 3,
        guide: '허밍과 립트릴. 편한 중음역에서 작게 — 크게가 아니라 편하게.',
      ),
      RoutineStep(
        id: 'mini10-scale',
        kind: RoutineStepKind.scale,
        minutes: 2,
        guide: '사이렌(저→고→저) 왕복. 무리 없는 범위에서 부드럽게.',
      ),
      RoutineStep(
        id: 'mini10-diction',
        kind: RoutineStepKind.diction,
        minutes: 2,
        guide: '"다다다-가가가" 빠르게, 혀·턱 힘 빼기. 간장공장 공장장 2회.',
      ),
    ],
  );

  static const short = VocalRoutine(
    id: 'short30',
    name: '30분 기본',
    steps: [
      RoutineStep(
        id: 'short30-breathing',
        kind: RoutineStepKind.breathing,
        minutes: 5,
        guide: '복식호흡. 4박 들이마시고 8박 동안 "스" 소리로 천천히 내쉬기 ×4회.',
      ),
      RoutineStep(
        id: 'short30-warmup',
        kind: RoutineStepKind.warmup,
        minutes: 4,
        guide: '립트릴(입술 털기)과 허밍. 편한 중음역에서 위아래로 부드럽게.',
      ),
      RoutineStep(
        id: 'short30-scale',
        kind: RoutineStepKind.scale,
        minutes: 5,
        guide: '5음 스케일 "마-메-미-모-무". 무리하지 않는 범위에서 반음씩 올리고 내리기.',
      ),
      RoutineStep(
        id: 'short30-diction',
        kind: RoutineStepKind.diction,
        minutes: 3,
        guide: '"레드 레더 옐로 레더" / "다다다-가가가" — 혀·턱을 깨워 발음을 또렷하게.',
      ),
      RoutineStep(
        id: 'short30-routine',
        kind: RoutineStepKind.routineSong,
        minutes: 7,
        guide: '편하게 부를 수 있는 곡으로 호흡과 발성을 적용해 보기.',
      ),
      RoutineStep(
        id: 'short30-target',
        kind: RoutineStepKind.targetSong,
        minutes: 6,
        guide: '도전 중인 곡. 어려운 구간만 끊어서 반복.',
      ),
    ],
  );

  static const long = VocalRoutine(
    id: 'long60',
    name: '60분 집중',
    steps: [
      RoutineStep(
        id: 'long60-breathing',
        kind: RoutineStepKind.breathing,
        minutes: 8,
        guide: '복식호흡 + 지속음. 4박 흡기 → 8박 "스" 날숨, 점차 길이 늘리기.',
      ),
      RoutineStep(
        id: 'long60-warmup',
        kind: RoutineStepKind.warmup,
        minutes: 7,
        guide: '립트릴, 허밍, 사이렌(저→고→저)으로 성대를 천천히 깨우기.',
      ),
      RoutineStep(
        id: 'long60-scale',
        kind: RoutineStepKind.scale,
        minutes: 10,
        guide: '5음 스케일과 아르페지오. 흉성·믹스·두성을 오가며 음역 확장.',
      ),
      RoutineStep(
        id: 'long60-diction',
        kind: RoutineStepKind.diction,
        minutes: 5,
        guide: '텅트위스터와 모음 연결("마-메-미-모-무"를 가사처럼). 자음은 짧고 또렷하게.',
      ),
      RoutineStep(
        id: 'long60-routine',
        kind: RoutineStepKind.routineSong,
        minutes: 14,
        guide: '익숙한 곡으로 전체를 부르며 호흡 지점과 모음 처리 점검.',
      ),
      RoutineStep(
        id: 'long60-target',
        kind: RoutineStepKind.targetSong,
        minutes: 13,
        guide: '목표곡 집중. 키를 바꿔 보며 편한 지점을 찾아도 좋습니다.',
      ),
      RoutineStep(
        id: 'long60-cooldown',
        kind: RoutineStepKind.cooldown,
        minutes: 3,
        guide: '가벼운 허밍으로 마무리. 성대를 식혀 줍니다.',
      ),
    ],
  );

  static const all = [mini, short, long];

  static VocalRoutine byId(String? id) {
    for (final routine in all) {
      if (routine.id == id) return routine;
    }
    return short;
  }
}

/// 하루치 목표 달성 기록.
class DailyGoalLog {
  /// yyyy-MM-dd
  final String date;
  final String routineId;
  final Set<String> completedStepIds;
  final String note;

  const DailyGoalLog({
    required this.date,
    required this.routineId,
    this.completedStepIds = const {},
    this.note = '',
  });

  bool isDone(String stepId) => completedStepIds.contains(stepId);

  DailyGoalLog toggle(String stepId) {
    final next = Set<String>.from(completedStepIds);
    if (!next.remove(stepId)) next.add(stepId);
    return copyWith(completedStepIds: next);
  }

  DailyGoalLog markDone(String stepId) {
    if (completedStepIds.contains(stepId)) return this;
    return copyWith(completedStepIds: {...completedStepIds, stepId});
  }

  DailyGoalLog copyWith({
    String? routineId,
    Set<String>? completedStepIds,
    String? note,
  }) {
    return DailyGoalLog(
      date: date,
      routineId: routineId ?? this.routineId,
      completedStepIds: completedStepIds ?? this.completedStepIds,
      note: note ?? this.note,
    );
  }

  /// 이 기록이 하루를 "달성"으로 볼 수 있는지 — 모든 단계를 마쳤을 때.
  bool isComplete(VocalRoutine routine) =>
      routine.steps.every((s) => completedStepIds.contains(s.id));

  double progress(VocalRoutine routine) {
    if (routine.steps.isEmpty) return 0;
    final done = routine.steps.where((s) => completedStepIds.contains(s.id));
    return done.length / routine.steps.length;
  }

  Map<String, dynamic> toJson() => {
    'date': date,
    'routineId': routineId,
    'completedStepIds': completedStepIds.toList(),
    'note': note,
  };

  factory DailyGoalLog.fromJson(Map<String, dynamic> json) {
    final raw = json['completedStepIds'];
    return DailyGoalLog(
      date: json['date'] as String? ?? '',
      routineId: json['routineId'] as String? ?? VocalRoutines.short.id,
      completedStepIds: raw is List
          ? raw.whereType<String>().toSet()
          : const <String>{},
      note: json['note'] as String? ?? '',
    );
  }
}

/// 날짜 키를 만든다. (순수 함수)
String dateKey(DateTime at) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${at.year}-${two(at.month)}-${two(at.day)}';
}

/// 오늘부터 거슬러 올라가며 연속으로 달성한 날 수를 센다. (순수 함수)
int calculateStreak({
  required Map<String, DailyGoalLog> logs,
  required DateTime today,
}) {
  var streak = 0;
  var cursor = today;
  while (true) {
    final log = logs[dateKey(cursor)];
    if (log == null) break;
    final routine = VocalRoutines.byId(log.routineId);
    if (!log.isComplete(routine)) break;
    streak += 1;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}
