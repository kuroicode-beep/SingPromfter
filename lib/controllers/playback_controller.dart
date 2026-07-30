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
import '../models/vocal_segments.dart';
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

  /// 지금 재생 중인 파일에 구워진 템포(배). 1.0이면 원속도다.
  ///
  /// 트림 지점은 이미 이 축으로 환산돼 있고, 가사 시각은 원본 축이라
  /// 비교하려면 이 값이 필요하다(lyrics_sync_math의 축 규약 참고).
  final double tempoScale;

  const PlaybackSnapshot({
    this.song,
    this.trackSlot,
    this.trackStartMs,
    this.trackEndMs,
    this.playing = false,
    this.audioReady = false,
    this.duration = Duration.zero,
    this.lyricsOffsetMs = 0,
    this.tempoScale = 1,
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
    double? tempoScale,
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
      tempoScale: clearTrack ? 1 : (tempoScale ?? this.tempoScale),
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

  /// 키·템포를 바꿔 구운 반주 경로를 준비한다. 기본값이거나 실패하면 null.
  final Future<String?> Function(
    Song song,
    int slot,
    int semitones,
    double tempoScale,
  )?
  trackVariantResolver;

  /// 반주의 EQ 밴드 레벨을 읽어온다(없으면 백그라운드 분석 후 늦게 도착).
  final Future<TrackLevels?> Function(Song song, int slot)? levelsLoader;

  /// 노래(보컬) 구간을 읽어온다 — 싱크 가사가 없는 곡의 줄 배분에 쓴다.
  /// 원곡·MR이 없는 곡이면 null이 오고, 그러면 균등 배분으로 폴백한다.
  final Future<VocalSegments?> Function(Song song)? vocalSegmentsLoader;

  /// 반주 길이가 확정될 때마다 불린다(곡을 물릴 때·슬롯을 바꿀 때).
  /// 길이를 알아야 표본 구간을 잡을 수 있는 조성 추정이 여기에 붙는다.
  /// 여러 번 불릴 수 있으니 받는 쪽이 멱등해야 한다.
  final void Function(Song song, Duration duration)? onSongReady;

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
    this.trackVariantResolver,
    this.levelsLoader,
    this.vocalSegmentsLoader,
    this.onSongReady,
    this.onPracticeSessionEnded,
  });

  PlaybackSnapshot get snapshot => state.value;

  void init() {
    _ticker = Ticker(_onTick);
    _bindings = audio.bind(
      onPlayingChanged: _handlePlayingChanged,
      onPositionChanged: _handleNativePosition,
      onDurationChanged: (dur) {
        _update(state.value.copyWith(duration: dur));
        // 길이는 네이티브에서 늦게 온다. 조성 추정처럼 길이가 있어야 하는
        // 작업은 loadSong 끝이 아니라 여기서 시작해야 한다.
        final song = state.value.song;
        if (song != null && dur > Duration.zero) onSongReady?.call(song, dur);
      },
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
  ///
  /// 줄 인덱스도 여기서 바로 다시 계산한다 — 위치 틱에만 맡기면
  /// **일시정지 중에는 다음 틱이 없어서** T(리셋)·`.`/`/`(밀고 당기기)를
  /// 눌러도 화면이 꿈쩍하지 않는다(실사용에서 "안 먹음"으로 보고된 원인).
  void applyLyricsOffset(int offsetMs) {
    _update(state.value.copyWith(lyricsOffsetMs: offsetMs));
    _recomputeLineIndex(position.value);
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
        tempoScale: state.value.tempoScale,
      );
      final next = synced.indexAt(songTime);
      if (next != lineIndex.value) lineIndex.value = next;
      return;
    }

    final lines = LyricsLineUtils.splitLines(song.lyricsText).length;
    final segments = _vocalSegments;
    final int next;
    if (segments != null && !segments.isEmpty) {
      // 노래 구간에만 줄을 배분한다 — 전주 동안 첫 줄에서 대기하고
      // 간주에서는 멈춘다. 구간은 원본 파일 축이라 템포 렌더에서는
      // 위치를 원본 축으로 되돌려 비교한다.
      next = LyricsProgressService.segmentLineProgress(
        position: LyricsSyncMath.toSource(current, state.value.tempoScale),
        segments: segments,
        lineCount: lines,
        offsetMs: state.value.lyricsOffsetMs,
      ).index;
    } else {
      next = LyricsProgressService.estimatedLineIndex(
        position: current,
        duration: state.value.duration,
        lineCount: lines,
      );
    }
    if (next != lineIndex.value) lineIndex.value = next;
  }

  /// 가사 줄이 끝나는 기준이 되는 곡 끝. 트림 끝을 우선하고 없으면 곡 길이.
  /// 마지막 줄의 끝을 정하는 데만 쓴다.
  Duration? get lyricsTrackEnd {
    final tempo = state.value.tempoScale;
    final endMs = state.value.trackEndMs;
    if (endMs != null && endMs > 0) {
      // 트림 끝은 렌더 축이므로 가사와 같은 원본 축으로 되돌린다.
      return LyricsSyncMath.toSource(Duration(milliseconds: endMs), tempo);
    }
    final duration = state.value.duration;
    if (duration <= Duration.zero) return null;
    return LyricsSyncMath.toSource(duration, tempo);
  }

  /// 현재 줄 안에서의 진행률(0..1). 스윕할 수 없는 상황이면 null.
  ///
  /// ValueNotifier로 노출하지 않는 것은 의도다 — 60Hz 값이 notifier가 되는
  /// 순간 누군가 AnimatedBuilder에 물릴 위험이 생긴다. "위치는 구독 위젯이
  /// 직접 받는다"는 v2.6.0 규약을 여기서도 지킨다. 스윕 위젯이 자기 Ticker에서
  /// 이 메서드를 직접 부른다.
  double? currentLineFraction() {
    final song = state.value.song;
    if (song == null) return null;

    final synced = timedLyrics.value;
    if (synced != null && !synced.isEmpty) {
      final index = lineIndex.value;
      if (index < 0 || index >= synced.lines.length) return null;
      final start = synced.lines[index].time;
      final end = index + 1 < synced.lines.length
          ? synced.lines[index + 1].time
          : lyricsTrackEnd;
      if (end == null) return null;

      final lyricsTime = LyricsSyncMath.lyricsTimeFor(
        playerPosition: position.value,
        lyrics: synced,
        trackStartMs: state.value.trackStartMs,
        lyricsOffsetMs: state.value.lyricsOffsetMs,
        tempoScale: state.value.tempoScale,
      );
      return LyricsSyncMath.lineProgress(
        lyricsTime: lyricsTime,
        start: start,
        end: end,
        maxSweep: LyricsSyncMath.sweepWindow(
          synced.lines[index].text,
          end - start,
        ),
      );
    }

    // 싱크 가사가 없으면 스윕하지 않는다.
    //
    // 추정 진행률은 있지만(LyricsProgressService.estimatedLineProgress),
    // 그건 "곡 길이에 줄을 고르게 뿌린" 값이라 실제 노래와 맞을 이유가 없다.
    // 그 값으로 개별 글자를 켜면 **자신 있게 틀린 음절**을 가리키게 된다 —
    // 아무 표시도 없느니만 못하다. 줄 단위 강조(화살표·밑줄·배경·색)는
    // 그대로 남으므로 어느 줄인지는 여전히 알 수 있다.
    return null;
  }

  /// 원본 축 트림 지점을 렌더 축으로 옮긴다. 값이 없으면 그대로 null.
  static int? _toRenderedMs(int? sourceMs, double tempoScale) {
    if (sourceMs == null) return null;
    return LyricsSyncMath.toRendered(
      Duration(milliseconds: sourceMs),
      tempoScale,
    ).inMilliseconds;
  }

  /// 지금 곡의 줄 수. 싱크 가사가 있으면 그 줄 목록 기준이다.
  int get lineCount {
    final synced = timedLyrics.value;
    if (synced != null && !synced.isEmpty) return synced.lines.length;
    final song = state.value.song;
    if (song == null) return 0;
    return LyricsLineUtils.splitLines(song.lyricsText).length;
  }

  /// "지금이 첫 줄이다" — 현재 재생 위치를 첫 줄 시작으로 삼는 오프셋(원본 축).
  ///
  /// 노래를 들으며 첫 소절이 나오는 순간에 눌러 주면 싱크 전체가 그 지점에
  /// 맞춰진다. 구간 탐지가 전주 끝을 잘못 잡았거나 LRC 판본이 다른 녹음에서
  /// 만들어졌을 때, 사람이 직접 바로잡는 입구다.
  ///
  /// 근거가 없으면(싱크 가사도, 노래 구간도 없음) null — 그때는 앵커를
  /// 걸 기준선이 아예 없다.
  int? anchorOffsetForCurrentPosition() {
    final tempo = state.value.tempoScale;
    final synced = timedLyrics.value;
    if (synced != null && !synced.isEmpty) {
      // LRC 경로는 트림 시작을 뺀 뒤 원본 축으로 환산한다(songTimeFor와 같은 순서).
      final rendered = Duration(
        milliseconds:
            position.value.inMilliseconds - (state.value.trackStartMs ?? 0),
      );
      return LyricsProgressService.anchorOffsetForLyrics(
        position: LyricsSyncMath.toSource(rendered, tempo),
        firstLineMs:
            synced.lines.first.time.inMilliseconds + synced.offsetMs,
      );
    }

    final segments = _vocalSegments;
    if (segments != null && !segments.isEmpty) {
      // 구간은 파일 절대 시각이라 trackStart를 빼지 않는다(seekToLine과 같은 규약).
      return LyricsProgressService.anchorOffsetForSegments(
        position: LyricsSyncMath.toSource(position.value, tempo),
        segments: segments,
      );
    }
    return null;
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
          tempoScale: state.value.tempoScale,
        ),
      );
      return;
    }

    final segments = _vocalSegments;
    if (segments != null && !segments.isEmpty) {
      final source = LyricsProgressService.positionForLineIndexWithSegments(
        index: clamped,
        segments: segments,
        lineCount: total,
        offsetMs: state.value.lyricsOffsetMs,
      );
      if (source != null) {
        // 구간은 원본 파일 축(파일 절대 시각)이라 trackStart를 더하지 않는다.
        await seek(LyricsSyncMath.toRendered(source, state.value.tempoScale));
        return;
      }
    }

    final estimated = LyricsProgressService.positionForLineIndex(
      index: clamped,
      duration: state.value.duration,
      lineCount: total,
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

  /// 곡 처음(트림 시작)으로. Home 단축키.
  Future<void> jumpToStart() =>
      seek(Duration(milliseconds: state.value.trackStartMs ?? 0));

  /// 현재 위치에서 [delta]만큼 건너뛴다. ←/→ 단축키.
  /// seek이 트림·길이로 클램프하므로 곡 밖으로 나가지 않는다.
  Future<void> seekRelative(Duration delta) => seek(position.value + delta);

  /// 곡 끝(트림 끝)으로. End 단축키.
  /// seek이 트림·길이로 클램프하므로 큰 값을 넘겨도 안전하다.
  Future<void> jumpToEnd() async {
    final end =
        state.value.trackEndMs ?? state.value.duration.inMilliseconds;
    if (end <= 0) return;
    await seek(Duration(milliseconds: end));
  }

  /// 이전/다음 줄로 옮긴다. (마우스 휠·단축키용)
  Future<void> stepLine(int delta) =>
      seekToLine(lineIndex.value + delta);

  /// 현재 줄 기준 한 줄 간격(ms) — Ctrl+←/→ 줄 단위 싱크 이동용.
  /// 싱크 가사가 없거나 줄이 부족하면 null.
  int? currentLineGapMs({required bool towardPrevious}) {
    final synced = timedLyrics.value;
    if (synced == null) return null;
    return synced.lineGapMsAt(lineIndex.value, towardPrevious: towardPrevious);
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
    // 가사가 늦게 도착하면 그 자리에서 줄을 다시 잡는다 —
    // 정지 상태라면 다음 틱이 영영 오지 않는다.
    _recomputeLineIndex(position.value);
    _reloadTrackLevels(song, resolvedSlot);
    _reloadVocalSegments(song);

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

  /// 반주 파일을 다시 물린다.
  ///
  /// [keepPosition]이면 지금 위치와 재생 여부를 그대로 이어 간다 —
  /// 노래를 부르는 도중에 키를 바꿔도 처음으로 돌아가지 않게 하기 위해서다.
  Future<void> prepareAudioForSelection({bool keepPosition = false}) async {
    final settings = settingsProvider();
    final resumeAt = keepPosition ? position.value : null;
    final wasPlaying = keepPosition && state.value.playing;
    // 스냅샷을 덮어쓰기 **전에** 잡아 둔다. 템포가 바뀌면 같은 "노래의 지점"이
    // 다른 재생 위치가 되므로, 옛 축으로 원본 시각을 구한 뒤 새 축으로
    // 되돌려야 한다. 렌더 위치를 그대로 재사용하면 0.8배에서 25% 뒤로 튄다.
    final oldTempo = state.value.tempoScale;
    final oldStartMs = state.value.trackStartMs ?? 0;

    // 새 파일의 길이가 오기 전에 이전 곡 길이를 먼저 버린다.
    // 이 초기화를 prepareSelection **뒤**에 두면, 그 사이 도착한
    // onDurationChanged 값을 도로 0으로 덮어써 길이가 영영 0에 머문다
    // (진행바 총 시간·End 키·가사 추정 이동이 모두 죽는다).
    _update(state.value.copyWith(duration: Duration.zero));

    // 키·템포가 지정돼 있으면 미리 렌더한 변형본을 재생한다.
    String? overridePath;
    final song = state.value.song;
    final slot = state.value.trackSlot;
    final semitones = song == null ? 0 : settings.pitchForSong(song.id, slot);
    final tempo = song == null ? 1.0 : settings.tempoForSong(song.id, slot);
    if (song != null && slot != null && (semitones != 0 || tempo != 1)) {
      overridePath = await trackVariantResolver?.call(
        song,
        slot,
        semitones,
        tempo,
      );
    }

    // 템포가 바뀌면 파일 길이 자체가 달라지므로 트림 지점을 렌더 축으로 옮긴다.
    final track = song?.trackForSlot(slot ?? -1);
    _update(
      state.value.copyWith(
        tempoScale: tempo,
        trackStartMs: _toRenderedMs(track?.startMs, tempo),
        trackEndMs: _toRenderedMs(track?.endMs, tempo),
      ),
    );

    final result = await audio.prepareSelection(
      overridePath: overridePath,
      song: state.value.song,
      selectedTrackSlot: state.value.trackSlot,
      volume: settings.volume,
      // 템포는 파일에 구워져 있으므로 플레이어 배속은 언제나 1.0이다.
      // Windows의 setPlaybackRate는 IMFMediaEngine을 그대로 불러 음정이
      // 딸려 올라간다 — 키를 오프라인으로 뺀 이유와 같다. 1.0으로 고정하면
      // setPlaybackRate와 _clock.setRate의 짝이 어긋날 여지도 사라진다.
      playbackRate: 1,
      startMs: state.value.trackStartMs,
    );
    if (_disposed) return;

    // 이벤트 스트림에 맡기지 않고 준비 완료 시점에 위치를 확정한다.
    final start = Duration(milliseconds: state.value.trackStartMs ?? 0);
    _clock.anchor(start);
    position.value = start;

    _update(state.value.copyWith(audioReady: result.ready));

    // 위치 유지 요청이면 원래 자리로 돌아가 이어 부른다.
    if (resumeAt != null && result.ready) {
      final newStartMs = state.value.trackStartMs ?? 0;
      final sourceAt = LyricsSyncMath.toSource(
        resumeAt - Duration(milliseconds: oldStartMs),
        oldTempo,
      );
      final target = LyricsSyncMath.clampToTrim(
        LyricsSyncMath.toRendered(sourceAt, tempo) +
            Duration(milliseconds: newStartMs),
        startMs: state.value.trackStartMs,
        endMs: state.value.trackEndMs,
      );
      await audio.seek(target);
      _clock.anchor(target);
      position.value = target;
      _recomputeLineIndex(target);
      if (wasPlaying) {
        await audio.play(
          song: state.value.song,
          audioReady: true,
          playing: false,
        );
      }
      _syncTicker();
    }

    if (result.message != null) onMessage(result.message!);
  }

  Future<void> selectTrackSlot(int slot) async {
    final song = state.value.song;
    if (song == null) return;
    if (!song.availableTrackSlots.contains(slot)) return;
    final track = song.trackForSlot(slot);
    // 트림 지점의 렌더 축 환산은 prepareAudioForSelection이 템포를 알고 나서
    // 다시 한다. 여기서는 원본 값으로 두고 슬롯만 바꾼다.
    _update(
      state.value.copyWith(
        trackSlot: slot,
        trackStartMs: track?.startMs,
        trackEndMs: track?.endMs,
        lyricsOffsetMs: track?.lyricsOffsetMs ?? 0,
      ),
    );
    _reloadTrackLevels(song, slot);
    _reloadVocalSegments(song);
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

  /// 현재 곡의 노래 구간(없으면 null). 곡이 바뀌면 로더 완료까지 null이다.
  VocalSegments? _vocalSegments;

  /// 구간을 비웠다가 로더 완료 시 채운다. 곡이 바뀌었으면 결과를 버린다.
  void _reloadVocalSegments(Song song) {
    _vocalSegments = null;
    final loader = vocalSegmentsLoader;
    if (loader == null) return;
    unawaited(
      loader(song).then((segments) {
        if (_disposed) return;
        if (state.value.song?.id != song.id) return;
        _vocalSegments = segments;
        // 늦게 도착한 구간으로 그 자리에서 줄을 다시 잡는다 —
        // 정지 상태라면 다음 틱이 영영 오지 않는다.
        _recomputeLineIndex(position.value);
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
    // 템포는 파일에 구워지므로 플레이어 배속은 손대지 않는다.
    // setPlaybackRate와 _clock.setRate는 반드시 짝으로 움직여야 하는데,
    // 둘 다 부르지 않는 것이 그 짝을 지키는 가장 확실한 방법이다.
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
