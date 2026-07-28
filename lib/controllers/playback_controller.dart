// file: lib/controllers/playback_controller.dart
//
// 재생 상태를 한곳에서 소유한다. 메인 패널과 전체화면 프롬프터가 같은
// 컨트롤러를 구독하므로 두 화면의 위치·하이라이트가 어긋나지 않는다.
import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../models/prompter_settings.dart';
import '../models/queue_item.dart';
import '../models/song.dart';
import '../models/timed_lyrics.dart';
import '../models/track_levels.dart';
import '../repository/song_repository.dart';
import '../services/lyrics_progress_service.dart';
import '../services/lyrics_sync_math.dart';
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
  ///
  /// v2.6.0: 게이트에서 speedLevel·autoScrollPaused를 뺐다. 둘은 "추정 줄
  /// 진행"과 "화면 따라가기" 설정일 뿐인데, 여기 묶여 있어 속도를 0으로
  /// 두거나 따라가기를 끄면 재생 위치·싱크 가사·진행바·EQ가 통째로 얼어붙었다.
  void _syncTicker() {
    final ticker = _ticker;
    if (ticker == null) return;

    final shouldRun = state.value.playing || state.value.isLyricsOnly;

    if (shouldRun && !ticker.isActive) {
      // 가사 전용 곡은 오디오 이벤트가 없으므로 시계를 직접 돌린다.
      if (state.value.isLyricsOnly && !_clock.isRunning) _clock.start();
      ticker.start();
    } else if (!shouldRun && ticker.isActive) {
      ticker.stop();
      if (state.value.isLyricsOnly) _clock.pause();
    }
  }

  void _onTick(Duration elapsed) {
    if (_disposed) return;
    position.value = _clock.value;
    _recomputeLineIndex(position.value);
  }

  /// 현재 재생 위치로 하이라이트 줄을 다시 구한다.
  ///
  /// 줄 소스 규칙은 하나뿐이다 — **싱크 가사가 있으면 그 타임스탬프, 없으면
  /// 추정**. 이전에는 `displayMode == timed`까지 만족해야 LRC를 썼는데,
  /// 전체화면에서는 그 모드에 도달할 수 없어 싱크가 무시됐다.
  void _recomputeLineIndex(Duration current) {
    final song = state.value.song;
    if (song == null) return;

    final synced = timedLyrics.value;
    if (synced != null && !synced.isEmpty) {
      final songTime = LyricsSyncMath.songTimeFor(
        playerPosition: current,
        trackStartMs: state.value.trackStartMs,
        lyricsOffsetMs: state.value.lyricsOffsetMs,
      );
      final next = synced.indexAt(songTime);
      if (next != lineIndex.value) lineIndex.value = next;
      return;
    }

    // 추정 진행은 속도가 0이면 계산 자체가 0을 돌려준다.
    // 그대로 쓰면 줄이 첫 줄로 튀므로, 이 경우엔 현재 줄을 유지한다.
    final speedLevel = settingsProvider().speedLevel;
    if (speedLevel <= 0) return;

    final lines = LyricsLineUtils.splitLines(song.lyricsText).length;
    final next = LyricsProgressService.estimatedLineIndex(
      position: current,
      duration: state.value.duration,
      lineCount: lines,
      speedLevel: speedLevel,
    );
    if (next != lineIndex.value) lineIndex.value = next;
  }

  /// 지금 곡의 줄 수. 싱크 가사가 있으면 그 줄 목록 기준이다.
  int get lineCount {
    final synced = timedLyrics.value;
    if (synced != null && !synced.isEmpty) return synced.lines.length;
    final song = state.value.song;
    if (song == null) return 0;
    return LyricsLineUtils.splitLines(song.lyricsText).length;
  }

  /// 특정 줄로 이동한다. 싱크 가사가 없으면 추정 시각으로, 그마저 불가능하면
  /// 줄 번호만 옮긴다(가사만 넘겨보는 용도).
  Future<void> seekToLine(int index) async {
    final total = lineCount;
    if (total <= 0) return;
    final clamped = index.clamp(0, total - 1);

    final synced = timedLyrics.value;
    if (synced != null && !synced.isEmpty) {
      await seek(
        LyricsSyncMath.playerPositionForLine(
          lyrics: synced,
          index: clamped,
          trackStartMs: state.value.trackStartMs,
          lyricsOffsetMs: state.value.lyricsOffsetMs,
        ),
      );
      return;
    }

    final estimated = LyricsProgressService.positionForLineIndex(
      index: clamped,
      duration: state.value.duration,
      lineCount: total,
      speedLevel: settingsProvider().speedLevel,
    );
    if (estimated != null) {
      await seek(estimated + Duration(milliseconds: state.value.trackStartMs ?? 0));
      return;
    }

    lineIndex.value = clamped;
    if (!_warnedNoSeekableLyrics) {
      _warnedNoSeekableLyrics = true;
      onMessage('싱크 가사가 없어 줄만 옮깁니다. 가사를 가져오면 반주도 함께 이동합니다.');
    }
  }

  bool _warnedNoSeekableLyrics = false;

  /// 이전/다음 줄로 옮긴다. (마우스 휠·단축키용)
  Future<void> stepLine(int delta) =>
      seekToLine(lineIndex.value + delta);

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
    // 가사가 늦게 도착하면 그 자리에서 줄을 다시 잡는다 —
    // 정지 상태라면 다음 틱이 영영 오지 않는다.
    _recomputeLineIndex(position.value);
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
    // 트림 시작이 있으면 첫 줄이 아닐 수 있다.
    _recomputeLineIndex(start);
    if (message != null) onMessage(message);
  }

  Future<void> seek(Duration target) async {
    final clamped = LyricsSyncMath.clampToTrim(
      target,
      startMs: state.value.trackStartMs,
      endMs: state.value.trackEndMs,
      duration: state.value.duration,
    );
    await audio.seek(clamped);
    _clock.anchor(clamped);
    position.value = clamped;
    // 이동 직후 바로 하이라이트를 맞춘다 — 다음 틱을 기다리면 정지 중에는
    // 영영 갱신되지 않는다.
    _recomputeLineIndex(clamped);
    _syncTicker();
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
