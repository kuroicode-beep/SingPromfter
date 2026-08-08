// file: lib/services/guide_audio_service.dart
//
// 트레이닝·도움말의 음성 안내(TTS 클립)와 피아노 런 재생 전담.
// 프롬프터 곡 재생(PrompterAudioService)과 절대 섞이지 않도록
// 자체 AudioPlayer 2개(음성/피아노)를 소유한다 — _takePlayer 선례와 같은 방식.
//
// 클립은 앱에 내장된 에셋(assets/audio/...)만 재생한다. 파일이 없으면
// 예외가 나므로 호출부는 catch 해서 SnackMessage로 알린다.
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../constants/voice_clips.dart';

/// 재생 인터페이스 — 테스트가 플러그인 채널 없이 가짜를 주입할 수 있게 분리.
abstract interface class GuideAudio {
  Future<void> playVoice(String clipId);
  Future<void> playVoiceSequence(
    Iterable<String> clipIds, {
    bool Function()? cancelled,
  });
  Future<void> playPianoRun(String fileName);
  Future<void> stopVoice();
  Future<void> stopPiano();
  Future<void> stopAll();
  Future<void> dispose();
}

class GuideAudioService implements GuideAudio {
  final AudioPlayer _voice = AudioPlayer();
  final AudioPlayer _piano = AudioPlayer();

  Completer<void>? _voiceDone;
  Completer<void>? _pianoDone;
  StreamSubscription<void>? _voiceSub;
  StreamSubscription<void>? _pianoSub;
  bool _disposed = false;

  GuideAudioService() {
    // 완료 스트림은 한 번만 구독하고, 진행 중인 재생의 completer를 풀어 준다.
    _voiceSub = _voice.onPlayerComplete.listen((_) {
      final done = _voiceDone;
      if (done != null && !done.isCompleted) done.complete();
    });
    _pianoSub = _piano.onPlayerComplete.listen((_) {
      final done = _pianoDone;
      if (done != null && !done.isCompleted) done.complete();
    });
  }

  @override
  /// 음성 클립 하나를 재생하고 끝날 때까지 기다린다.
  /// stopAll/stopVoice가 끼어들면 그 시점에 조용히 반환한다.
  Future<void> playVoice(String clipId) async {
    if (_disposed) return;
    await stopVoice();
    final done = Completer<void>();
    _voiceDone = done;
    await _voice.play(AssetSource(VoiceClips.assetPath(clipId)));
    await done.future;
    if (identical(_voiceDone, done)) _voiceDone = null;
  }

  @override
  /// 여러 클립을 순서대로 재생한다. cancelled()가 true가 되면 즉시 멈춘다.
  Future<void> playVoiceSequence(
    Iterable<String> clipIds, {
    bool Function()? cancelled,
  }) async {
    for (final id in clipIds) {
      if (_disposed || (cancelled?.call() ?? false)) return;
      await playVoice(id);
    }
  }

  @override
  /// 피아노 런 파일(`assets/audio/piano/<name>.wav`)을 재생하고 끝까지 기다린다.
  Future<void> playPianoRun(String fileName) async {
    if (_disposed) return;
    await stopPiano();
    final done = Completer<void>();
    _pianoDone = done;
    await _piano.play(AssetSource('audio/piano/$fileName'));
    await done.future;
    if (identical(_pianoDone, done)) _pianoDone = null;
  }

  @override
  /// 음성만 정지. 대기 중이던 playVoice는 즉시 풀린다.
  Future<void> stopVoice() async {
    final done = _voiceDone;
    _voiceDone = null;
    if (done != null && !done.isCompleted) done.complete();
    try {
      await _voice.stop();
    } catch (_) {
      // 이미 정지 상태 등 — 정지 실패는 치명적이지 않다.
    }
  }

  @override
  /// 피아노만 정지.
  Future<void> stopPiano() async {
    final done = _pianoDone;
    _pianoDone = null;
    if (done != null && !done.isCompleted) done.complete();
    try {
      await _piano.stop();
    } catch (_) {}
  }

  @override
  /// 전부 정지 — 탭 이탈·세션 종료·dispose 직전에 호출.
  Future<void> stopAll() async {
    await stopVoice();
    await stopPiano();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stopAll();
    await _voiceSub?.cancel();
    await _pianoSub?.cancel();
    await _voice.dispose();
    await _piano.dispose();
  }
}
