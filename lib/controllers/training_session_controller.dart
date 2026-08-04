// file: lib/controllers/training_session_controller.dart
//
// 트레이닝 따라하기 세션의 상태기계. 음성 안내(사전 생성 TTS)와 피아노 런을
// 순서대로 틀며 스텝을 자동 진행하고, 끝난 스텝은 DailyGoalService로 체크한다.
//
// 진행 흐름: 시작 안내 → (코스면 주차 브리핑) → 스텝 반복[안내 → 실행] → 마침.
// 실행은 스텝 종류별로 다르다:
//  - 호흡: 들이쉬고/내쉬세요 큐를 박자에 맞춰 반복 (reps가 완료 기준)
//  - 스케일(5음): 음역의 루트를 반음씩 올렸다 내리며 피아노 런 + 따라 부를 간격
//  - 스케일(사이렌)·워밍업·딕션·쿨다운·곡 스텝: 안내 후 분 카운트다운
//
// 동시성 규약: 세션 루프는 하나(_runToken 세대 토큰으로 취소). 일시정지·건너뛰기·
// 재시작은 플래그로 요청하고 루프가 소비한다 — 루프를 여러 개 띄우지 않는다.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../constants/voice_clips.dart';
import '../models/routine_step_spec.dart';
import '../models/vocal_routine.dart';
import '../services/guide_audio_service.dart';

enum TrainingSessionPhase { idle, briefing, announcing, running, finished }

/// 스텝 실행 결과 — 루프 제어에 쓴다.
enum _StepOutcome { done, skipped, restart, cancelled }

class TrainingSessionController extends ChangeNotifier {
  final GuideAudio audio;
  final TrainingVoiceRange Function() voiceRange;
  final Future<void> Function(String stepId) onStepCompleted;

  /// 테스트용 대기 주입 — 기본은 실제 시간.
  final Future<void> Function(Duration) delayFn;

  TrainingSessionController({
    required this.audio,
    required this.voiceRange,
    required this.onStepCompleted,
    Future<void> Function(Duration)? delayFn,
  }) : delayFn = delayFn ?? _realDelay;

  static Future<void> _realDelay(Duration d) => Future<void>.delayed(d);

  // ── 화면이 구독하는 상태 ──
  TrainingSessionPhase phase = TrainingSessionPhase.idle;
  VocalRoutine? routine;
  int stepIndex = 0;
  bool paused = false;

  /// 러너 카드의 대형 안내 텍스트(예: "들이쉬고 4", "따라 부르세요").
  String bigText = '';

  /// 카운트다운 스텝의 남은 시간(초 단위 갱신). 없으면 null.
  Duration? remaining;

  bool get active =>
      phase != TrainingSessionPhase.idle &&
      phase != TrainingSessionPhase.finished;

  RoutineStep? get currentStep {
    final r = routine;
    if (r == null || stepIndex < 0 || stepIndex >= r.steps.length) return null;
    return r.steps[stepIndex];
  }

  // ── 내부 제어 ──
  int _runToken = 0;
  bool _skipRequested = false;
  bool _restartRequested = false;

  /// 세션 시작. 코스 진행 중이면 주차 번호를 넘겨 브리핑을 선행한다.
  Future<void> start(VocalRoutine r, {int? courseWeekNumber}) async {
    await stop(silent: true);
    routine = r;
    stepIndex = 0;
    paused = false;
    _skipRequested = false;
    _restartRequested = false;
    phase = TrainingSessionPhase.briefing;
    bigText = '트레이닝 시작';
    remaining = null;
    notifyListeners();

    final token = ++_runToken;
    unawaited(_run(token, courseWeekNumber));
  }

  /// 일시정지 — 진행 중 음성·피아노도 멈춘다.
  Future<void> pause() async {
    if (!active || paused) return;
    paused = true;
    notifyListeners();
    await audio.stopAll();
    unawaited(_playSafe('session_paused'));
  }

  /// 재개.
  Future<void> resume() async {
    if (!active || !paused) return;
    await _playSafe('session_resume');
    paused = false;
    notifyListeners();
  }

  /// Space 단축키용 토글.
  Future<void> togglePause() => paused ? resume() : pause();

  /// 현재 스텝을 체크 없이 건너뛴다.
  Future<void> skipStep() async {
    if (!active) return;
    _skipRequested = true;
    paused = false;
    await audio.stopAll();
    notifyListeners();
  }

  /// 현재 스텝(섹션)을 처음부터 다시 — Home 단축키.
  Future<void> restartStep() async {
    if (!active) return;
    _restartRequested = true;
    paused = false;
    await audio.stopAll();
    notifyListeners();
  }

  /// 세션 종료(idle 복귀).
  Future<void> stop({bool silent = false}) async {
    final wasActive = active;
    _runToken++;
    phase = TrainingSessionPhase.idle;
    paused = false;
    bigText = '';
    remaining = null;
    notifyListeners();
    await audio.stopAll();
    if (wasActive && !silent) unawaited(_playSafe('session_stopped'));
  }

  @override
  void dispose() {
    _runToken++;
    super.dispose();
  }

  // ── 세션 루프 ──

  Future<void> _run(int token, int? courseWeekNumber) async {
    await _playSafe('session_start');
    if (token != _runToken) return;
    if (courseWeekNumber != null) {
      await _playSafe(VoiceClips.courseWeekClipId(courseWeekNumber));
      if (token != _runToken) return;
    }

    final r = routine;
    if (r == null) return;

    while (token == _runToken && stepIndex < r.steps.length) {
      final step = r.steps[stepIndex];
      final outcome = await _runStep(token, step);
      if (token != _runToken || outcome == _StepOutcome.cancelled) return;
      switch (outcome) {
        case _StepOutcome.restart:
          _restartRequested = false;
          await _playSafe('session_restart_step');
          continue; // 같은 인덱스 다시
        case _StepOutcome.skipped:
          _skipRequested = false;
          await _playSafe('session_skipped');
          stepIndex += 1;
        case _StepOutcome.done:
          await onStepCompleted(step.id);
          await _playSafe('session_step_done');
          stepIndex += 1;
          if (stepIndex < r.steps.length) {
            await _playSafe('session_next');
          }
        case _StepOutcome.cancelled:
          return;
      }
      notifyListeners();
    }

    if (token != _runToken) return;
    phase = TrainingSessionPhase.finished;
    bigText = '오늘의 루틴 완료!';
    remaining = null;
    notifyListeners();
    await _playSafe('session_all_done');
  }

  Future<_StepOutcome> _runStep(int token, RoutineStep step) async {
    phase = TrainingSessionPhase.announcing;
    bigText = step.title;
    remaining = null;
    notifyListeners();

    final spec = RoutineStepSpecs.byStepId(step.id);
    await _playSafe(spec?.announceClipId ?? '');
    var interrupt = _checkInterrupt(token);
    if (interrupt != null) return interrupt;

    phase = TrainingSessionPhase.running;
    notifyListeners();

    if (spec != null && spec.breathing.isNotEmpty) {
      return _runBreathing(token, spec.breathing);
    }
    if (spec?.scale == ScaleKind.fiveTone) {
      return _runFiveToneScale(token);
    }
    // 사이렌·워밍업·딕션·쿨다운·곡 스텝: 분 카운트다운.
    if (spec?.scale == ScaleKind.siren) {
      await _playSafe('scale_intro_siren');
      interrupt = _checkInterrupt(token);
      if (interrupt != null) return interrupt;
    }
    return _runCountdown(token, Duration(minutes: step.minutes));
  }

  /// 호흡 — 블록×반복만큼 들숨/멈춤/날숨 큐를 박자에 맞춰 낸다.
  Future<_StepOutcome> _runBreathing(
    int token,
    List<BreathingPattern> blocks,
  ) async {
    for (final block in blocks) {
      for (var rep = 0; rep < block.reps; rep++) {
        // 반복 전 큐 — 첫 회는 바로, 이후 "한 번 더"/"마지막 한 번".
        if (rep > 0) {
          await _playSafe(
            rep == block.reps - 1 ? 'breath_last' : 'breath_again',
          );
        }
        var interrupt = _checkInterrupt(token);
        if (interrupt != null) return interrupt;

        await _playSafe('breath_inhale');
        var ok = await _guidedWait(
          token,
          block.beat * block.inhaleBeats,
          label: '들이쉬고',
          countBeats: block.inhaleBeats,
          beat: block.beat,
        );
        if (!ok) return _checkInterrupt(token) ?? _StepOutcome.cancelled;

        if (block.holdBeats > 0) {
          await _playSafe('breath_hold');
          ok = await _guidedWait(
            token,
            block.beat * block.holdBeats,
            label: '멈추고',
            countBeats: block.holdBeats,
            beat: block.beat,
          );
          if (!ok) return _checkInterrupt(token) ?? _StepOutcome.cancelled;
        }

        await _playSafe('breath_exhale');
        ok = await _guidedWait(
          token,
          block.beat * block.exhaleBeats,
          label: '내쉬세요',
          countBeats: block.exhaleBeats,
          beat: block.beat,
        );
        if (!ok) return _checkInterrupt(token) ?? _StepOutcome.cancelled;
      }
    }
    await _playSafe('breath_done');
    return _checkInterrupt(token) ?? _StepOutcome.done;
  }

  /// 5음 스케일 — 음역 루트를 반음씩 올렸다 내리며 피아노 런 + 따라 부르기 간격.
  Future<_StepOutcome> _runFiveToneScale(int token) async {
    await _playSafe('scale_intro_five');
    var interrupt = _checkInterrupt(token);
    if (interrupt != null) return interrupt;

    final range = voiceRange();
    final ascending = [
      for (var m = range.rootLow; m <= range.rootHigh; m++) m,
    ];
    final descending = [
      for (var m = range.rootHigh - 1; m >= range.rootLow; m--) m,
    ];

    Future<_StepOutcome?> playRoot(int midi) async {
      bigText = '피아노를 듣고';
      notifyListeners();
      try {
        await audio.playPianoRun('run_$midi.wav');
      } catch (_) {
        // 피아노 에셋 문제 — 세션은 계속(음성 안내만으로).
      }
      var i = _checkInterrupt(token);
      if (i != null) return i;
      // 사용자가 같은 런을 따라 부를 간격(런 길이와 동일하게 잡는다).
      final ok = await _guidedWait(
        token,
        const Duration(milliseconds: 5300),
        label: '따라 부르세요',
      );
      if (!ok) return _checkInterrupt(token) ?? _StepOutcome.cancelled;
      return null;
    }

    for (final midi in ascending) {
      final out = await playRoot(midi);
      if (out != null) return out;
    }
    await _playSafe('scale_top');
    for (final midi in descending) {
      final out = await playRoot(midi);
      if (out != null) return out;
    }
    await _playSafe('scale_done');
    return _checkInterrupt(token) ?? _StepOutcome.done;
  }

  /// 분 단위 카운트다운 — 절반·30초 남음 큐 포함.
  Future<_StepOutcome> _runCountdown(int token, Duration total) async {
    var halfCued = false;
    var lastCued = false;
    var left = total;
    remaining = left;
    bigText = currentStep?.kind.label ?? '';
    notifyListeners();

    while (left > Duration.zero) {
      final ok = await _guidedWait(
        token,
        const Duration(seconds: 1),
        label: bigText,
        silentLabel: true,
      );
      if (!ok) return _checkInterrupt(token) ?? _StepOutcome.cancelled;
      left -= const Duration(seconds: 1);
      remaining = left;
      notifyListeners();

      if (!halfCued && total.inSeconds >= 120 && left <= total ~/ 2) {
        halfCued = true;
        unawaited(_playSafe('session_half'));
      }
      if (!lastCued && total.inSeconds >= 90 && left.inSeconds == 30) {
        lastCued = true;
        unawaited(_playSafe('session_30s'));
      }
    }
    remaining = null;
    return _checkInterrupt(token) ?? _StepOutcome.done;
  }

  // ── 대기·인터럽트 공통 ──

  /// 지정 시간 대기하며 큰 글씨(박자 카운트 포함)를 갱신한다.
  /// 일시정지면 시간을 멈추고, 취소/건너뛰기/재시작 요청이 오면 false.
  Future<bool> _guidedWait(
    int token,
    Duration total, {
    required String label,
    bool silentLabel = false,
    int? countBeats,
    Duration? beat,
  }) async {
    var elapsed = Duration.zero;
    const tick = Duration(milliseconds: 100);
    while (elapsed < total) {
      if (token != _runToken ||
          _skipRequested ||
          _restartRequested) {
        return false;
      }
      if (paused) {
        await delayFn(tick);
        continue; // 일시정지 중엔 시간이 흐르지 않는다.
      }
      if (!silentLabel) {
        if (countBeats != null && beat != null) {
          // "들이쉬고 4·3·2·1" — 남은 박 수 표시.
          final beatsLeft =
              countBeats - (elapsed.inMilliseconds ~/ beat.inMilliseconds);
          final next = '$label $beatsLeft';
          if (next != bigText) {
            bigText = next;
            notifyListeners();
          }
        } else if (bigText != label) {
          bigText = label;
          notifyListeners();
        }
      }
      await delayFn(tick);
      elapsed += tick;
    }
    return token == _runToken && !_skipRequested && !_restartRequested;
  }

  /// 취소/건너뛰기/재시작 요청을 결과로 바꾼다. 없으면 null.
  _StepOutcome? _checkInterrupt(int token) {
    if (token != _runToken) return _StepOutcome.cancelled;
    if (_restartRequested) return _StepOutcome.restart;
    if (_skipRequested) return _StepOutcome.skipped;
    return null;
  }

  /// 클립 재생 — 에셋 누락 등 실패는 세션을 멈추지 않는다.
  Future<void> _playSafe(String clipId) async {
    if (clipId.isEmpty) return;
    try {
      await audio.playVoice(clipId);
    } catch (_) {
      // 재생 실패는 치명적이지 않다 — 텍스트 안내가 계속 보인다.
    }
  }
}
