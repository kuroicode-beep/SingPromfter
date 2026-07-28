// file: lib/controllers/playback_controller.dart
//
// 재생 상태를 한곳에서 소유한다. 메인 패널과 전체화면 프롬프터가 같은
// 컨트롤러를 구독하므로 두 화면의 위치·하이라이트가 어긋나지 않는다.
import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../constants/app_constants.dart';
import '../models/prompter_display_mode.dart';
import '../models/prompter_settings.dart';
import '../models/queue_item.dart';
import '../models/song.dart';
import '../models/timed_lyrics.dart';
import '../models/track_levels.dart';
import '../repository/song_repository.dart';
import '../services/lyrics_progress_service.dart';
import '../services/prompter_audio_service.dart';
import '../services/song_queue_service.dart';
import '../utils/lyrics_line_utils.dart';
import 'position_clock.dart';

/// 자주 바뀌지 않는 재생 상태 묶음. 위치(60Hz)는 여기 포함하지 않는다.
@immutable
class PlaybackSnapshot {
  final Song? song;
  final int? trackSlot;
  final int? trackStartMs;
  final int? trackEndMs;
  final bool playing;
  final bool audioReady;
  final Duration duration;

  /// 현재 반주에 맞춘 가사 오프셋(ms). 음수면 가사를 먼저 띄운다.
  final int lyricsOffsetMs;

  const PlaybackSnapshot({
    this.song,
    this.trackSlot,
    this.trackStartMs,
    this.trackEndMs,
    this.playing = false,
    this.audioReady = false,
    this.duration = Duration.zero,
    this.lyricsOffsetMs = 0,
  });

  PlaybackSnapshot copyWith({
    Song? song,
    int? trackSlot,
    int? trackStartMs,
    int? trackEndMs,
    bool? playing,
    bool? audioReady,
    Duration? duration,
    int? lyricsOffsetMs,
    bool clearSong = false,
    bool clearTrack = false,
  }) {
    return PlaybackSnapshot(
      song: clearSong ? null : (song ?? this.song),
      trackSlot: clearTrack ? null : (trackSlot ?? this.trackSlot),
      trackStartMs: clearTrack ? null : (trackStartMs ?? this.trackStartMs),
      trackEndMs: clearTrack ? null : (trackEndMs ?? this.trackEndMs),
      playing: playing ?? this.playing,
      audioReady: audioReady ?? this.audioReady,
      duration: duration ?? this.duration,
      lyricsOffsetMs: clearTrack ? 0 : (lyricsOffsetMs ?? this.lyricsOffsetMs),
    );
  }

  /// 가사만 있고 반주가 없는 곡인지.
  bool get isLyricsOnly => song != null && song!.availableTrackSlots.isEmpty;
}

/// 재생 오케스트레이션 + 가사 진행.
class PlaybackController {
  final PrompterAudioService audio;
  final SongQueueService queueService;
  final SongRepository repo;
  final ScrollController lyricsScrollController;

  /// 곡 목록·큐·설정은 화면이 소유하므로 읽기 연결점을 주입받는다.
  final List<Song> Function() songsProvider;
  final List<QueueItem> Function() queueProvider;
  final PrompterSettings Function() settingsProvider;
  final void Function(List<QueueItem> queue) onQueueChanged;
  final void Function(String message) onMessage;

  /// 곡의 싱크 가사를 읽어온다. 없으면 null.
  final Future<TimedLyrics?> Function(Song song)? timedLyricsLoader;

  /// 키를 바꾼 반주 경로를 준비한다. 0이거나 실패하면 null(원본 사용).
  final Future<String?> Function(Song song, int slot, int semitones)?
  pitchVariantResolver;

  /// 반주의 EQ 밴드 레벨을 읽어온다(없으면 백그라운드 분석 후 늦게 도착).
  final Future<TrackLevels?> Function(Song song, int slot)? levelsLoader;

  /// 녹음 중이면 true. 녹음 중에는 자동으로 다음 곡으로 넘어가지 않는다.
  bool Function()? isRecordingProvider;

  /// 30초 이상 재생하면 연습 1회로 집계한다. (세션 적재 연결점)
  final void Function(PlaybackSnapshot snapshot, Duration played)?
  onPracticeSessionEnded;

  final ValueNotifier<PlaybackSnapshot> state = ValueNotifier(
    const PlaybackSnapshot(),
  );
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<int> lineIndex = ValueNotifier(0);

  /// 사용자가 가사 자동 진행을 잠시 멈춘 상태. (전체화면의 자동 스크롤 토글)
  final ValueNotifier<bool> autoScrollPaused = ValueNotifier(false);

  /// 현재 곡의 싱크 가사. 없으면 null이고 timed 모드는 추정으로 되돌아간다.
  final ValueNotifier<TimedLyrics?> timedLyrics = ValueNotifier(null);

  /// 현재 반주의 EQ 밴드 레벨. 분석 전이거나 없으면 null.
  final ValueNotifier<TrackLevels?> trackLevels = ValueNotifier(null);

  final PositionClock _clock = PositionClock();
  Ticker? _ticker;
  AudioBindings? _bindings;
  Timer? _noAudioSkipTimer;
  Timer? _resyncTimer;
  bool _processingQueue = false;
  bool _disposed = false;

  // 연습 세션 집계용
  Duration _practiceAccumulated = Duration.zero;
  Duration _practiceMarker = Duration.zero;
  Song? _practiceSong;

  PlaybackController({
    required this.audio,
    required this.queueService,
    required this.repo,
    required this.lyricsScrollController,
    required this.songsProvider,
    required this.queueProvider,
    required this.settingsProvider,
    required this.onQueueChanged,
    required this.onMessage,
    this.timedLyricsLoader,
    this.pitchVariantResolver,
    this.levelsLoader,
    this.onPracticeSessionEnded,
  });

  PlaybackSnapshot get snapshot => state.value;

  void init() {
    _ticker = Ticker(_onTick);
    _bindings = audio.bind(
      onPlayingChanged: _handlePlayingChanged,
      onPositionChanged: _handleNativePosition,
      onDurationChanged: (dur) => _update(state.value.copyWith(duration: dur)),
      onCompleted: onSongCompleted,
    );
    // 네이티브 이벤트가 멎어도 위치가 어긋나지 않도록 주기적으로 재동기화한다.
    _resyncTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (_disposed || !state.value.playing) return;
      final native = await audio.currentPosition();
      if (native != null) _clock.resync(native);
    });
  }

  void dispose() {
    _disposed = true;
    _ticker?.dispose();
    _resyncTimer?.cancel();
    _noAudioSkipTimer?.cancel();
    _bindings?.cancel();
    state.dispose();
    position.dispose();
    lineIndex.dispose();
    autoScrollPaused.dispose();
    timedLyrics.dispose();
    trackLevels.dispose();
  }

  /// 가사 오프셋 변경을 즉시 반영한다.
  void applyLyricsOffset(int offsetMs) {
    _update(state.value.copyWith(lyricsOffsetMs: offsetMs));
  }

  /// 가사 자동 진행을 멈추거나 다시 시작한다.
  void toggleAutoScrollPaused() {
    autoScrollPaused.value = !autoScrollPaused.value;
    _syncTicker();
  }

  // ── 상태 갱신 ─────────────────────────────────────────────

  void _update(PlaybackSnapshot next) {
    if (_disposed) return;
    state.value = next;
    _syncTicker();
  }

  void _handlePlayingChanged(bool playing) {
    if (_disposed) return;
    if (playing) {
      _clock.start();
      _practiceMarker = _clock.value;
    } else {
      _accumulatePractice();
      _clock.pause();
    }
    _update(state.value.copyWith(playing: playing));
  }

  void _handleNativePosition(Duration pos) {
    if (_disposed) return;
    _clock.resync(pos);

    final endMs = state.value.trackEndMs;
    if (state.value.playing &&
        endMs != null &&
        pos.inMilliseconds >= endMs) {
      onSongCompleted();
    }
  }

  /// 재생 중이거나 가사 전용 곡이면 틱을 돌린다. 그 외에는 멈춰 CPU를 아낀다.
  void _syncTicker() {
    final ticker = _ticker;
    if (ticker == null) return;

    final settings = settingsProvider();
    final shouldRun =
        (state.value.playing || state.value.isLyricsOnly) &&
        settings.speedLevel > 0 &&
        !autoScrollPaused.value;

    if (shouldRun && !ticker.isActive) {
      // 가사 전용 곡은 오디오 이벤트가 없으므로 시계를 직접 돌린다.
      if (state.value.isLyricsOnly && !_clock.isRunning) _clock.start();
      ticker.start();
    } else if (!shouldRun && ticker.isActive) {
      ticker.stop();
      if (state.value.isLyricsOnly) _clock.pause();
    }
  }

  Duration _lastScrollTick = Duration.zero;

  void _onTick(Duration elapsed) {
    if (_disposed) return;

    final current = _clock.value;
    position.value = current;

    final song = state.value.song;
    if (song == null) return;
    final settings = settingsProvider();

    // 줄 번호 — 싱크 가사가 있으면 실제 타임스탬프를, 없으면 추정을 쓴다.
    final synced = timedLyrics.value;
    final int nextIndex;
    if (settings.displayMode == PrompterDisplayMode.timed &&
        synced != null &&
        !synced.isEmpty) {
      // 트림 시작점을 빼고 곡별 오프셋을 더해 실제 노래 시각으로 환산한다.
      final startMs = state.value.trackStartMs ?? 0;
      final songTime = Duration(
        milliseconds:
            current.inMilliseconds - startMs + state.value.lyricsOffsetMs,
      );
      nextIndex = synced.indexAt(songTime);
    } else {
      final lines = LyricsLineUtils.splitLines(song.lyricsText).length;
      nextIndex = LyricsProgressService.estimatedLineIndex(
        position: current,
        duration: state.value.duration,
        lineCount: lines,
        speedLevel: settings.speedLevel,
      );
    }
    if (nextIndex != lineIndex.value) lineIndex.value = nextIndex;

    // 전체 모드 자동 스크롤 — 프레임 간격 기준이라 주사율에 좌우되지 않는다.
    if (settings.displayMode == PrompterDisplayMode.full) {
      final deltaSeconds =
          (elapsed - _lastScrollTick).inMicroseconds /
          Duration.microsecondsPerSecond;
      _scrollBy(settings.speedLevel, deltaSeconds);
    }
    _lastScrollTick = elapsed;
  }

  /// 전체화면이 열리면 그쪽 스크롤을 대신 움직인다.
  ScrollController? _overrideScroll;

  ScrollController get _activeScroll => _overrideScroll ?? lyricsScrollController;

  void attachScrollController(ScrollController controller) {
    _overrideScroll = controller;
  }

  void detachScrollController(ScrollController controller) {
    if (identical(_overrideScroll, controller)) _overrideScroll = null;
  }

  void _scrollBy(double speedLevel, double seconds) {
    if (seconds <= 0 || seconds > 0.5) return; // 첫 틱·정지 후 복귀 시 튐 방지
    final scroll = _activeScroll;
    if (!scroll.hasClients) return;
    final pixels =
        speedLevel * AppConstants.autoScrollPixelsPerSecond * seconds;
    if (pixels <= 0) return;
    final next = (scroll.offset + pixels).clamp(
      0.0,
      scroll.position.maxScrollExtent,
    );
    scroll.jumpTo(next);
  }

  // ── 연습 세션 집계 ────────────────────────────────────────

  void _accumulatePractice() {
    if (!_clock.isRunning) return;
    final delta = _clock.value - _practiceMarker;
    if (delta > Duration.zero) _practiceAccumulated += delta;
    _practiceMarker = _clock.value;
  }

  /// 진행 중이던 연습 세션을 종료하고 집계 대상으로 넘긴다.
  void _finishPracticeSession() {
    _accumulatePractice();
    final song = _practiceSong;
    final played = _practiceAccumulated;
    _practiceAccumulated = Duration.zero;
    _practiceMarker = Duration.zero;
    _practiceSong = null;
    if (song == null || played <= Duration.zero) return;
    onPracticeSessionEnded?.call(
      state.value.copyWith(song: song),
      played,
    );
  }

  // ── 재생 조작 ─────────────────────────────────────────────

  Future<void> loadSong(
    Song song, {
    int? preferredSlot,
    bool autoPlay = false,
  }) async {
    _noAudioSkipTimer?.cancel();

    // 곡이 바뀌면 이전 곡의 연습 세션을 마감한다.
    if (_practiceSong != null && _practiceSong!.id != song.id) {
      _finishPracticeSession();
    }
    _practiceSong = song;

    final settings = settingsProvider();
    final available = song.availableTrackSlots;
    int? resolvedSlot;

    if (preferredSlot != null && available.contains(preferredSlot)) {
      resolvedSlot = preferredSlot;
    } else {
      final savedForSong = settings.trackSlotForSong(song.id);
      if (savedForSong != null && available.contains(savedForSong)) {
        resolvedSlot = savedForSong;
      } else if (settings.lastSelectedTrackSlot != null &&
          available.contains(settings.lastSelectedTrackSlot)) {
        resolvedSlot = settings.lastSelectedTrackSlot;
      } else if (available.isNotEmpty) {
        resolvedSlot = available.first;
      }
    }

    final track = song.trackForSlot(resolvedSlot ?? -1);
    _clock.reset();
    position.value = Duration.zero;
    lineIndex.value = 0;
    _update(
      state.value.copyWith(
        song: song,
        trackSlot: resolvedSlot,
        trackStartMs: track?.startMs,
        trackEndMs: track?.endMs,
        lyricsOffsetMs: track?.lyricsOffsetMs ?? 0,
        clearTrack: resolvedSlot == null,
      ),
    );

    // 싱크 가사는 곡 단위라 슬롯 전환 때는 다시 읽지 않는다.
    timedLyrics.value = await timedLyricsLoader?.call(song);
    _reloadTrackLevels(song, resolvedSlot);

    await repo.saveLastSongId(song.id);
    await prepareAudioForSelection();

    if (autoPlay && available.isEmpty && queueProvider().isNotEmpty) {
      _noAudioSkipTimer = Timer(
        const Duration(seconds: 5),
        () => onSongCompleted(),
      );
    }

    if (autoPlay && state.value.audioReady) {
      await audio.resumeFromStart(startMs: state.value.trackStartMs);
    }
    _syncTicker();
  }

  Future<void> prepareAudioForSelection() async {
    final settings = settingsProvider();

    // 키가 지정돼 있으면 미리 렌더한 변형본을 재생한다.
    String? overridePath;
    final song = state.value.song;
    final slot = state.value.trackSlot;
    final semitones = song == null ? 0 : settings.pitchForSong(song.id, slot);
    if (song != null && slot != null && semitones != 0) {
      overridePath = await pitchVariantResolver?.call(song, slot, semitones);
    }

    final result = await audio.prepareSelection(
      overridePath: overridePath,
      song: state.value.song,
      selectedTrackSlot: state.value.trackSlot,
      volume: settings.volume,
      playbackRate: settings.playbackRate,
      startMs: state.value.trackStartMs,
    );
    if (_disposed) return;

    // 이벤트 스트림에 맡기지 않고 준비 완료 시점에 위치를 확정한다.
    final start = Duration(milliseconds: state.value.trackStartMs ?? 0);
    _clock.anchor(start);
    position.value = start;

    _update(
      state.value.copyWith(audioReady: result.ready, duration: Duration.zero),
    );
    if (result.message != null) onMessage(result.message!);
  }

  Future<void> selectTrackSlot(int slot) async {
    final song = state.value.song;
    if (song == null) return;
    if (!song.availableTrackSlots.contains(slot)) return;
    final track = song.trackForSlot(slot);
    _update(
      state.value.copyWith(
        trackSlot: slot,
        trackStartMs: track?.startMs,
        trackEndMs: track?.endMs,
        lyricsOffsetMs: track?.lyricsOffsetMs ?? 0,
      ),
    );
    _reloadTrackLevels(song, slot);
    await prepareAudioForSelection();
  }

  /// 레벨을 비웠다가 로더 완료 시 채운다.
  /// 로드 중에 곡·슬롯이 바뀌었으면 결과를 버린다(경합 가드).
  void _reloadTrackLevels(Song song, int? slot) {
    trackLevels.value = null;
    if (slot == null || levelsLoader == null) return;
    unawaited(
      levelsLoader!(song, slot).then((levels) {
        if (_disposed) return;
        if (state.value.song?.id != song.id) return;
        if (state.value.trackSlot != slot) return;
        trackLevels.value = levels;
      }),
    );
  }

  Future<void> togglePlayPause() async {
    final message = await audio.togglePlayPause(
      song: state.value.song,
      audioReady: state.value.audioReady,
      playing: state.value.playing,
    );
    if (message != null) onMessage(message);
  }

  /// 명시적 재생(멱등). 이미 재생 중이면 무동작 — MCP 제어용.
  Future<void> play() async {
    final message = await audio.play(
      song: state.value.song,
      audioReady: state.value.audioReady,
      playing: state.value.playing,
    );
    if (message != null) onMessage(message);
  }

  /// 명시적 일시정지(멱등). 정지 상태면 무동작.
  Future<void> pause() async {
    final message = await audio.pause(
      song: state.value.song,
      audioReady: state.value.audioReady,
      playing: state.value.playing,
    );
    if (message != null) onMessage(message);
  }

  Future<void> stop() async {
    await audio.stop();
    _accumulatePractice();
    _clock.reset();
    position.value = Duration.zero;
    lineIndex.value = 0;
    _finishPracticeSession();
    _syncTicker();
  }

  Future<void> restart() async {
    final message = await audio.restart(
      audioReady: state.value.audioReady,
      startMs: state.value.trackStartMs,
    );
    final start = Duration(milliseconds: state.value.trackStartMs ?? 0);
    _clock.anchor(start);
    position.value = start;
    lineIndex.value = 0;
    if (message != null) onMessage(message);
  }

  Future<void> seek(Duration target) async {
    await audio.seek(target);
    _clock.anchor(target);
    position.value = target;
  }

  /// 볼륨·배속 등 설정 변경을 재생에 반영한다.
  Future<void> applySettings(PrompterSettings next) async {
    await audio.setVolume(next.volume);
    await audio.setPlaybackRate(next.playbackRate);
    _clock.setRate(next.playbackRate);
    _syncTicker();
  }

  Future<void> onSongCompleted() async {
    if (_processingQueue || _disposed) return;
    // 아웃트로를 부르는 중에 다음 곡으로 넘어가지 않도록 막는다.
    if (isRecordingProvider?.call() ?? false) return;
    _processingQueue = true;
    try {
      _finishPracticeSession();
      await _playNextFromQueue();
    } finally {
      _processingQueue = false;
    }
  }

  Future<void> _playNextFromQueue() async {
    final next = await queueService.popNextPlayable(
      queue: queueProvider(),
      songs: songsProvider(),
    );
    if (_disposed) return;
    onQueueChanged(next?.queue ?? const []);
    if (next == null) return;

    await loadSong(
      next.song,
      preferredSlot: next.selectedTrackSlot,
      autoPlay: true,
    );
  }

  /// 곡이 삭제되는 등 선택이 사라질 때 호출한다.
  void clearSelection() {
    _finishPracticeSession();
    _clock.reset();
    position.value = Duration.zero;
    lineIndex.value = 0;
    _update(
      state.value.copyWith(clearSong: true, clearTrack: true, duration: Duration.zero),
    );
  }
}
