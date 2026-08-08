// file: test/controllers/training_session_controller_test.dart
//
// 따라하기 세션 상태기계 — 가짜 오디오 + 즉시 딜레이로 검증한다.
// 특정 클립에서 세션을 붙잡아 두는 홀드 게이트로 타이밍을 결정적으로 만든다.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/controllers/training_session_controller.dart';
import 'package:singpromfter_app/models/routine_step_spec.dart';
import 'package:singpromfter_app/models/vocal_routine.dart';
import 'package:singpromfter_app/services/guide_audio_service.dart';

/// 재생 호출을 기록만 하는 가짜 — holds에 등록된 클립은 test가 풀 때까지 대기.
class FakeGuideAudio implements GuideAudio {
  final played = <String>[];
  final pianoPlayed = <String>[];
  final holds = <String, Completer<void>>{};

  Completer<void>? hold(String clipId) => holds[clipId] = Completer<void>();

  @override
  Future<void> playVoice(String clipId) async {
    played.add(clipId);
    final gate = holds[clipId];
    if (gate != null) await gate.future;
  }

  @override
  Future<void> playVoiceSequence(
    Iterable<String> clipIds, {
    bool Function()? cancelled,
  }) async {
    for (final id in clipIds) {
      if (cancelled?.call() ?? false) return;
      await playVoice(id);
    }
  }

  @override
  Future<void> playPianoRun(String fileName) async {
    pianoPlayed.add(fileName);
  }

  @override
  Future<void> stopVoice() async {
    for (final gate in holds.values) {
      if (!gate.isCompleted) gate.complete();
    }
    holds.clear();
  }

  @override
  Future<void> stopPiano() async {}

  @override
  Future<void> stopAll() async {
    await stopVoice();
    await stopPiano();
  }

  @override
  Future<void> dispose() async {}
}

Future<void> _pumpUntil(
  bool Function() condition, {
  int maxTurns = 200000,
}) async {
  for (var i = 0; i < maxTurns; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('조건이 $maxTurns 턴 안에 성립하지 않음');
}

void main() {
  late FakeGuideAudio audio;
  late List<String> completed;
  late TrainingSessionController controller;
  var range = TrainingVoiceRange.male;

  setUp(() {
    audio = FakeGuideAudio();
    completed = [];
    range = TrainingVoiceRange.male;
    controller = TrainingSessionController(
      audio: audio,
      voiceRange: () => range,
      onStepCompleted: (id) async => completed.add(id),
      delayFn: (_) => Future<void>.delayed(Duration.zero),
    );
  });

  tearDown(() => controller.dispose());

  test('10분 데일리 전체 자동 진행 — 4스텝 모두 완료 체크', () async {
    await controller.start(VocalRoutines.mini);
    await _pumpUntil(
      () => controller.phase == TrainingSessionPhase.finished,
    );

    expect(completed, [
      'mini10-breathing',
      'mini10-warmup',
      'mini10-scale',
      'mini10-diction',
    ]);
    expect(audio.played.first, 'session_start');
    expect(audio.played, contains('step_mini10-breathing'));
    expect(audio.played, contains('breath_inhale'));
    expect(audio.played, contains('scale_intro_siren'));
    expect(audio.played.last, 'session_all_done');
    // 사이렌 루틴이라 피아노는 안 나온다.
    expect(audio.pianoPlayed, isEmpty);
  });

  test('코스 주차 번호를 주면 브리핑이 시작 직후 나온다', () async {
    audio.hold('step_mini10-breathing'); // 첫 스텝에서 붙잡아 두고 확인
    await controller.start(VocalRoutines.mini, courseWeekNumber: 2);
    await _pumpUntil(() => audio.played.contains('step_mini10-breathing'));

    expect(
      audio.played.take(3).toList(),
      ['session_start', 'course_week2', 'step_mini10-breathing'],
    );
    await controller.stop(silent: true);
  });

  test('skipStep은 체크 없이 다음 스텝으로 넘어간다', () async {
    audio.hold('breath_inhale'); // 호흡 실행 중에 붙잡는다
    await controller.start(VocalRoutines.mini);
    await _pumpUntil(() => audio.played.contains('breath_inhale'));

    await controller.skipStep();
    await _pumpUntil(
      () => controller.phase == TrainingSessionPhase.finished,
    );

    expect(completed, isNot(contains('mini10-breathing')));
    expect(completed, contains('mini10-warmup'));
    expect(audio.played, contains('session_skipped'));
  });

  test('restartStep은 같은 스텝 안내를 다시 시작한다', () async {
    audio.hold('breath_inhale');
    await controller.start(VocalRoutines.mini);
    await _pumpUntil(() => audio.played.contains('breath_inhale'));

    await controller.restartStep();
    await _pumpUntil(
      () =>
          audio.played
              .where((id) => id == 'step_mini10-breathing')
              .length >=
          2,
    );

    expect(audio.played, contains('session_restart_step'));
    expect(controller.stepIndex, 0);
    await controller.stop(silent: true);
  });

  test('pause는 시간이 멈추고 resume으로 이어진다', () async {
    audio.hold('breath_inhale');
    await controller.start(VocalRoutines.mini);
    await _pumpUntil(() => audio.played.contains('breath_inhale'));

    await controller.pause();
    expect(controller.paused, isTrue);
    expect(audio.played, contains('session_paused'));

    await controller.resume();
    expect(controller.paused, isFalse);
    expect(audio.played, contains('session_resume'));
    await controller.stop(silent: true);
  });

  test('여성 음역이면 5음 스케일 피아노 런이 F3(53)부터 나온다', () async {
    range = TrainingVoiceRange.female;
    // 30분 기본의 스케일 스텝만 도려내 짧은 루틴으로 검증한다.
    const scaleOnly = VocalRoutine(
      id: 'short30',
      name: '테스트',
      steps: [
        RoutineStep(
          id: 'short30-scale',
          kind: RoutineStepKind.scale,
          minutes: 5,
          guide: '5음 스케일',
        ),
      ],
    );
    await controller.start(scaleOnly);
    await _pumpUntil(
      () => controller.phase == TrainingSessionPhase.finished,
    );

    expect(audio.pianoPlayed.first, 'run_53.wav');
    // 상행 53→65, 하행 64→53: 최고 루트가 65다.
    expect(audio.pianoPlayed, contains('run_65.wav'));
    expect(audio.pianoPlayed, isNot(contains('run_48.wav')));
    expect(audio.played, contains('scale_top'));
    expect(completed, ['short30-scale']);
  });

  test('stop은 idle로 돌아가고 이후 완료 체크가 없다', () async {
    audio.hold('breath_inhale');
    await controller.start(VocalRoutines.mini);
    await _pumpUntil(() => audio.played.contains('breath_inhale'));

    await controller.stop();
    expect(controller.phase, TrainingSessionPhase.idle);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isEmpty);
  });
}
