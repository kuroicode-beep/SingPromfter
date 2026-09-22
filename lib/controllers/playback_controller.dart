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
import '../utils/playback_copy_plan.dart';
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

  /// 지금 재생에 물린 실제 파일 경로(키/템포 변형본·위치 보정본 포함).
  /// 녹음 시 이 파일에서 반주 구간을 잘라 테이크에 보관한다.
  ///
  /// 🔴 「원본 슬롯 파일」이 아니라 **플레이어가 실제로 연 파일**이다. 테이크의
  /// sourceAudioPath가 이 값을 그대로 받는다. 원본이 필요한 일(키·템포 변형본 렌더,
  /// 조성·EQ 분석, 내보내기)은 이 값을 쓰지 말고 repo.getBackingTrackPath로 집는다.
  final String? activeAudioPath;

  /// [activeAudioPath]의 성격 — VBR 원본 그대로인지, 위치 보정본인지.
  /// 화면의 「재생: 위치 보정본」 글자와 녹음 때의 VBR 안내가 이 값을 본다.
  final PlaybackSourceKind sourceKind;

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
    this.activeAudioPath,
    this.sourceKind = PlaybackSourceKind.plain,
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
    String? activeAudioPath,
    PlaybackSourceKind? sourceKind,
    bool clearSong = false,
    bool clearTrack = false,
    bool clearAudioPath = false,
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
      activeAudioPath: (clearTrack || clearAudioPath)
          ? null
          : (activeAudioPath ?? this.activeAudioPath),
      // 파일이 없어지면 성격도 함께 비운다 — 옛 곡의 「보정본」 글자가 남지 않게.
      sourceKind: (clearTrack || clearAudioPath)
          ? PlaybackSourceKind.plain
          : (sourceKind ?? this.sourceKind),
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

  /// 기본 키·템포로 재생할 때 「위치 보정본」(VBR MP3의 WAV 사본)이 있는지 묻는다.
  ///
  /// 🔴 **조회만** 해야 한다 — 없다고 굽기를 기다리면 첫 재생이 늦어진다. 없으면
  /// (path: null)을 돌려주고 굽기는 뒤에서 건다. 구워진 사본은 **다음에 물릴 때**부터
  /// 쓰인다. 변형본과 달리 원본을 대신하는 파일이 아니라 같은 소리의 재생용 사본이다.
  final Future<PlaybackCopyResolution> Function(Song song, int slot)?
  playbackCopyResolver;

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

  /// 틱을 기다리지 않은 **지금**의 위치.
  ///
  /// [position]은 화면 틱에서만 갱신돼 최대 17ms 낡아 있다. 가사 표시에는
  /// 충분하지만 녹음 조각의 곡 좌표를 재는 데는 그 오차가 그대로 실린다.
  Duration get precisePosition => _clock.value;
  final ValueNotifier<int> lineIndex = ValueNotifier(0);

  /// 사용자가 가사 자동 진행을 잠시 멈춘 상태. (전체화면의 자동 스크롤 토글)
  final ValueNotifier<bool> autoScrollPaused = ValueNotifier(false);

  /// 싱크 대기(]) — 켜져 있는 동안 줄 진행이 얼어붙는다. 재생은 계속되고,
  /// 해제할 때 기다린 시간이 오프셋으로 흡수된다(AppController 소관).
  final ValueNotifier<bool> lyricsHold = ValueNotifier(false);

  /// 현재 곡의 싱크 잠금(L) 상태 — 프롬프터 우상단 자물쇠 배지가 듣는다.
  /// 정본은 Song.syncLocked이고, 여기는 화면 표시용 거울이다
  /// (곡 로드·토글 때 AppController가 채운다).
  final ValueNotifier<bool> syncLockedView = ValueNotifier(false);

  /// 녹음 중(R) 상태 — 프롬프터 우하단 배지가 듣는다.
  /// 정본은 RecordingController이고, 여기는 표시용 거울이다
  /// (화면이 리스너로 채운다 — 잠금 배지와 같은 패턴).
  final ValueNotifier<bool> recordingView = ValueNotifier(false);

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
    this.playbackCopyResolver,
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
    lyricsHold.dispose();
    syncLockedView.dispose();
    recordingView.dispose();
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

  /// 지금 위치에 **재생으로** 도달했는가(마지막 seek·처음·정지 뒤에 재생이 걸렸다).
  ///
  /// VBR 원본을 틀다 멈춘 자리의 보고 위치 P는 실제 들린 내용과 최대 ±0.7초 어긋나
  /// 있다(seek 오차). 그 자리에서 위치 보정본으로 갈아타면 내용은 P로 정확해지지만
  /// 사용자에게는 「방금 멈춘 자리」가 옮겨진 것으로 들린다 — 화면이 이 값으로 그 안내를
  /// 실을지 정한다. 화살표·처음으로 정한 위치라면(seek 뒤 재생 없음) 옮겨지지 않는다.
  bool get positionHeardSinceSeek => _heardSinceSeek;
  bool _heardSinceSeek = false;

  void _handlePlayingChanged(bool playing) {
    if (_disposed) return;
    if (playing) {
      _clock.start();
      _practiceMarker = _clock.value;
      _heardSinceSeek = true;
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
    // 싱크 대기 중에는 줄이 움직이지 않는다 — 해제 때 오프셋이 흡수한다.
    if (lyricsHold.value) return;
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

  /// 가사 타임스탬프가 바뀐 뒤(부분 보정 등) 현재 위치로 줄을 다시 잡는다.
  /// 일시정지 중에는 다음 틱이 없어 이걸 부르지 않으면 화면이 안 바뀐다.
  void refreshLineIndex() => _recomputeLineIndex(position.value);

  /// **아직 시작하지 않은** 첫 줄 — Alt 부분 보정의 기준.
  ///
  /// 현재 줄(lineIndex)은 간주에서는 '방금 부른 줄'이라, 그걸 기준으로
  /// 밀면 재생 위치 밑의 타임스탬프가 움직여 하이라이트가 널뛴다.
  /// 전주면 0, 마지막 줄까지 다 시작했으면 lines.length(=밀 줄 없음).
  int upcomingLineIndex() {
    final synced = timedLyrics.value;
    if (synced == null || synced.isEmpty) return 0;
    final songTime = LyricsSyncMath.songTimeFor(
      playerPosition: position.value,
      trackStartMs: state.value.trackStartMs,
      lyricsOffsetMs: state.value.lyricsOffsetMs,
      tempoScale: state.value.tempoScale,
    );
    final target = songTime.inMilliseconds - synced.offsetMs;
    var i = 0;
    while (i < synced.lines.length &&
        synced.lines[i].time.inMilliseconds <= target) {
      i++;
    }
    return i;
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
    // 곡이 바뀌면 싱크 대기는 무의미하다 — 얼어붙은 채 남지 않게 푼다.
    lyricsHold.value = false;
    syncLockedView.value = song.syncLocked;
    _update(
      state.value.copyWith(
        song: song,
        trackSlot: resolvedSlot,
        trackStartMs: track?.startMs,
        trackEndMs: track?.endMs,
        lyricsOffsetMs: track?.lyricsOffsetMs ?? 0,
        clearTrack: resolvedSlot == null,
        // 새 곡의 파일은 prepareAudioForSelection이 정한다 — 그 전까지 옛 곡의
        // activeAudioPath·sourceKind가 남으면 고정 중 VBR 안내가 옛 곡의 성격으로
        // 새 곡에 잘못 뜬다(VbrNoticeGate가 곡마다 한 번이라 되돌릴 수도 없다). 성격만
        // 비운다(plain) — audioReady는 손대지 않는다: 무대 화면이 그 값으로 진행바를
        // 넣었다 뺐다 하므로 곡을 바꿀 때마다 접근성 노드가 생겼다 사라진다.
        clearAudioPath: true,
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

    // 기본 키·템포면 「위치 보정본」이 있는지 본다(VBR MP3 원본의 seek 어긋남 대책).
    // 🔴 재생 파일은 **이 함수 안에서만** 정해진다 — 사본이 뒤늦게 구워져도 재생·고정
    // 도중에 갈아끼우지 않는다(stop→setSource라 소리가 끊기고 조각 좌표가 깨진다).
    // 변형본(m4a)은 어긋나지 않으므로 묻지 않는다. 변형본은 언제나 **원본**에서 굽는다.
    var sourceKind = PlaybackSourceKind.plain;
    if (song != null && slot != null && semitones == 0 && tempo == 1) {
      final copy = await _resolvePlaybackCopy(song, slot);
      overridePath = copy.path;
      sourceKind = copy.kind;
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

    Future<AudioPrepareResult> prepare(String? path) => audio.prepareSelection(
      overridePath: path,
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
    var result = await prepare(overridePath);
    if (_disposed) return;
    // 보정본을 못 열었으면(깨짐·잠김) 원본으로 한 번 더 물린다 — 파생물 하나 때문에
    // 재생이 막히면 안 된다. 원본은 VBR이니 성격도 그렇게 적는다.
    if (!result.ready && sourceKind == PlaybackSourceKind.seekCopy) {
      sourceKind = PlaybackSourceKind.vbrOriginal;
      result = await prepare(null);
      if (_disposed) return;
    }

    // 이벤트 스트림에 맡기지 않고 준비 완료 시점에 위치를 확정한다.
    final start = Duration(milliseconds: state.value.trackStartMs ?? 0);
    _clock.anchor(start);
    position.value = start;
    // 위치를 처음(또는 유지)으로 새로 정했다 — 이어 갈 때는 들은 자리를 그대로 잇는다.
    if (resumeAt == null) _heardSinceSeek = false;

    _update(
      state.value.copyWith(
        audioReady: result.ready,
        activeAudioPath: result.path,
        clearAudioPath: result.path == null,
        sourceKind: sourceKind,
      ),
    );

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

  /// 위치 보정본 경로를 묻는다. 리졸버가 없거나, 던지거나, 늦으면 원본 그대로다 —
  /// 어떤 경우에도 첫 재생을 막지 않는다.
  Future<PlaybackCopyResolution> _resolvePlaybackCopy(
    Song song,
    int slot,
  ) async {
    final resolver = playbackCopyResolver;
    if (resolver == null) return kPlainPlayback;
    try {
      // async 함수로 한 번 감싸 **새 Future**를 만든다 — 리졸버가 `Future<Never>`(곧바로
      // 던지는 async)를 돌려주면 timeout의 onTimeout 타입이 안 맞아 여기서 던지고, 원래
      // 오류는 받는 이 없는 비동기 오류로 샌다(Future.sync는 같은 객체를 돌려줘 소용없다).
      Future<PlaybackCopyResolution> ask() async => await resolver(song, slot);
      return await ask().timeout(
        kPlaybackCopyLookupTimeout,
        onTimeout: () => kPlainPlayback,
      );
    } catch (e) {
      debugPrint('위치 보정본 조회 실패: $e');
      return kPlainPlayback;
    }
  }

  /// 그사이 구워진 위치 보정본으로 갈아탄다 — **멈춰 있고 받는 중도 아닐 때만.**
  /// 갈아탔으면 true. 녹음 고정을 켜거나 R 녹음을 걸기 직전에 부른다.
  ///
  /// 곡을 연 직후에 고정을 켜면 보정본은 2~3초 뒤에야 생긴다. 그대로 두면 그 세션의
  /// 조각은 전부 VBR 원본 위에서 받게 된다(「다음에 열 때 적용」을 한 세션 미루는 셈).
  /// 같은 자리에서 다시 물리는 것은 「키를 원래대로 되돌렸을 때」와 같은 길이라 위치가
  /// 그대로 이어진다. 🔴 재생 중이거나 조각이 열려 있으면 절대 손대지 않는다.
  ///
  /// 「위치가 이어진다」는 **보고 위치 P**다. VBR 원본에서 재생으로 도달한 P는 실제
  /// 들린 내용과 최대 ±0.7초 어긋나 있어(seek 오차, playback_copy_plan 머리말), 사본에서는
  /// 내용이 P로 정확해지는 대신 사용자에게는 「방금 멈춘 자리」가 그만큼 옮겨진 것으로
  /// 들린다. 좌표는 옳다 — 화면이 [positionHeardSinceSeek]를 보고 그 점만 알린다.
  Future<bool> adoptPlaybackCopyIfIdle() async {
    bool idleOnVbrOriginal() =>
        state.value.sourceKind == PlaybackSourceKind.vbrOriginal &&
        !state.value.playing &&
        !(isRecordingProvider?.call() ?? false);

    final song = state.value.song;
    final slot = state.value.trackSlot;
    if (song == null || slot == null || !idleOnVbrOriginal()) return false;
    final copy = await _resolvePlaybackCopy(song, slot);
    if (_disposed || copy.kind != PlaybackSourceKind.seekCopy) return false;
    // 묻는 사이에 재생이 걸렸거나 곡·슬롯이 바뀌었으면 그만둔다.
    if (!idleOnVbrOriginal()) return false;
    if (state.value.song?.id != song.id || state.value.trackSlot != slot) {
      return false;
    }
    await prepareAudioForSelection(keepPosition: true);
    return !_disposed && state.value.sourceKind == PlaybackSourceKind.seekCopy;
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
    final wasPlaying = state.value.playing;
    final message = await audio.pause(
      song: state.value.song,
      audioReady: state.value.audioReady,
      playing: wasPlaying,
    );
    if (message != null) {
      onMessage(message);
      return;
    }
    // 실제로 멈춘 경우에만 확정한다 — 이미 서 있던 시계의 앵커는 그대로가 정확하다.
    if (wasPlaying && state.value.song != null) await _confirmPausedAnchor();
  }

  /// `playing` 게이트를 거치지 않는 재생 — 녹음 고정의 스페이스 전용.
  /// 재생을 걸었으면 true. 막혔으면(반주 없음 등) 사유를 알리고 false.
  ///
  /// `state.playing`은 네이티브 호출이 끝난 뒤의 상태 이벤트로 서는 거울이라,
  /// 그걸로 게이트하면 「조각 마크는 찍혔는데 음악은 안 나오는」 틈이 생긴다.
  Future<bool> forcePlay() async {
    final message = await audio.forcePlay(
      song: state.value.song,
      audioReady: state.value.audioReady,
    );
    if (message == null) return true;
    onMessage(message);
    return false;
  }

  /// `playing` 게이트를 거치지 않는 일시정지 — 녹음 고정의 스페이스 전용.
  /// 재생 직후(상태 이벤트 전)에 멈춰도 음악이 혼자 계속 나오지 않는다.
  Future<void> forcePause() async {
    final message = await audio.forcePause(
      song: state.value.song,
      audioReady: state.value.audioReady,
    );
    // 멈출 반주가 없다 — 정지 요청에는 알릴 게 없고 확정할 위치도 없다.
    if (message != null || state.value.song == null) return;
    await _confirmPausedAnchor();
  }

  /// 멈춘 직후의 시계 앵커를 네이티브 위치로 확정한다.
  ///
  /// 보간 시계는 「마지막 기준점 + 경과시간」이라 멈춘 순간의 값에 수 ms~수십 ms의
  /// 추정 오차가 남는다. 표시에는 상관없지만 녹음 고정은 이 값을 **다음 조각의 곡
  /// 좌표(P0)** 로 쓴다 — 화살표 seek 없이 곧바로 다음 조각을 걸면 그 오차가 조각
  /// 위치에 그대로 실린다.
  Future<void> _confirmPausedAnchor() async {
    // 상태 이벤트를 기다리지 않고 시계를 먼저 세운다. 돌고 있는 시계에 resync하면
    // 25%만 당겨지고(blend) 이벤트가 올 때까지 계속 흘러 앵커가 밀린다.
    // 연습 시간은 세우기 전에 모아 둔다 — 뒤늦게 오는 이벤트는 멈춘 시계를 보고 건너뛴다.
    _accumulatePractice();
    _clock.pause();
    final native = await audio.currentPosition();
    if (_disposed || native == null) return;
    // 기다리는 사이 다시 재생이 걸렸으면 건드리지 않는다.
    if (_clock.isRunning) return;
    _clock.resync(native);
    position.value = _clock.value;
    // 정지 중에는 다음 틱이 없다 — 줄도 그 자리에서 맞춘다.
    _recomputeLineIndex(position.value);
  }

  Future<void> stop() async {
    await audio.stop();
    _accumulatePractice();
    _clock.reset();
    position.value = Duration.zero;
    lineIndex.value = 0;
    _heardSinceSeek = false;
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
    // 재생 중이었으면 새 자리부터 계속 듣는다 — 그 뒤의 정지 위치는 재생으로 도달한 것.
    _heardSinceSeek = state.value.playing;
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
    // 사용자가 정한 자리다 — 멈춘 채 여기서 갈아타도 들은 자리가 옮겨지지 않는다.
    // 재생 중의 이동이면 새 자리부터 계속 듣는다(그 뒤의 정지 위치는 재생으로 도달).
    _heardSinceSeek = state.value.playing;
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
