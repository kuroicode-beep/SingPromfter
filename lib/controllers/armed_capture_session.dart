// file: lib/controllers/armed_capture_session.dart
//
// 녹음 고정 — 상시 캡처 세션의 **프로세스 쪽**. 순수 부품은 capture_session.dart에 있다.
//
// 맡는 일: 고정을 켜는 순간 ffmpeg 하나를 띄워 raw PCM 세션 파일에 계속 받고,
// 스페이스는 벽시계 「표시(마크)」만 찍게 한다. 저장할 때 마크 한 쌍을 파일시각으로
// 환산해 세션 파일에서 잘라 낸다. 화면은 RecordingController(파사드)만 본다.
//
// 🔴 고정 대기 중(조각 없음)에는 주기 알림을 하지 않는다. 레벨 줄은 초당 수십 번
// 오는데, 그때마다 화면 전체가 다시 그려지면 접근성 브리지 크래시 노출이 커진다
// (lib/widgets/center_alert.dart 머리말). 상태·준비 여부·레벨 버킷이 **바뀔 때만** 알린다.
//
// 설계: docs/architecture/설계_20260922_녹음고정_상시캡처세션_유미.md (3.1~3.7)
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../services/process/process_runner.dart';
import '../utils/recording_latency.dart';
import 'capture_session.dart';
import 'recording_controller.dart';

/// 고정 세션의 상태.
/// off: 고정 꺼짐 / opening: 장치를 여는 중 / live: 소리가 들어오는 중 /
/// failed: 못 열었거나 도중에 끊겼다.
enum ArmedSessionState { off, opening, live, failed }

/// 장치가 열려 첫 프레임 줄이 오기까지 기다리는 상한. 실측은 0.5~0.65초다.
const Duration kSessionLiveTimeout = Duration(seconds: 3);

/// 고정을 켤 때의 입력 점검 길이(ms) — 세션 자신의 레벨 줄로 잰다(별도 프로브 없음).
const int kSessionInputCheckMs = 900;

/// 입력 점검의 벽시계 상한. 줄이 안 와도 「점검 중」에 영영 갇히지 않게 한다.
const Duration kSessionInputCheckCap = Duration(milliseconds: 2900);

/// 'q'를 보낸 뒤 종료를 기다리는 상한(실측 104~140ms). 넘으면 핸들로 끊는다.
const Duration kSessionQuitCap = Duration(seconds: 2);

/// 멈춤 감시 간격.
const Duration kSessionWatchdogInterval = Duration(milliseconds: 300);

/// 레벨 버킷을 정하는 최대값 유지 창 — 500ms 칸 × 4개(2초).
/// 줄마다의 값으로 버킷을 정하면 숨 쉴 때마다 「좋음↔작음」이 뒤집혀 알림이 쏟아진다.
const int kLevelHoldSlotUs = 500000;
const int kLevelHoldSlots = 4;

/// 상한(-t) 도달로 보는 여유(초). 마지막 pts가 상한에서 이 안쪽이어야 재기동한다.
const int kSessionCapSlackSeconds = 30;

/// 대기 중에 세션을 미리 갈아타는 나이(초) — 35분.
///
/// `-t` 상한은 고아 프로세스를 막는 안전장치인데, 조각 도중에 닿으면 조각이 잘리고
/// 고정까지 풀린다. 대기 중(조각·저장 대기 없음)에 여기서 미리 새 세션으로 갈아타면
/// 상한까지 10분이 남아, 조각 하나가 10분을 넘지 않는 한 도중에 닿지 않는다.
const int kSessionRolloverSeconds = 2100;

/// 사이드카 없는 세션 파일을 지우는 나이.
const Duration kStaleSessionAge = Duration(days: 7);

/// 조각 시작 마크. **벽시계(µs)로만** 들고 있는다 — 파일시각 환산은 저장할 때 한다.
@immutable
class TakeStartMark {
  const TakeStartMark({
    required this.id,
    required this.sessionId,
    required this.wallUs,
    required this.songPositionMs,
    this.markedAtMs,
    this.playbackAlreadyRunning = false,
    this.latencyCompensationMs = 0,
    this.context = const {},
  });

  /// 세션 안에서 조각을 가리는 번호.
  final int id;

  /// 이 마크가 속한 세션 파일. 상한 재기동으로 파일이 바뀌어도 옛 조각을 자를 수 있다.
  final String sessionId;

  /// 세션 시계(Stopwatch, µs) — 파일시각 환산용이다. epoch가 아니다.
  final int wallUs;

  /// 마크를 찍은 달력 시각(epoch ms). 사이드카에 실려 부팅 복구가 테이크의 recordedAt로
  /// 쓴다 — 복구 시각을 찍으면 같은 줄을 다시 받은 정상 조각이 이어붙이기 dedupe에서
  /// 옛 실패 조각에 밀린다(늦게 받은 쪽이 이기는 규칙). null이면 모른다(테스트용).
  final int? markedAtMs;

  /// 마크를 찍은 순간의 재생 위치(P0, ms).
  final int songPositionMs;

  /// 이미 재생 중일 때 찍었는가(R 키). 참이면 재생 시작 지연을 빼지 않는다.
  final bool playbackAlreadyRunning;

  /// 마크를 찍은 순간의 「녹음 지연 보정」(ms). 저장은 한참 뒤에 돌고 부팅 복구는 다음
  /// 실행에 돈다 — 그때 설정을 다시 읽으면 값을 바꾼 사이의 조각이 다른 좌표로 구워진다.
  /// [songPositionMs]는 보정 전의 P0 그대로다(교차 검증이 보정 전 값끼리 견준다).
  final int latencyCompensationMs;

  /// 화면이 그 순간 굳힌 컨텍스트(곡 id·슬롯·피치·반주 경로·템포 등). 해석하지 않는다.
  final Map<String, Object?> context;
}

/// 조각 끝 마크.
@immutable
class TakeEndMark {
  const TakeEndMark({
    required this.id,
    required this.sessionId,
    required this.wallUs,
    this.peakDbfs,
    this.measuredAnchorMs,
  });

  /// 짝이 되는 [TakeStartMark.id].
  final int id;
  final String sessionId;
  final int wallUs;

  /// 두 마크 사이에 관측한 최대 입력 레벨(dBFS). 레벨 줄이 없었으면 null.
  final double? peakDbfs;

  /// 조각 진행 중에 실측한 「세션 파일 t=0의 곡 좌표」(ms). 표본이 없으면 null.
  final int? measuredAnchorMs;
}

/// [ArmedCaptureSession.sliceTake]의 결과.
///
/// 🔴 null과 구분한다: **null = 너무 짧아 저장하지 않음**(정상), `ok == false` = 저장
/// 실패(세션 파일은 남겨 둔다 — 화면은 큰 경고로 알린다).
@immutable
class SlicedTake {
  const SlicedTake({
    required this.path,
    required this.fileName,
    required this.durationMs,
    required this.leadInMs,
    required this.songPositionMs,
    required this.peakDbfs,
    required this.timelineSuspect,
    required this.truncated,
    required this.message,
    this.timelineErrorMs,
    this.filledGapMs = 0,
    this.latencyAppliedMs = 0,
    this.context = const {},
  }) : ok = true;

  /// 실패 결과를 만든다.
  const SlicedTake.failure(
    this.message, {
    this.path = '',
    this.fileName = '',
    this.context = const {},
  }) : ok = false,
       durationMs = 0,
       leadInMs = 0,
       songPositionMs = 0,
       peakDbfs = null,
       timelineSuspect = false,
       truncated = false,
       timelineErrorMs = null,
       filledGapMs = 0,
       latencyAppliedMs = 0;

  final bool ok;
  final String path;
  final String fileName;

  /// 저장된 WAV의 길이(ms) — 리드인 포함.
  final int durationMs;

  /// 조각 머리의 리드인(ms). 곡 앞머리에서는 300보다 짧다 — 고정값으로 가정하지 말 것.
  final int leadInMs;

  /// 조각 t=0의 곡 좌표(ms).
  final int songPositionMs;

  /// 저장된 소리의 최대 창 RMS(dBFS). [isSilentTake]에 그대로 넣을 수 있다.
  final double? peakDbfs;

  /// 개루프 좌표와 실측 좌표가 40ms 넘게 어긋났다(표시만 — 값은 개루프를 쓴다).
  final bool timelineSuspect;

  /// 실측 − 개루프(ms). 실측 표본이 없으면 null.
  final int? timelineErrorMs;

  /// 세션 파일이 덜 자라 계획보다 짧게 저장했다.
  final bool truncated;

  /// 조각 도중의 pts 구멍(장치가 흘린 소리) 자리에 끼워 넣은 무음의 합(ms). 없으면 0.
  final int filledGapMs;

  /// [songPositionMs]에 이미 구워진 「녹음 지연 보정」(ms) — 테이크에 그대로 남긴다.
  final int latencyAppliedMs;
  final String message;
  final Map<String, Object?> context;
}

/// 부팅 복구로 되살린 조각 하나.
@immutable
class RecoveredSlice {
  const RecoveredSlice({
    required this.sessionId,
    required this.path,
    required this.fileName,
    required this.durationMs,
    required this.leadInMs,
    required this.songPositionMs,
    required this.peakDbfs,
    required this.truncated,
    required this.wasOpenTake,
    this.recordedAt,
    this.latencyAppliedMs = 0,
    this.context = const {},
  });

  final String sessionId;
  final String path;
  final String fileName;
  final int durationMs;
  final int leadInMs;
  final int songPositionMs;
  final double? peakDbfs;
  final bool truncated;

  /// 끝을 못 찍은 채 앱이 죽은 조각인가(끝 = 파일 길이와 「마지막 생존 표시 + 여유」 중 앞쪽).
  final bool wasOpenTake;

  /// 마크를 찍은 달력 시각 — 테이크의 recordedAt이 된다. 사이드카에 없으면(옛 형식)
  /// 세션 시작 시각 + 파일 오프셋으로 어림하고, 그것도 없으면 null(호출부가 지금 시각).
  ///
  /// 🔴 복구 시각을 쓰면 안 된다 — 저장이 실패해 마크가 남은 조각을 사용자가 다시
  /// 받았을 때, 복구 조각이 「더 늦게 받은 것」이 돼 이어붙이기가 정상 조각을 뺀다.
  final DateTime? recordedAt;

  /// [songPositionMs]에 이미 구워진 「녹음 지연 보정」(ms) — 마크를 찍을 때의 값이다.
  final int latencyAppliedMs;
  final Map<String, Object?> context;
}

/// 조작판 고정 글자에 넣을 문구. (순수 함수 — 테스트 대상)
///
/// [checked]는 「시계 잠금 + 입력 점검 끝」이다. 그 전에는 마이크가 열렸어도
/// 스페이스를 받지 않으므로 「여는 중」으로 보여 준다.
String armedSessionStatusLabel({
  required ArmedSessionState state,
  required bool checked,
  required InputLevelBucket bucket,
}) {
  return switch (state) {
    ArmedSessionState.off => '',
    ArmedSessionState.opening => '● 고정 — 마이크 여는 중',
    ArmedSessionState.live =>
      checked ? '● 고정 ON · 마이크 열림 · ${bucket.label}' : '● 고정 — 마이크 여는 중',
    ArmedSessionState.failed => '● 고정 — 마이크 끊김',
  };
}

/// 기본 세션 폴더 — `getApplicationSupportDirectory()/capture_sessions`.
///
/// OneDrive 밖(자라는 파일이 동기화에 걸린다)이고 %TEMP% 밖(이 PC는 05시 정리
/// 크론이 %TEMP%를 쓴다)이어야 한다.
Future<Directory> defaultCaptureSessionDir() async {
  final base = await getApplicationSupportDirectory();
  return Directory('${base.path}${Platform.pathSeparator}capture_sessions');
}

/// 끝을 찍었지만(또는 세션이 죽어 못 찍었지만) 아직 저장하지 않은 조각.
class _PendingTake {
  _PendingTake({required this.start, this.end, this.anchorMs, this.peakDbfs});

  final TakeStartMark start;

  /// null이면 세션이 죽어 끝을 못 찍은 조각 — 파일 끝까지 살린다.
  final TakeEndMark? end;
  final int? anchorMs;
  final double? peakDbfs;
}

/// ffmpeg 프로세스 하나 = 세션 파일 하나.
class _SessionRun {
  _SessionRun({
    required this.id,
    required this.pcmPath,
    required this.sidecarPath,
    required this.lockPath,
    required this.deviceName,
    required this.gain,
    required this.startedAtIso,
    required this.reopened,
  });

  final String id;
  final String pcmPath;
  final String sidecarPath;
  final String lockPath;
  final String deviceName;
  final double gain;
  final String startedAtIso;

  /// 상한 재기동으로 뜬 세션인가. 참이면 실패를 화면이 기다려 주지 않으니 콜백으로 알린다.
  final bool reopened;

  final CaptureClock clock = CaptureClock();
  final Completer<bool> live = Completer<bool>();
  final Completer<void> exit = Completer<void>();
  final List<String> errorLines = [];
  final List<_PendingTake> pending = [];

  JobHandle? job;
  StreamSubscription<String>? sub;
  bool isLive = false;
  bool exited = false;

  /// 우리가 끝내는 중이다 — 종료 감시가 이걸 「끊김」으로 오인하지 않게 한다.
  bool closing = false;
  bool deleteWhenDrained = false;
  bool filesDeleted = false;
  int? lastPtsUs;
  Future<void> sidecarChain = Future<void>.value();

  /// 소유 잠금([sessionLockFileName])을 쥔 핸들. 이 앱이 살아 있는 동안만 잠겨 있다.
  RandomAccessFile? lockFile;

  /// 마지막으로 사이드카를 줄에 올린 시각(µs) — 생존 표시 간격을 잰다.
  int lastSidecarUs = 0;

  /// 출력 줄 구독을 끊는다. 여러 번 불러도 된다.
  Future<void> cancelSub() async {
    await sub?.cancel();
    sub = null;
  }

  /// 소유 잠금을 놓는다. 여러 번 불러도 된다.
  Future<void> releaseLock() async {
    final file = lockFile;
    lockFile = null;
    if (file == null) return;
    try {
      await file.unlock();
    } on FileSystemException {
      // 닫으면 어차피 풀린다.
    }
    try {
      await file.close();
    } on FileSystemException {
      // 닫기 실패는 결과를 바꾸지 않는다 — 프로세스가 끝나면 OS가 닫는다.
    }
  }

  /// 기다릴 수 없을 때(dispose) 잠금 핸들을 그 자리에서 닫는다.
  void dropLockSync() {
    final file = lockFile;
    lockFile = null;
    if (file == null) return;
    try {
      file.closeSync();
    } on FileSystemException {
      // 프로세스가 끝나면 OS가 닫는다.
    }
  }
}

/// 녹음 고정 세션. [RecordingController]가 소유하고 화면은 컨트롤러만 본다.
class ArmedCaptureSession {
  ArmedCaptureSession({
    required ProcessRunner runner,
    required this.onChanged,
    required this.onLevel,
    required this.onLost,
    required this.positionProbe,
    int Function()? nowUs,
    Future<Directory> Function()? sessionDirBuilder,
    this.watchdogInterval = kSessionWatchdogInterval,
    this.liveTimeout = kSessionLiveTimeout,
  }) : _runner = runner,
       _sessionDirBuilder = sessionDirBuilder ?? defaultCaptureSessionDir {
    _nowUs = nowUs ?? () => _watch.elapsedMicroseconds;
  }

  final ProcessRunner _runner;
  final Future<Directory> Function() _sessionDirBuilder;
  final Stopwatch _watch = Stopwatch()..start();
  late final int Function() _nowUs;

  /// 상태·준비 여부·레벨 버킷이 바뀌었다(드물게 온다).
  final VoidCallback onChanged;

  /// 조각이 열려 있는 동안의 레벨 갱신(호출부가 120ms로 묶는다).
  final VoidCallback onLevel;

  /// 세션이 죽었다. 열려 있던 조각이 있으면 함께 넘긴다 — 화면이 끊긴 데까지 살린다.
  final void Function(String message, {TakeStartMark? openTake}) onLost;

  /// 지금 이 순간의 재생 위치(ms). 재생 중이 아니면 null. 교차 검증 표본에 쓴다.
  final int? Function() positionProbe;

  /// 멈춤 감시 간격. null이면 타이머를 돌리지 않는다(테스트가 직접 틱을 부른다).
  final Duration? watchdogInterval;
  final Duration liveTimeout;

  ArmedSessionState _state = ArmedSessionState.off;
  String? _error;
  _SessionRun? _current;
  final Map<String, _SessionRun> _runs = {};
  bool _disposed = false;

  // 재기동 때 다시 쓸 값.
  String? _ffmpegPath;
  String? _deviceName;
  double _gain = 1.0;

  // 열린 조각.
  TakeStartMark? _openTake;
  double? _takePeak;
  CaptureAnchorEstimator _takeAnchor = CaptureAnchorEstimator();
  int _markSeq = 0;
  int _runSeq = 0;

  // 입력 점검.
  Completer<double?>? _check;
  bool _checkDone = false;
  double? _checkPeak;
  int? _checkStartPtsUs;
  double? _inputPeak;
  Timer? _checkTimer;

  // 레벨.
  double? _dbfs;
  final Map<int, double> _holdSlots = {};

  // 멈춤 감시.
  Timer? _watchdog;
  int _lastRmsUs = 0;
  int? _lastSize;
  int _stagnantTicks = 0;
  bool _ticking = false;

  String _lastSignature = '';

  // 여는 도중에 close()가 오면 세대가 바뀐다 — 뒤늦게 프로세스를 띄우지 않게 한다.
  int _openGeneration = 0;

  ArmedSessionState get state => _state;

  /// 세션 프로세스가 떠 있는가(여는 중 포함).
  bool get isOpen =>
      _state == ArmedSessionState.opening || _state == ArmedSessionState.live;

  /// 세션의 ffmpeg가 **실제로** 장치를 쥐고 있는가.
  ///
  /// [isOpen]은 [markOpening] 직후부터 참이라, 프로세스를 띄우기 전에 도는 입력 장치
  /// 자동 선택(후보를 잠깐 열어 소리를 잰다)이 그 값으로는 「쥐고 있다」와 「아직
  /// 고르는 중」을 못 가린다.
  bool get holdsDevice => _current != null;

  /// 마지막 실패 원인. 없으면 null.
  String? get error => _error;

  /// 마크를 받아도 되는가 — live + 시계 잠금 + 입력 점검 끝 + 무음 아님.
  bool get isReady {
    final run = _current;
    return _state == ArmedSessionState.live &&
        run != null &&
        run.clock.isLocked &&
        _checkDone &&
        !isSilentTake(_inputPeak);
  }

  bool get isTakeOpen => _openTake != null;

  /// 지금 입력 레벨(dBFS). 고정 대기 중에는 값이 바뀌어도 알리지 않는다.
  double? get dbfs => _dbfs;

  /// 입력 점검에서 본 최대 레벨(dBFS). 점검이 안 끝났으면 null.
  double? get inputPeakDbfs => _checkDone ? _inputPeak : null;

  /// 입력 점검이 끝났는가(결과가 무음이어도 참).
  bool get isInputChecked => _checkDone;

  /// 입력 점검 결과를 기다린다. 세션이 없으면 곧바로 마지막 결과를 준다.
  Future<double?> get inputCheck =>
      _check?.future ?? Future<double?>.value(inputPeakDbfs);

  /// 최근 2초의 최대 레벨로 정한 버킷.
  InputLevelBucket get levelBucket {
    double? best;
    for (final value in _holdSlots.values) {
      if (best == null || value > best) best = value;
    }
    return inputLevelBucket(best);
  }

  /// 조작판 고정 글자(설계 3.7).
  String get statusLabel => armedSessionStatusLabel(
    state: _state,
    checked: (_current?.clock.isLocked ?? false) && _checkDone,
    bucket: levelBucket,
  );

  /// 열린 조각의 길이. 없으면 0.
  Duration get takeElapsed {
    final open = _openTake;
    if (open == null) return Duration.zero;
    final us = _nowUs() - open.wallUs;
    return Duration(microseconds: us < 0 ? 0 : us);
  }

  /// 아직 저장하지 않은 마크가 있는가(열린 조각 포함).
  bool get hasUnslicedMarks =>
      _openTake != null || _runs.values.any((run) => run.pending.isNotEmpty);

  /// 지금 세션 파일의 경로(테스트·진단용).
  String? get currentPcmPath => _current?.pcmPath;

  /// 지금 세션의 시계(테스트·진단용).
  CaptureClock? get currentClock => _current?.clock;

  /// 「여는 중」으로 먼저 바꾼다 — ffmpeg·장치를 찾는 동안에도 화면이 상태를 보여 준다.
  /// 돌려주는 값은 이번 열기의 **세대**다. [open]·[failBeforeOpen]에 그대로 넘기면,
  /// 그 사이에 [close]가 온 열기는 조용히 버려진다.
  int markOpening() {
    if (_disposed) return _openGeneration;
    _error = null;
    _resetInputCheck();
    _setState(ArmedSessionState.opening);
    return _openGeneration;
  }

  /// 그 세대의 열기가 이미 닫혔는가.
  bool _isStale(int? generation) =>
      generation != null && generation != _openGeneration;

  /// 열기 전에 실패했다(ffmpeg·장치 없음).
  void failBeforeOpen(String message, {int? generation}) {
    if (_disposed || _isStale(generation)) return;
    _error = message;
    _completeCheck(null);
    _setState(ArmedSessionState.failed);
  }

  /// 이미 여는 중이면 그 결과를 기다린다.
  Future<bool> waitLive() async {
    final run = _current;
    if (run == null) return false;
    if (run.isLive) return true;
    return run.live.future;
  }

  /// 세션을 연다. live가 되면 true, 상한([liveTimeout]) 안에 못 열면 false.
  /// 입력 점검은 이어서 돈다 — 결과는 [inputCheck]로 기다린다.
  Future<bool> open({
    required String ffmpegPath,
    required String deviceName,
    double gain = 1.0,
    int? generation,
  }) async {
    if (_disposed || _isStale(generation)) return false;
    if (_current != null && isOpen) return waitLive();
    _ffmpegPath = ffmpegPath;
    _deviceName = deviceName;
    _gain = gain;
    return _startRun(reopened: false);
  }

  /// ffmpeg 하나를 띄우고 live를 기다린다.
  Future<bool> _startRun({required bool reopened}) async {
    final ffmpegPath = _ffmpegPath;
    final deviceName = _deviceName;
    if (ffmpegPath == null || deviceName == null) return false;
    _error = null;
    _resetInputCheck();
    _holdSlots.clear();
    _dbfs = null;
    _setState(ArmedSessionState.opening);

    final generation = _openGeneration;
    bool abandoned() => _disposed || generation != _openGeneration;
    _SessionRun? run;
    try {
      final dir = await _sessionDirBuilder();
      await dir.create(recursive: true);
      if (abandoned()) return false;
      final id = 'cap_${DateTime.now().millisecondsSinceEpoch}_${_runSeq++}';
      final created = _SessionRun(
        id: id,
        pcmPath: _join(dir.path, sessionPcmFileName(id)),
        sidecarPath: _join(dir.path, sessionSidecarFileName(id)),
        lockPath: _join(dir.path, sessionLockFileName(id)),
        deviceName: deviceName,
        gain: _gain,
        startedAtIso: DateTime.now().toIso8601String(),
        reopened: reopened,
      );
      run = created;
      // 소유 잠금을 사이드카보다도 먼저 쥔다 — 사이드카가 보이는 순간부터 다른
      // 인스턴스의 부팅 복구가 「살아 있는 남의 세션」임을 알 수 있어야 한다.
      await _acquireLock(created);
      // 사이드카를 **먼저** 쓴다. 사이드카 없이 죽으면 최대 259MB짜리 PCM이
      // 7일 동안 남는다 — 있으면 다음 부팅에서 곧바로 치운다.
      await _writeSidecarNow(created);
      if (abandoned()) {
        await _discardRun(created);
        return false;
      }

      final job = _runner.start(
        ffmpegPath,
        buildSessionCaptureArgs(
          deviceName: deviceName,
          outputPath: created.pcmPath,
          gain: _gain,
        ),
      );
      created.job = job;
      _current = created;
      _runs[id] = created;
      _lastRmsUs = _nowUs();
      _lastSize = null;
      _stagnantTicks = 0;
      created.sub = job.lines.listen(
        (line) => _onLine(created, line),
        onError: (Object e) => debugPrint('고정 세션 스트림 오류: $e'),
      );
      unawaited(job.exitCode.then((code) => _onExit(created, code)));

      final live = await created.live.future.timeout(
        liveTimeout,
        onTimeout: () => false,
      );
      if (!live && !created.closing && identical(_current, created)) {
        _failOpen(created, '마이크가 ${liveTimeout.inSeconds}초 안에 열리지 않았습니다.');
      }
      return live;
    } catch (e) {
      debugPrint('고정 세션 시작 실패: $e');
      final failed = run;
      if (failed != null) {
        _failOpen(failed, '녹음 고정을 시작하지 못했습니다 — $e');
      } else {
        failBeforeOpen('녹음 고정을 시작하지 못했습니다 — $e');
        if (reopened) onLost(_error!, openTake: null);
      }
      return false;
    }
  }

  /// 세션 소유 잠금을 쥔다. 못 쥐어도 녹음은 막지 않는다 — 복구 판정의 근거일 뿐이다.
  ///
  /// 앱이 죽으면 OS가 핸들을 닫아 잠금이 풀린다. 자식 ffmpeg는 이 핸들을 물려받지
  /// 않으므로(표준 입출력만 물려준다), 고아가 남아도 「소유 앱은 죽었다」가 드러난다.
  Future<void> _acquireLock(_SessionRun run) async {
    RandomAccessFile? file;
    try {
      file = await File(run.lockPath).open(mode: FileMode.write);
      await file.lock(FileLock.exclusive);
      run.lockFile = file;
    } on FileSystemException catch (e) {
      debugPrint('세션 잠금 실패: ${e.message}');
      try {
        await file?.close();
        // 잠기지 않은 .lock은 「소유 앱이 죽었다」로 읽힌다 — 틀린 단서는 남기지 않는다.
        // (없으면 복구가 파일 성장 여부로 되돌아가 판단한다.)
        final stray = File(run.lockPath);
        if (await stray.exists()) await stray.delete();
      } on FileSystemException {
        // 못 지워도 녹음은 계속한다.
      }
    }
  }

  /// ffmpeg 출력 한 줄. 프레임 머리줄은 시계로, 레벨 줄은 레벨·점검으로 간다.
  void _onLine(_SessionRun run, String line) {
    if (_disposed || run.closing || !identical(run, _current)) return;
    // 🔴 도착 시각은 **맨 먼저** 찍는다. 파싱 뒤에 찍으면 그만큼이 지터로 실린다.
    final arrivalUs = _nowUs();
    final ptsUs = parseAmetadataFramePtsUs(line);
    if (ptsUs != null) {
      run.clock.addFrame(arrivalUs: arrivalUs, ptsUs: ptsUs);
      run.lastPtsUs = ptsUs;
      if (!run.isLive) _becomeLive(run);
      if (_openTake != null) {
        // 교차 검증 표본 — 파일시각은 pts에서 그때까지의 구멍을 뺀 값이다.
        _takeAnchor.addFrame(
          ptsMs: usToMs(ptsUs - run.clock.totalGapUs),
          positionMs: positionProbe(),
        );
      }
      if (_shouldRollOver(run, ptsUs)) {
        unawaited(_rollover(run));
        return;
      }
      _afterLine();
      return;
    }
    final rms = parseRmsLevel(line);
    if (rms != null) {
      _lastRmsUs = arrivalUs;
      _lastSize = null;
      _stagnantTicks = 0;
      _dbfs = rms;
      _holdLevel(arrivalUs, rms);
      if (_openTake != null && (_takePeak == null || rms > _takePeak!)) {
        _takePeak = rms;
      }
      _feedInputCheck(run, rms);
      _afterLine();
      return;
    }
    final detail = ffmpegErrorDetail(line);
    if (detail != null && run.errorLines.length < 5) run.errorLines.add(detail);
  }

  /// 첫 프레임 줄 = 장치가 열려 소리가 흐른다.
  void _becomeLive(_SessionRun run) {
    run.isLive = true;
    _lastRmsUs = _nowUs();
    if (!run.live.isCompleted) run.live.complete(true);
    _checkTimer?.cancel();
    _checkTimer = Timer(kSessionInputCheckCap, _finishInputCheck);
    _startWatchdog();
    _state = ArmedSessionState.live;
  }

  /// 줄 하나를 반영한 뒤의 알림. 대기 중에는 **바뀐 것이 있을 때만** 알린다.
  void _afterLine() {
    if (_notifyIfChanged()) return;
    if (_openTake != null) onLevel();
  }

  /// 화면에 보이는 값의 지문. 이게 같으면 다시 그릴 이유가 없다.
  String _signature() =>
      '${_state.index}|$isReady|${_openTake != null}|${levelBucket.index}|'
      '${_checkDone ? 1 : 0}';

  /// 지문이 바뀌었으면 알린다. 알렸으면 true.
  bool _notifyIfChanged() {
    if (_disposed) return false;
    final signature = _signature();
    if (signature == _lastSignature) return false;
    _lastSignature = signature;
    onChanged();
    return true;
  }

  /// 상태를 바꾸고 알린다.
  void _setState(ArmedSessionState next) {
    _state = next;
    _notifyIfChanged();
  }

  /// 최근 2초의 최대 레벨을 500ms 칸으로 들고 있는다.
  void _holdLevel(int nowUs, double rms) {
    final slot = nowUs ~/ kLevelHoldSlotUs;
    final known = _holdSlots[slot];
    if (known == null || rms > known) _holdSlots[slot] = rms;
    _holdSlots.removeWhere((key, _) => key <= slot - kLevelHoldSlots);
  }

  /// 입력 점검을 새로 시작할 수 있게 비운다.
  void _resetInputCheck() {
    _checkTimer?.cancel();
    _checkTimer = null;
    final old = _check;
    if (old != null && !old.isCompleted) old.complete(null);
    _check = Completer<double?>();
    _checkDone = false;
    _checkPeak = null;
    _checkStartPtsUs = null;
    _inputPeak = null;
  }

  /// 레벨 줄 하나를 입력 점검에 넣는다. 길이는 **pts**로 잰다 — 줄이 몰려 와도
  /// 실제로 들어온 소리의 길이를 센다.
  void _feedInputCheck(_SessionRun run, double rms) {
    if (_checkDone) return;
    final ptsUs = run.lastPtsUs;
    if (ptsUs == null) return;
    final startUs = _checkStartPtsUs ??= ptsUs;
    if (_checkPeak == null || rms > _checkPeak!) _checkPeak = rms;
    if (ptsUs - startUs >= kSessionInputCheckMs * 1000) _finishInputCheck();
  }

  /// 입력 점검을 끝낸다. 재기동한 세션이 무음이면 기다려 줄 화면이 없으니 끊김으로 알린다.
  void _finishInputCheck() {
    if (_checkDone || _disposed) return;
    final run = _current;
    _completeCheck(_checkPeak);
    if (run != null && run.reopened && isSilentTake(_inputPeak)) {
      _loseSession(run, '녹음 입력에 소리가 없습니다 — 마이크와 믹서를 확인해 주세요.');
      return;
    }
    _notifyIfChanged();
  }

  /// 점검 결과를 굳히고 기다리는 쪽을 깨운다.
  void _completeCheck(double? peak) {
    _checkTimer?.cancel();
    _checkTimer = null;
    _checkDone = true;
    _inputPeak = peak;
    final check = _check;
    if (check != null && !check.isCompleted) check.complete(peak);
  }

  /// 조각 시작을 찍는다. **동기** — 벽시계만 저장하고 파일 IO는 하지 않는다.
  /// 준비가 안 됐거나 이미 조각이 열려 있으면 null.
  TakeStartMark? markTakeStart({
    required int songPositionMs,
    bool playbackAlreadyRunning = false,
    int latencyCompensationMs = 0,
    Map<String, Object?> context = const {},
  }) {
    // 🔴 벽시계는 맨 먼저 읽는다 — 아래 검사에 드는 시간이 마크에 실리면 안 된다.
    final wallUs = _nowUs();
    final run = _current;
    if (_disposed || run == null || !isReady || _openTake != null) return null;
    final mark = TakeStartMark(
      id: _markSeq++,
      sessionId: run.id,
      wallUs: wallUs,
      songPositionMs: songPositionMs,
      // 달력 시각도 지금 찍는다 — 복구된 조각의 recordedAt이 된다(wallUs는 Stopwatch).
      markedAtMs: DateTime.now().millisecondsSinceEpoch,
      playbackAlreadyRunning: playbackAlreadyRunning,
      latencyCompensationMs: clampRecordingLatencyMs(latencyCompensationMs),
      context: Map.unmodifiable(context),
    );
    _openTake = mark;
    _takePeak = null;
    _takeAnchor = CaptureAnchorEstimator();
    _afterMark(run);
    return mark;
  }

  /// 조각 끝을 찍는다. **동기.** 열린 조각이 없으면 null.
  TakeEndMark? markTakeEnd() {
    final wallUs = _nowUs();
    final open = _openTake;
    if (open == null) return null;
    // 재생을 멈추면 위치가 서 버린다 — 표본은 그 전에 닫는다.
    _takeAnchor.freeze();
    final end = TakeEndMark(
      id: open.id,
      sessionId: open.sessionId,
      wallUs: wallUs,
      peakDbfs: _takePeak,
      measuredAnchorMs: _takeAnchor.anchorMs,
    );
    _openTake = null;
    final run = _runs[open.sessionId];
    if (run != null) {
      run.pending.add(
        _PendingTake(
          start: open,
          end: end,
          anchorMs: end.measuredAnchorMs,
          peakDbfs: end.peakDbfs,
        ),
      );
      _afterMark(run);
    }
    return end;
  }

  /// 열린 조각을 없던 일로 한다(재생이 막혔을 때).
  void cancelOpenTake() {
    final open = _openTake;
    if (open == null) return;
    _openTake = null;
    final run = _runs[open.sessionId];
    if (run != null) _afterMark(run);
  }

  /// 마크 뒤의 뒷일 — 알림과 사이드카. 🔴 **핫패스 밖으로 미룬다.**
  /// 호출부는 마크 직후 같은 동기 스택에서 재생을 건다. 알림은 그 호출이 나간 뒤의
  /// 마이크로태스크로, 사이드카(파일 IO)는 다음 이벤트 루프로 넘긴다.
  void _afterMark(_SessionRun run) {
    scheduleMicrotask(_notifyIfChanged);
    Timer.run(() => _scheduleSidecar(run));
  }

  /// 마크 한 쌍을 세션 파일에서 잘라 [outputPath]에 WAV로 저장한다.
  ///
  /// [end]가 null이면 「세션이 죽어 끝을 못 찍은 조각」으로 보고 파일 끝까지 살린다.
  /// 환산은 **지금의 수렴된 시계**로 한다(구멍은 각 마크 시각까지만).
  /// 돌려주는 값: null = 너무 짧음, `ok == false` = 저장 실패(세션 파일은 남긴다).
  /// 성공해도 마크는 대기열에 남는다 — 목록 등록 뒤 [confirmTakeSaved]로 뺀다.
  Future<SlicedTake?> sliceTake(
    TakeStartMark start,
    TakeEndMark? end, {
    required String outputPath,
  }) async {
    final fileName = _baseName(outputPath);
    SlicedTake fail(String message) => SlicedTake.failure(
      message,
      path: outputPath,
      fileName: fileName,
      context: start.context,
    );

    final run = _runs[start.sessionId];
    if (run == null) return fail('세션 파일을 찾지 못했습니다.');
    final pending = run.pending
        .where((take) => take.start.id == start.id)
        .firstOrNull;

    // 세션이 더 자라지 않으면 실제 길이로 끝을 자른다. 살아 있으면 null로 두어
    // 끝 바이트가 디스크에 닿기를 기다리게 한다(실시간보다 0~70ms 늦다).
    int? fileLengthMs;
    if (end == null || run.exited || run.closing) {
      await run.exit.future.timeout(kSessionQuitCap, onTimeout: () {});
      final length = await _handleLength(run.pcmPath);
      if (length < 0) return fail('세션 파일을 열지 못했습니다.');
      fileLengthMs = length ~/ kSessionBytesPerMs;
    }

    final startUs = run.clock.fileTimeUsAt(start.wallUs);
    if (startUs == null) return fail('세션 시계가 잠기기 전의 마크입니다.');
    final startFileMs = usToMs(startUs);
    final int endFileMs;
    if (end == null) {
      // 정지 키를 누른 적이 없으니 끝 60ms를 깎을 이유가 없다 — 깎일 만큼 더해 둔다.
      endFileMs = fileLengthMs! + kStopClickTrimMs;
    } else {
      final endUs = run.clock.fileTimeUsAt(end.wallUs);
      if (endUs == null) return fail('세션 시계가 잠기기 전의 마크입니다.');
      endFileMs = usToMs(endUs);
    }

    final plan = computeTakeSlice(
      startFileMs: startFileMs,
      endFileMs: endFileMs,
      songPosAtStartMs: start.songPositionMs,
      playbackAlreadyRunning: start.playbackAlreadyRunning,
      fileLengthMs: fileLengthMs,
      latencyCompensationMs: start.latencyCompensationMs,
    );
    if (plan == null) {
      // 너무 짧다 — 저장할 게 없으니 대기열에서 뺀다.
      await _settle(run, pending);
      return null;
    }

    // 시작 마크 **뒤**(본 내용)의 구멍만 메운다. 리드인 안의 구멍은 그대로 둔다 —
    // 클릭 가드와 `songPositionMs` 불변식을 건드리지 않고, 이어붙이기는 어차피 건너뛴다.
    final fills = <TakeFill>[
      for (final hole in run.clock.holesInFileRange(
        startUs,
        plan.sliceEndMs * 1000,
      ))
        (
          atMs: usToMs(hole.fileUs) - plan.sliceStartMs,
          lengthMs: usToMs(hole.lengthUs),
        ),
    ];

    Future<TakeWriteResult> write() => writeTakeFromSession(
      sessionPath: run.pcmPath,
      plan: plan,
      outputPath: outputPath,
      fills: fills,
    );
    var result = await write();
    // 살아 있는 세션이 잠깐 밀린 것이면(디스크 정체 등) 나머지가 곧 닿는다 — 한 번만
    // 더 기다려 같은 자리에 다시 자른다. 그래도 짧으면 화면이 `truncated`로 알린다.
    if (result.ok &&
        result.truncated &&
        fileLengthMs == null &&
        !run.exited &&
        !run.closing) {
      final retry = await write();
      if (retry.ok) result = retry;
    }
    // 실패하면 대기열에 남긴다 — 세션 파일이 지워지지 않아 다시 자를 수 있다.
    if (!result.ok) return fail(result.message);

    // 교차 검증(표시만): 개루프 식과 조각 진행 중에 잰 좌표를 견준다.
    // 🔴 「녹음 지연 보정」은 여기 넣지 않는다. 두 값은 모두 **표시 위치** 축이라 입력
    // 지연이 서로 상쇄된다 — 한쪽에만 빼면 보정값이 40ms를 넘는 순간 멀쩡한 조각마다
    // 「곡 위치가 부정확할 수 있습니다」가 붙는다.
    final latency = start.playbackAlreadyRunning ? 0 : kPlaybackStartLatencyMs;
    final openLoopMs = start.songPositionMs - latency;
    final anchorMs = end?.measuredAnchorMs ?? pending?.anchorMs;
    final measuredMs = anchorMs == null ? null : anchorMs + startFileMs;

    // 🔴 여기서 대기열에서 빼지 않는다. 목록(recordings.json)에 닿기 전에 앱이 끝나면
    // 사이드카에서 이미 빠진 조각은 목록에도 없고 복구도 안 된다 — 화면이 등록을
    // 확인한 뒤 [confirmTakeSaved]로 뺀다.
    return SlicedTake(
      path: outputPath,
      fileName: fileName,
      durationMs: result.writtenMs,
      leadInMs: plan.leadInMs,
      songPositionMs: plan.songPositionMs,
      // 저장된 실물로 잰 값이 정본이다. 없으면 마크 사이에 본 레벨 줄의 최대값.
      peakDbfs: result.peakDbfs ?? end?.peakDbfs ?? pending?.peakDbfs,
      timelineSuspect: isTimelineSuspect(
        openLoopMs: openLoopMs,
        measuredMs: measuredMs,
      ),
      timelineErrorMs: measuredMs == null ? null : measuredMs - openLoopMs,
      truncated: result.truncated,
      filledGapMs: result.filledMs,
      latencyAppliedMs: start.latencyCompensationMs,
      message: result.message,
      context: start.context,
    );
  }

  /// 조각이 녹음 목록에 **등록됐다** — 대기열에서 빼고 미뤄 둔 세션 정리를 한다.
  ///
  /// 등록에 실패했으면 부르지 않는다. 그러면 마크가 사이드카에 남아 세션 파일이
  /// 지워지지 않고, 다음 부팅의 복구가 「복구됨」 조각으로 되살린다.
  Future<void> confirmTakeSaved(TakeStartMark start) async {
    final run = _runs[start.sessionId];
    if (run == null) return;
    final pending = run.pending
        .where((take) => take.start.id == start.id)
        .firstOrNull;
    await _settle(run, pending);
  }

  /// 조각 하나의 처리가 끝났다 — 대기열에서 빼고, 비었으면 미뤄 둔 파일 정리를 한다.
  Future<void> _settle(_SessionRun run, _PendingTake? pending) async {
    if (pending != null) run.pending.remove(pending);
    _scheduleSidecar(run);
    if (run.pending.isEmpty &&
        run.deleteWhenDrained &&
        !identical(run, _current)) {
      await _discardRun(run);
    }
  }

  /// 세션을 닫는다. 'q' → [quitCap] 대기 → 안 끝나면 핸들로 끊는다.
  ///
  /// 저장하지 않은 마크가 있는 세션 파일은 **지우지 않는다** — 목록 등록이 확인되는
  /// 대로([confirmTakeSaved]) 지우고, 끝내 못 하면 다음 부팅의 복구가 사이드카로 살린다.
  Future<void> close({
    bool deleteFiles = true,
    Duration quitCap = kSessionQuitCap,
  }) async {
    // 열린 조각은 끝을 찍어 대기열로 옮긴다 — 부른 소리를 버리지 않는다.
    if (_openTake != null) markTakeEnd();
    _openGeneration++;
    _stopTimers();
    _completeCheck(_checkDone ? _inputPeak : _checkPeak);
    final run = _current;
    _current = null;
    if (run != null) await _quit(run, quitCap);
    for (final each in _runs.values.toList()) {
      if (each.pending.isEmpty) {
        if (deleteFiles) {
          await _discardRun(each);
        } else {
          _runs.remove(each.id);
          await each.releaseLock();
        }
      } else {
        each.deleteWhenDrained = deleteFiles;
        _scheduleSidecar(each);
      }
    }
    _error = null;
    _dbfs = null;
    _holdSlots.clear();
    _setState(ArmedSessionState.off);
  }

  /// 프로세스 하나를 우아하게 끝낸다. 안 끝나면 **우리 핸들로만** 끊는다 —
  /// 이 PC는 다른 작업의 ffmpeg가 상시 돌아서 이름·PID로 죽이면 안 된다.
  Future<void> _quit(_SessionRun run, Duration cap) async {
    run.closing = true;
    if (!run.live.isCompleted) run.live.complete(false);
    final job = run.job;
    if (job != null && !run.exited) {
      job.writeStdin('q');
      try {
        await run.exit.future.timeout(cap);
      } on TimeoutException {
        job.cancel();
        await run.exit.future.timeout(
          const Duration(milliseconds: 500),
          onTimeout: () {},
        );
      }
    }
    await run.cancelSub();
  }

  /// 프로세스가 끝났다. 우리가 끝낸 게 아니면 즉사·상한 도달·끊김을 가린다.
  void _onExit(_SessionRun run, int code) {
    run.exited = true;
    if (!run.exit.isCompleted) run.exit.complete();
    if (_disposed || run.closing || !identical(run, _current)) return;
    final detail = run.errorLines.isEmpty
        ? '종료 코드 $code'
        : run.errorLines.first;
    if (!run.isLive) {
      _failOpen(run, '마이크를 열지 못했습니다 — $detail');
      return;
    }
    // 상한(-t) 도달: 정상 종료 + 오류 줄 없음 + 마지막 pts가 상한 근처.
    // pts까지 보는 이유 — 코드 0만 믿으면 열자마자 끝나는 장치에서 재기동이 돈다.
    final capUs = (kSessionMaxSeconds - kSessionCapSlackSeconds) * 1000000;
    final capReached =
        code == 0 && run.errorLines.isEmpty && (run.lastPtsUs ?? 0) >= capUs;
    if (capReached && _openTake == null) {
      unawaited(_reopen(run));
      return;
    }
    _loseSession(
      run,
      capReached
          ? '고정 세션이 상한(${kSessionMaxSeconds ~/ 60}분)에 닿아 조각이 끊겼습니다.'
          : '마이크 연결이 끊겼습니다 — $detail',
    );
  }

  /// 상한에 닿은 세션을 이어서 다시 연다. 옛 파일은 저장 대기 조각이 있을 수 있어 둔다.
  Future<void> _reopen(_SessionRun old) async {
    _stopTimers();
    await old.cancelSub();
    _current = null;
    if (_disposed) return;
    await _startRun(reopened: true);
  }

  /// 대기 중에 세션이 [kSessionRolloverSeconds]를 넘겼는가 — 미리 갈아탈 때다.
  ///
  /// 저장 대기 조각이 있으면 갈아타지 않는다. 끝 바이트가 디스크에 닿기 전에 'q'를
  /// 보내면 장치 버퍼 분량(50~100ms)만큼 조각의 끝이 잘릴 수 있다.
  bool _shouldRollOver(_SessionRun run, int ptsUs) =>
      _state == ArmedSessionState.live &&
      _checkDone &&
      _openTake == null &&
      run.pending.isEmpty &&
      ptsUs >= kSessionRolloverSeconds * 1000000;

  /// 상한이 조각 도중에 닿지 않게, 대기 중에 미리 새 세션으로 갈아탄다(약 1.5초).
  /// 그동안 스페이스는 「마이크를 여는 중」으로 거절된다(isReady가 거짓).
  ///
  /// [_reopen]과 다른 점: 옛 프로세스가 아직 살아 있다 — 'q'로 끝낸 뒤에 연다.
  /// 옛 세션 파일은 목록에 남겨, 고정을 끌 때 함께 지운다(설계 3.4).
  Future<void> _rollover(_SessionRun old) async {
    final generation = _openGeneration;
    _stopTimers();
    _setState(ArmedSessionState.opening);
    // _quit은 첫 줄에서 closing을 **동기로** 세운다 — 뒤따르는 줄이 또 갈아타기를
    // 걸거나, 종료 감시가 이걸 끊김으로 오인하지 않는다.
    await _quit(old, kSessionQuitCap);
    // 그사이 close()가 왔다 — 새 세션을 띄우지 않는다.
    if (_disposed ||
        generation != _openGeneration ||
        !identical(old, _current)) {
      return;
    }
    _current = null;
    await _startRun(reopened: true);
  }

  /// 열지 못했다. 빈 세션 파일을 치우고 상태를 failed로 둔다.
  void _failOpen(_SessionRun run, String message) {
    run.closing = true;
    if (!run.exited) run.job?.cancel();
    if (!run.live.isCompleted) run.live.complete(false);
    _stopTimers();
    if (identical(run, _current)) _current = null;
    _error = message;
    _completeCheck(null);
    unawaited(_discardAfterExit(run));
    _setState(ArmedSessionState.failed);
    if (run.reopened) onLost(message, openTake: null);
  }

  /// 돌던 세션이 죽었다(종료·멈춤). 열린 조각은 「끝 없는 대기 조각」으로 옮겨
  /// 세션 파일이 지워지지 않게 하고, 마크를 화면에 넘겨 끊긴 데까지 살리게 한다.
  void _loseSession(_SessionRun run, String message) {
    final open = _openTake;
    _openTake = null;
    if (open != null) {
      _takeAnchor.freeze();
      final owner = _runs[open.sessionId];
      owner?.pending.add(
        _PendingTake(
          start: open,
          anchorMs: _takeAnchor.anchorMs,
          peakDbfs: _takePeak,
        ),
      );
    }
    run.closing = true;
    if (!run.exited) run.job?.cancel();
    _stopTimers();
    if (identical(run, _current)) _current = null;
    _error = message;
    _completeCheck(_checkDone ? _inputPeak : _checkPeak);
    _scheduleSidecar(run);
    _setState(ArmedSessionState.failed);
    onLost(message, openTake: open);
  }

  /// 멈춤 감시를 켠다.
  void _startWatchdog() {
    _watchdog?.cancel();
    final interval = watchdogInterval;
    if (interval == null) return;
    _watchdog = Timer.periodic(interval, (_) => unawaited(watchdogTick()));
  }

  /// 감시 한 번. 멈춤 = 레벨 줄 공백 ≥ 600ms **AND** 파일 크기 2틱 연속 정체.
  /// 줄이 잘 오는 동안에는 파일을 열어 보지도 않는다.
  Future<void> watchdogTick() async {
    final run = _current;
    if (_disposed || _ticking || run == null) return;
    if (!run.isLive || run.exited || run.closing) return;
    _heartbeat(run);
    final gapMs = (_nowUs() - _lastRmsUs) ~/ 1000;
    if (gapMs < kStallRmsGapMs) {
      _lastSize = null;
      _stagnantTicks = 0;
      return;
    }
    _ticking = true;
    try {
      final size = await _handleLength(run.pcmPath);
      if (_disposed || run.closing || run.exited) return;
      if (!identical(run, _current)) return;
      if (_lastSize != null && size == _lastSize) {
        _stagnantTicks++;
      } else {
        _stagnantTicks = 0;
      }
      _lastSize = size;
      final stalled = isSessionStalled(
        processExited: false,
        rmsGapMs: gapMs,
        stagnantTicks: _stagnantTicks,
      );
      if (stalled) {
        _loseSession(run, '마이크에서 소리가 더 들어오지 않습니다 — 연결을 확인해 주세요.');
      }
    } finally {
      _ticking = false;
    }
  }

  /// 생존 표시 — 조각이 열려 있는 동안만, [kSidecarHeartbeatMs]에 한 번 사이드카를 다시 쓴다.
  ///
  /// 앱이 죽어도 고아 ffmpeg는 상한까지 계속 쓴다. 복구가 열린 조각의 끝을 「파일
  /// 길이」로 닫으면 최대 45분짜리 조각이 나오므로, 마지막 생존 시각으로 묶는다.
  /// 🔴 파일 IO뿐이다 — 화면은 깨우지 않는다(대기 중 주기 재빌드 금지 규칙).
  void _heartbeat(_SessionRun run) {
    if (_openTake?.sessionId != run.id) return;
    if (_nowUs() - run.lastSidecarUs < kSidecarHeartbeatMs * 1000) return;
    _scheduleSidecar(run);
  }

  /// 타이머를 모두 끈다.
  void _stopTimers() {
    _watchdog?.cancel();
    _watchdog = null;
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  /// 사이드카 쓰기를 세션별 직렬 줄에 올린다. 기다리지 않는다.
  void _scheduleSidecar(_SessionRun run) {
    if (_disposed || run.filesDeleted) return;
    run.lastSidecarUs = _nowUs();
    run.sidecarChain = run.sidecarChain.then((_) => _writeSidecarNow(run));
  }

  /// 지금 상태로 사이드카를 쓴다. 실패해도 던지지 않는다 — 녹음을 막을 이유가 아니다.
  Future<void> _writeSidecarNow(_SessionRun run) async {
    if (run.filesDeleted) return;
    try {
      await writeSessionSidecar(File(run.sidecarPath), _sidecarOf(run));
    } catch (e) {
      debugPrint('세션 사이드카 쓰기 실패: $e');
    }
  }

  /// 세션의 미저장 구간을 파일 ms로 옮긴 사이드카.
  SessionSidecar _sidecarOf(_SessionRun run) {
    SessionTakeMark markOf(TakeStartMark start, int? endWallUs) {
      final endUs = endWallUs == null
          ? null
          : run.clock.fileTimeUsAt(endWallUs);
      return SessionTakeMark(
        startFileMs: usToMs(run.clock.fileTimeUsAt(start.wallUs) ?? 0),
        endFileMs: endUs == null ? null : usToMs(endUs),
        songPosAtStartMs: start.songPositionMs,
        markedAtMs: start.markedAtMs,
        playbackAlreadyRunning: start.playbackAlreadyRunning,
        latencyCompensationMs: start.latencyCompensationMs,
        context: start.context,
      );
    }

    final open = _openTake;
    SessionTakeMark? openMark;
    if (open != null && open.sessionId == run.id) openMark = markOf(open, null);
    final closed = <SessionTakeMark>[];
    for (final take in run.pending) {
      final end = take.end;
      if (end == null) {
        // 끝을 못 찍은 조각 — 복구 때 파일 끝까지 살린다.
        openMark ??= markOf(take.start, null);
      } else {
        closed.add(markOf(take.start, end.wallUs));
      }
    }
    // 쓰는 지금이 곧 「마지막으로 살아 있던 순간」이다(시계가 잠기기 전이면 null).
    final aliveUs = run.clock.fileTimeUsAt(_nowUs());
    return SessionSidecar(
      sessionId: run.id,
      deviceName: run.deviceName,
      gain: run.gain,
      startedAtIso: run.startedAtIso,
      openTake: openMark,
      pending: closed,
      aliveFileMs: aliveUs == null ? null : usToMs(aliveUs),
    );
  }

  /// 프로세스가 끝난 뒤에 세션 파일을 치운다(열지 못한 세션용).
  Future<void> _discardAfterExit(_SessionRun run) async {
    await run.exit.future.timeout(kSessionQuitCap, onTimeout: () {});
    await run.cancelSub();
    await _discardRun(run);
  }

  /// 세션 파일과 사이드카를 지우고 목록에서 뺀다.
  Future<void> _discardRun(_SessionRun run) async {
    await run.sidecarChain;
    run.filesDeleted = true;
    _runs.remove(run.id);
    await deleteSessionFile(File(run.pcmPath));
    await deleteSessionFile(File(run.sidecarPath));
    await deleteSessionFile(File('${run.sidecarPath}.tmp'));
    // 잠금은 맨 끝에 놓는다 — 지우는 도중에 다른 인스턴스의 복구가 끼어들지 않게.
    await run.releaseLock();
    await deleteSessionFile(File(run.lockPath));
  }

  /// 앱이 남기고 죽은 세션을 되살린다(설계 3.6). 지금 열려 있는 세션은 건드리지 않는다.
  ///
  /// [onSlice]는 조각 하나를 쓴 직후에 불린다 — 목록에 등록하고 성공 여부를 돌려준다.
  /// 거짓이면 그 구간은 사이드카에 남아 다음 부팅에 다시 시도된다.
  Future<List<RecoveredSlice>> recoverStale({
    required Future<String> Function(String fileName) pathBuilder,
    String Function(String sessionId, int index)? fileNameFor,
    Future<bool> Function(RecoveredSlice slice)? onSlice,
  }) async {
    try {
      return await recoverStaleCaptureSessions(
        dir: await _sessionDirBuilder(),
        pathBuilder: pathBuilder,
        skipSessionIds: _runs.keys.toSet(),
        fileNameFor: fileNameFor,
        onSlice: onSlice,
      );
    } catch (e) {
      debugPrint('세션 복구 실패: $e');
      return const [];
    }
  }

  /// 떠 있는 세션 프로세스를 **지금** 핸들로 끊는다(동기). 기다리지 않는다.
  void killAll() {
    for (final run in _runs.values) {
      run.closing = true;
      if (!run.live.isCompleted) run.live.complete(false);
      unawaited(run.cancelSub());
      if (!run.exited) run.job?.cancel();
      // 기다릴 수 없는 길이다 — 잠금 핸들은 그 자리에서 닫는다. 남은 세션 파일은
      // 다음 부팅의 복구가 「소유 앱 없음」으로 보고 살리거나 치운다.
      run.dropLockSync();
    }
  }

  /// 폐기 — 동기라 기다릴 수 없다. 프로세스는 핸들로 끊고, 남은 파일은 다음 부팅의
  /// 복구가 사이드카를 보고 살리거나 치운다.
  void dispose() {
    _disposed = true;
    _stopTimers();
    final check = _check;
    if (check != null && !check.isCompleted) check.complete(null);
    killAll();
  }
}

/// 사이드카를 원자적으로 쓴다 — `.tmp`에 쓰고 이름을 바꾼다. 쓰다 죽어도 반쪽짜리
/// JSON이 정본 자리에 남지 않는다.
Future<void> writeSessionSidecar(File target, SessionSidecar sidecar) async {
  final tmp = File('${target.path}.tmp');
  await tmp.writeAsString(sidecar.encode(), flush: true);
  await tmp.rename(target.path);
}

/// 세션 파일 하나를 지운다. 없으면 넘어가고, 막 끝난 프로세스가 핸들을 아직 쥐고
/// 있을 수 있어 **조건 루프**로 잠깐 다시 해 본다. 지웠으면 true.
Future<bool> deleteSessionFile(File file) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    try {
      if (!await file.exists()) return true;
      await file.delete();
      return true;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  debugPrint('세션 파일을 지우지 못했습니다 — ${file.path}');
  return false;
}

/// 폴더와 파일 이름을 잇는다.
String _join(String dir, String name) => '$dir${Platform.pathSeparator}$name';

/// 경로의 마지막 마디(파일 이름).
String _baseName(String path) {
  final cut = math.max(path.lastIndexOf('/'), path.lastIndexOf(r'\'));
  return cut < 0 ? path : path.substring(cut + 1);
}

/// 열린 핸들로 파일 길이를 잰다. 못 열면 -1.
///
/// 경로로 묻지 않는 이유: Windows는 다른 프로세스가 쓰는 중인 파일의 디렉터리
/// 항목 크기를 늦게 갱신한다.
Future<int> _handleLength(String path) async {
  RandomAccessFile? file;
  try {
    file = await File(path).open();
    return await file.length();
  } on FileSystemException {
    return -1;
  } finally {
    try {
      await file?.close();
    } on FileSystemException {
      // 닫기 실패는 결과를 바꾸지 않는다.
    }
  }
}

/// 파일이 [age]보다 오래됐는가.
Future<bool> _olderThan(File file, Duration age, DateTime now) async {
  final modified = await file.lastModified();
  return now.difference(modified) > age;
}

/// 파일이 자라는 것으로 「살아 있는 세션」을 짐작한다 — **소유 잠금 파일이 없을 때만**
/// 쓰는 폴백이다(잠금을 못 만든 세션). 상한 시간 안에 시작했고 지금도 자라면 그렇다.
///
/// 🔴 잠금이 있으면 이걸 보지 않는다. 앱이 죽어도 고아 ffmpeg는 `-t` 상한까지 계속
/// 쓰기 때문에, 성장만 보면 「내 크래시가 남긴 고아」까지 남의 세션으로 읽혀 복구가
/// 통째로 건너뛰어진다(복구는 부팅 때 한 번뿐이다).
Future<bool> _looksLive(
  File pcm,
  SessionSidecar sidecar,
  DateTime now,
  Duration growthProbe,
) async {
  if (growthProbe <= Duration.zero) return false;
  final started = DateTime.tryParse(sidecar.startedAtIso);
  if (started == null) return false;
  if (now.difference(started) >
      const Duration(seconds: kSessionMaxSeconds + 60)) {
    return false;
  }
  final before = await _handleLength(pcm.path);
  await Future<void>.delayed(growthProbe);
  return await _handleLength(pcm.path) > before;
}

/// 세션의 소유 잠금을 쥐어 본다. 쥐었으면 그 핸들을 준다 — **소유 앱이 죽었다.**
/// 다른 인스턴스가 쥐고 있으면(또는 열 수조차 없으면) null — 손대지 않는다.
Future<RandomAccessFile?> _tryOwnSession(File lock) async {
  RandomAccessFile? file;
  try {
    file = await lock.open(mode: FileMode.append);
    await file.lock(FileLock.exclusive);
    return file;
  } on FileSystemException {
    try {
      await file?.close();
    } on FileSystemException {
      // 닫기 실패는 결과를 바꾸지 않는다.
    }
    return null;
  }
}

/// 세션 폴더에 남은 세션을 정리한다. (파일 IO뿐 — 프로세스와 무관, 테스트 대상)
///
/// - 소유 잠금(`.lock`)을 다른 인스턴스가 쥐고 있으면 그 세션은 건드리지 않는다.
///   잠금이 풀려 있으면 소유 앱이 죽은 것이다 — 고아 ffmpeg가 아직 쓰는 중이어도
///   **곧바로** 복구한다.
/// - 사이드카에 미저장 구간이 있으면 잘라서 돌려주고(열린 조각의 끝 = 파일 길이와
///   마지막 생존 표시+여유 중 앞쪽), 전부 살렸으면 세션을 지운다. 못 살린 구간은
///   사이드카에 남겨 다음에 다시 한다.
/// - [onSlice]를 주면 조각을 쓴 직후에 부른다(목록 등록). 거짓을 돌려준 구간은
///   「못 살린 구간」으로 남는다 — 등록이 디스크에 닿은 뒤에만 세션을 지운다.
/// - 사이드카에 미저장 구간이 없으면 세션을 지운다.
/// - 사이드카가 없거나 깨졌으면 [kStaleSessionAge]가 지난 것만 지운다.
/// - [skipSessionIds](지금 열려 있는 세션)는 건드리지 않는다.
Future<List<RecoveredSlice>> recoverStaleCaptureSessions({
  required Directory dir,
  required Future<String> Function(String fileName) pathBuilder,
  Set<String> skipSessionIds = const {},
  String Function(String sessionId, int index)? fileNameFor,
  Future<bool> Function(RecoveredSlice slice)? onSlice,
  DateTime? now,
  Duration growthProbe = const Duration(milliseconds: 250),
}) async {
  final recovered = <RecoveredSlice>[];
  if (!await dir.exists()) return recovered;
  final clock = now ?? DateTime.now();

  final files = <File>[];
  try {
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) files.add(entity);
    }
  } on FileSystemException catch (e) {
    debugPrint('세션 폴더를 읽지 못했습니다: ${e.message}');
    return recovered;
  }

  final ids = <String>{};
  for (final file in files) {
    final name = _baseName(file.path);
    if (name.endsWith('.pcm')) {
      ids.add(name.substring(0, name.length - 4));
    } else if (name.endsWith('.json')) {
      ids.add(name.substring(0, name.length - 5));
    } else if (name.endsWith('.lock')) {
      // 잠금만 남은 세션도 본다 — 소유 앱이 죽었으면 함께 치운다.
      ids.add(name.substring(0, name.length - 5));
    } else if (name.endsWith('.tmp') || name.endsWith('.part')) {
      // 쓰다 만 찌꺼기 — 열려 있는 세션의 것일 수 있으니 오래된 것만 치운다.
      try {
        if (await _olderThan(file, kStaleSessionAge, clock)) {
          await deleteSessionFile(file);
        }
      } on FileSystemException {
        // 다음 부팅에 다시 본다.
      }
    }
  }

  for (final id in ids) {
    if (skipSessionIds.contains(id)) continue;
    try {
      recovered.addAll(
        await _recoverOneSession(
          id: id,
          pcm: File(_join(dir.path, sessionPcmFileName(id))),
          json: File(_join(dir.path, sessionSidecarFileName(id))),
          lock: File(_join(dir.path, sessionLockFileName(id))),
          pathBuilder: pathBuilder,
          fileNameFor: fileNameFor,
          onSlice: onSlice,
          now: clock,
          growthProbe: growthProbe,
        ),
      );
    } on FileSystemException catch (e) {
      // 세션 하나가 말썽이어도 나머지는 계속 본다.
      debugPrint('세션 $id 복구 실패: ${e.message}');
    }
  }
  return recovered;
}

/// 세션 하나를 복구하거나 치운다 — 먼저 소유 잠금으로 「손대도 되는가」를 가린다.
Future<List<RecoveredSlice>> _recoverOneSession({
  required String id,
  required File pcm,
  required File json,
  required File lock,
  required Future<String> Function(String fileName) pathBuilder,
  required String Function(String sessionId, int index)? fileNameFor,
  required Future<bool> Function(RecoveredSlice slice)? onSlice,
  required DateTime now,
  required Duration growthProbe,
}) async {
  final hasLock = await lock.exists();
  RandomAccessFile? owned;
  if (hasLock) {
    owned = await _tryOwnSession(lock);
    // 다른 인스턴스가 쥐고 있다 — 살아 있는 남의 세션이다.
    if (owned == null) return const [];
  }
  try {
    return await _recoverOwnedSession(
      id: id,
      pcm: pcm,
      json: json,
      pathBuilder: pathBuilder,
      fileNameFor: fileNameFor,
      onSlice: onSlice,
      now: now,
      // 잠금을 쥐었으면 소유 앱이 죽은 게 확실하다 — 성장 여부를 볼 이유가 없다.
      growthProbe: hasLock ? Duration.zero : growthProbe,
    );
  } finally {
    if (owned != null) {
      try {
        await owned.unlock();
      } on FileSystemException {
        // 닫으면 어차피 풀린다.
      }
      try {
        await owned.close();
      } on FileSystemException {
        // 닫기 실패는 결과를 바꾸지 않는다.
      }
    }
    // 세션이 다 치워졌으면 잠금 파일도 치운다(남아 있으면 다음 부팅이 또 쥔다).
    if (hasLock && !await pcm.exists() && !await json.exists()) {
      await deleteSessionFile(lock);
    }
  }
}

/// 손대도 되는 세션 하나를 복구하거나 치운다.
Future<List<RecoveredSlice>> _recoverOwnedSession({
  required String id,
  required File pcm,
  required File json,
  required Future<String> Function(String fileName) pathBuilder,
  required String Function(String sessionId, int index)? fileNameFor,
  required Future<bool> Function(RecoveredSlice slice)? onSlice,
  required DateTime now,
  required Duration growthProbe,
}) async {
  final hasPcm = await pcm.exists();
  final hasJson = await json.exists();
  final sidecar = hasJson
      ? SessionSidecar.tryDecode(await json.readAsString())
      : null;

  if (sidecar == null) {
    // 사이드카가 없거나 깨졌다 — 무엇이 담겼는지 모르니 7일은 둔다.
    if (hasPcm && await _olderThan(pcm, kStaleSessionAge, now)) {
      await deleteSessionFile(pcm);
    }
    if (hasJson && await _olderThan(json, kStaleSessionAge, now)) {
      await deleteSessionFile(json);
    }
    return const [];
  }
  if (!hasPcm) {
    await deleteSessionFile(json);
    return const [];
  }
  if (await _looksLive(pcm, sidecar, now, growthProbe)) return const [];
  if (!sidecar.hasUnsaved) {
    // 고아 ffmpeg가 PCM을 쥐고 있으면(공유 삭제 없이 연다) 못 지운다. 그때 사이드카만
    // 지우면 단서 없는 PCM(최대 259MB)이 7일 남는다 — 사이드카를 남겨 다음에 치운다.
    if (await deleteSessionFile(pcm)) await deleteSessionFile(json);
    return const [];
  }

  final length = await _handleLength(pcm.path);
  if (length < 0) return const [];
  final lengthMs = length ~/ kSessionBytesPerMs;
  // 열린 조각에는 정지 키 소리가 없다 — 끝 60ms가 깎이지 않게 그만큼 더해 닫는다.
  // (생존 표시가 있으면 그쪽이 끝을 묶는다 — spansToRecover 참고.)
  final spans = sidecar.spansToRecover(lengthMs + kStopClickTrimMs);
  final openIndex = sidecar.openTake == null ? -1 : spans.length - 1;

  final out = <RecoveredSlice>[];
  final failed = <SessionTakeMark>[];
  for (var i = 0; i < spans.length; i++) {
    final span = spans[i];
    final plan = computeTakeSlice(
      startFileMs: span.startFileMs,
      endFileMs: span.endFileMs ?? lengthMs,
      songPosAtStartMs: span.songPosAtStartMs,
      playbackAlreadyRunning: span.playbackAlreadyRunning,
      fileLengthMs: lengthMs,
      latencyCompensationMs: span.latencyCompensationMs,
    );
    // 너무 짧은 구간은 살릴 게 없다.
    if (plan == null) continue;
    final fileName = fileNameFor?.call(id, i) ?? 'recovered_${id}_$i.wav';
    final path = await pathBuilder(fileName);
    final result = await writeTakeFromSession(
      sessionPath: pcm.path,
      plan: plan,
      outputPath: path,
      // 계획이 파일 길이 안쪽이다 — 기다릴 이유가 없다.
      waitCap: Duration.zero,
    );
    if (!result.ok) {
      debugPrint('세션 $id 구간 $i 복구 실패: ${result.message}');
      failed.add(span);
      continue;
    }
    final slice = RecoveredSlice(
      sessionId: id,
      path: path,
      fileName: fileName,
      durationMs: result.writtenMs,
      leadInMs: plan.leadInMs,
      songPositionMs: plan.songPositionMs,
      peakDbfs: result.peakDbfs,
      truncated: result.truncated,
      wasOpenTake: i == openIndex,
      recordedAt: recoveredSliceRecordedAt(span, sidecar),
      latencyAppliedMs: span.latencyCompensationMs,
      context: span.context,
    );
    // 등록이 디스크에 닿은 뒤에만 「살렸다」로 친다. 실패하면 구간을 남겨 다음 부팅에
    // 다시 한다 — 방금 쓴 WAV는 지우지 않는다(호출부의 메모리 목록이 가리킬 수 있다.
    // 중복이 조각을 잃는 것보다 낫다).
    if (onSlice != null && !await _registerSlice(onSlice, slice)) {
      failed.add(span);
      continue;
    }
    out.add(slice);
  }

  if (failed.isNotEmpty) {
    // 살린 구간이 다음 부팅에 또 등록되지 않게, 못 살린 것만 남긴다.
    await writeSessionSidecar(
      json,
      sidecar.copyWith(clearOpenTake: true, pending: failed),
    );
  } else if (await deleteSessionFile(pcm)) {
    await deleteSessionFile(json);
  } else {
    // 고아 ffmpeg가 PCM을 쥐고 있어 못 지웠다 — 사이드카를 「복구 끝」으로 남겨,
    // 다음 부팅이 중복 등록 없이 치우게 한다.
    await writeSessionSidecar(
      json,
      sidecar.copyWith(clearOpenTake: true, pending: const []),
    );
  }
  return out;
}

/// 복구 조각의 recordedAt — 마크를 찍은 달력 시각. (순수 함수)
///
/// 사이드카에 `markedAtMs`가 있으면 그것, 없으면(v5.16.0 사이드카) 세션 시작 시각에
/// 마크의 파일 오프셋을 더해 어림한다. 세션 시작 시각도 못 읽으면 null.
DateTime? recoveredSliceRecordedAt(
  SessionTakeMark span,
  SessionSidecar sidecar,
) {
  final marked = span.markedAtMs;
  if (marked != null) return DateTime.fromMillisecondsSinceEpoch(marked);
  final started = DateTime.tryParse(sidecar.startedAtIso);
  if (started == null) return null;
  return started.add(Duration(milliseconds: span.startFileMs));
}

/// 되살린 조각을 호출부에 등록시킨다. 예외도 「등록 실패」로 친다.
Future<bool> _registerSlice(
  Future<bool> Function(RecoveredSlice slice) onSlice,
  RecoveredSlice slice,
) async {
  try {
    return await onSlice(slice);
  } catch (e) {
    debugPrint('복구 조각 등록 실패: $e');
    return false;
  }
}
