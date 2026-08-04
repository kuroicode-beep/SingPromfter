// file: lib/models/routine_step_spec.dart
//
// 따라하기 세션이 쓰는 스텝별 실행 스펙 — vocal_routine.dart 의 const 데이터는
// 표시용 그대로 두고, 실행 동작(호흡 박자·스케일 종류)은 여기 병렬 테이블이
// RoutineStep.id 로 소유한다. 17개 스텝 전부 등록돼 있어야 한다(테스트 강제).

/// 스케일 트레이닝의 남/녀 음역. 설정(trainingVoiceRange)으로 고른다.
enum TrainingVoiceRange {
  male,
  female;

  String get label => switch (this) {
    TrainingVoiceRange.male => '남성',
    TrainingVoiceRange.female => '여성',
  };

  /// 설정 JSON 문자열 → enum. 모르는 값은 남성(기본).
  static TrainingVoiceRange fromStorage(String? raw) =>
      raw == 'female' ? TrainingVoiceRange.female : TrainingVoiceRange.male;

  /// 스케일 런 루트의 MIDI 범위 — 남성 C3~C4, 여성 F3~F4(+5반음).
  /// 평균적인 비훈련 남성 편안 음역(A2~A4) 기준 정점 G4, 여성은 완전4도 위.
  int get rootLow => this == TrainingVoiceRange.male ? 48 : 53;
  int get rootHigh => this == TrainingVoiceRange.male ? 60 : 65;
}

/// 호흡 한 블록 — 들숨/멈춤/날숨 박자와 반복 수. 1박 = 60/bpm 초.
class BreathingPattern {
  final int inhaleBeats;
  final int holdBeats;
  final int exhaleBeats;
  final int reps;
  final int bpm;

  const BreathingPattern({
    required this.inhaleBeats,
    this.holdBeats = 0,
    required this.exhaleBeats,
    required this.reps,
    this.bpm = 60,
  });

  Duration get beat => Duration(milliseconds: 60000 ~/ bpm);
}

/// 스케일 스텝의 종류 — 사이렌(음성 안내만) / 5음 스케일(피아노 동반).
enum ScaleKind { siren, fiveTone }

/// 스텝 하나의 실행 스펙.
class RoutineStepSpec {
  /// 스텝 시작 시 낭독할 클립 id (voice_clips.dart 의 `step_<id>`).
  final String announceClipId;

  /// 호흡 스텝이면 블록 목록(순서대로 수행). 아니면 빈 리스트.
  final List<BreathingPattern> breathing;

  /// 스케일 스텝이면 종류. 아니면 null.
  final ScaleKind? scale;

  const RoutineStepSpec({
    required this.announceClipId,
    this.breathing = const [],
    this.scale,
  });
}

/// 스텝 id → 실행 스펙 테이블.
class RoutineStepSpecs {
  RoutineStepSpecs._();

  static const Map<String, RoutineStepSpec> all = {
    // ── 10분 데일리 ──
    'mini10-breathing': RoutineStepSpec(
      announceClipId: 'step_mini10-breathing',
      breathing: [
        BreathingPattern(inhaleBeats: 4, exhaleBeats: 8, reps: 4),
      ],
    ),
    'mini10-warmup': RoutineStepSpec(announceClipId: 'step_mini10-warmup'),
    'mini10-scale': RoutineStepSpec(
      announceClipId: 'step_mini10-scale',
      scale: ScaleKind.siren,
    ),
    'mini10-diction': RoutineStepSpec(announceClipId: 'step_mini10-diction'),

    // ── 30분 기본 ──
    'short30-breathing': RoutineStepSpec(
      announceClipId: 'step_short30-breathing',
      breathing: [
        BreathingPattern(inhaleBeats: 4, exhaleBeats: 8, reps: 4),
      ],
    ),
    'short30-warmup': RoutineStepSpec(announceClipId: 'step_short30-warmup'),
    'short30-scale': RoutineStepSpec(
      announceClipId: 'step_short30-scale',
      scale: ScaleKind.fiveTone,
    ),
    'short30-diction': RoutineStepSpec(announceClipId: 'step_short30-diction'),
    'short30-routine': RoutineStepSpec(announceClipId: 'step_short30-routine'),
    'short30-target': RoutineStepSpec(announceClipId: 'step_short30-target'),

    // ── 60분 집중 ── (호흡은 8박 → 12박 점진 확장: 블록 2개)
    'long60-breathing': RoutineStepSpec(
      announceClipId: 'step_long60-breathing',
      breathing: [
        BreathingPattern(inhaleBeats: 4, exhaleBeats: 8, reps: 3),
        BreathingPattern(inhaleBeats: 4, exhaleBeats: 12, reps: 3),
      ],
    ),
    'long60-warmup': RoutineStepSpec(announceClipId: 'step_long60-warmup'),
    'long60-scale': RoutineStepSpec(
      announceClipId: 'step_long60-scale',
      scale: ScaleKind.fiveTone,
    ),
    'long60-diction': RoutineStepSpec(announceClipId: 'step_long60-diction'),
    'long60-routine': RoutineStepSpec(announceClipId: 'step_long60-routine'),
    'long60-target': RoutineStepSpec(announceClipId: 'step_long60-target'),
    'long60-cooldown': RoutineStepSpec(
      announceClipId: 'step_long60-cooldown',
    ),
  };

  static RoutineStepSpec? byStepId(String stepId) => all[stepId];
}
