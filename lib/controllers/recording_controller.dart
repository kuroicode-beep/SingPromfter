// file: lib/controllers/recording_controller.dart
//
// 마이크 녹음. ffmpeg의 DirectShow 입력으로 캡처한다.
//
// 플러그인(record) 대신 ffmpeg를 쓰는 이유: record_windows가 CMake 3.23+를
// 요구하는데 이 환경의 Visual Studio 번들 CMake가 그보다 낮다. 이미 갖춰 둔
// ffmpeg + ProcessRunner를 재사용하면 툴체인을 건드리지 않고 같은 일을 하며,
// astats 메타데이터로 라이브 입력 레벨까지 얻을 수 있다.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/process/external_tool_locator.dart';
import '../services/process/process_runner.dart';
import '../services/process/tool_progress_parsers.dart';
import 'armed_capture_session.dart';
import 'capture_session.dart';

/// 녹음 중 자동 다음곡 진행 여부. (순수 함수 — 테스트 대상)
///
/// 아웃트로를 부르는 중에 다음 곡으로 넘어가는 게 최악이라
/// **녹음 중에는 자동 진행을 막고** 저장 후 사용자가 직접 넘기게 한다.
bool shouldAutoAdvance({
  required bool isRecording,
  required bool queueHasNext,
}) {
  if (isRecording) return false;
  return queueHasNext;
}

/// 녹음에 소리가 안 들어왔다고 볼 기준(dBFS).
///
/// 진짜 마이크는 조용한 방에서도 -60~-70dB대 노이즈 플로어가 있다.
/// 그보다 낮으면 장치가 **디지털 무음**을 보내고 있다는 뜻이다 —
/// 꺼진 무선 헤드셋, 믹서 루프백, 뽑힌 마이크가 전부 여기 걸린다.
const double kSilentTakeDbfs = -75;

/// 이 테이크에 소리가 없었는가. (순수 함수 — 테스트 대상)
///
/// 2026-09-21에 같은 사고가 두 번 났다. 잘못된 장치를 녹음해 **디지털 무음**이
/// 저장됐는데, 저장까지 정상으로 끝나서 들어 보기 전에는 알 수가 없었다.
/// 조용히 실패하는 게 가장 비싸다 — 그 자리에서 알려야 한다.
bool isSilentTake(double? peakDbfs) {
  if (peakDbfs == null) return true;
  return peakDbfs < kSilentTakeDbfs;
}

/// 저장할 가치가 있는 최소 녹음 길이.
///
/// 실수로 누른 R만 거르는 선이다. 예전 3초 기준은 **한 줄씩 끊어 녹음한
/// 조각(1~2초)을 정상인데도 통째로 삭제**했다(2026-09-21 실사고).
/// 잘못 누른 녹음은 Ctrl+R로 물릴 수 있으니 자동 삭제는 느슨해도 된다.
const Duration kMinimumTakeDuration = Duration(milliseconds: 500);

/// 입력 레벨을 사람이 읽을 수 있는 상태 문구로 바꾼다.
/// 막대만으로는 저시력 사용자가 판단하기 어려워 텍스트를 함께 준다.
String inputLevelLabel(double? dbfs) {
  if (dbfs == null) return '입력 확인 중';
  if (dbfs < -45) return '소리 없음';
  if (dbfs < -30) return '너무 작음';
  if (dbfs > -3) return '너무 큼';
  return '입력 좋음';
}

/// 진폭(dBFS)을 0~1 막대 값으로 바꾼다.
double normalizedLevel(double? dbfs) {
  if (dbfs == null) return 0;
  const floor = -60.0;
  if (dbfs <= floor) return 0;
  if (dbfs >= 0) return 1;
  return (dbfs - floor) / -floor;
}

/// ffmpeg astats 출력에서 RMS 레벨을 뽑는다. (순수 함수)
/// 예: `lavfi.astats.Overall.RMS_level=-21.091524`
double? parseRmsLevel(String line) {
  const key = 'lavfi.astats.Overall.RMS_level=';
  final index = line.indexOf(key);
  if (index < 0) return null;
  final value = line.substring(index + key.length).trim();
  final parsed = double.tryParse(value);
  // 완전 무음이면 ffmpeg가 -inf를 낸다.
  if (parsed == null || parsed.isNaN || parsed.isInfinite) return -100;
  return parsed;
}

/// ffmpeg 출력 줄이 즉사 원인(장치 열기 실패 등)을 담고 있으면 그 문구를 돌려준다.
/// 아니면 null. (순수 함수) — 테이크 녹음과 고정 세션이 같은 잣대를 쓴다.
String? ffmpegErrorDetail(String line) {
  final trimmed = line.trim();
  if (trimmed.startsWith('Error') || trimmed.contains('Could not')) {
    return trimmed;
  }
  return null;
}

/// `ffmpeg -list_devices` 출력에서 오디오 장치 이름을 뽑는다. (순수 함수)
List<String> parseDshowAudioDevices(String output) {
  final devices = <String>[];
  final pattern = RegExp(r'"([^"]+)"\s*\(audio\)');
  for (final line in output.split(RegExp(r'\r?\n'))) {
    final match = pattern.firstMatch(line);
    if (match != null) devices.add(match.group(1)!);
  }
  return devices;
}

/// ffmpeg의 입력 스트림 줄에서 (입력 번호, 시작 타임스탬프 초)를 뽑는다.
/// 예: `  Stream #1:0: Audio: pcm_s16le, 44100 Hz, stereo, ..., start 148439.518000`
///
/// 2채널 녹음의 **정렬**에 쓴다 — ffmpeg는 dshow 장치를 차례로 열기 때문에
/// 두 번째 장치가 수백 ms 늦게 캡처를 시작하는데, 출력 파일은 각자 0으로
/// 정규화돼 그 지연이 통째로 어긋남이 된다(실측: 버퍼 기본값에서 790ms).
/// 출력 줄에는 `start`가 없어 이 정규식에 걸리지 않는다. (순수 함수)
({int input, double startSeconds})? parseInputStreamStart(String line) {
  final match = RegExp(
    r'Stream #(\d+):\d+.*[, ]start ([0-9]+\.?[0-9]*)',
  ).firstMatch(line);
  if (match == null) return null;
  final input = int.tryParse(match.group(1)!);
  final start = double.tryParse(match.group(2)!);
  if (input == null || start == null) return null;
  return (input: input, startSeconds: start);
}

/// 보고된 시작 시각 차이에서 빼는 잔차(ms).
///
/// 실측(2026-09-21, RØDE NT-USB Mini 2회 동시 개방, 버퍼 20/50/200/500ms):
/// 보고 차이 340/369/523/815ms에 대해 실제 상관 지연이 310/340/490/790ms로,
/// 잔차가 버퍼 크기와 무관하게 25~33ms로 일정했다(리샘플러·버퍼 단위 지연).
/// 빼 주면 오차가 ±4ms로 떨어진다.
const int kDualCaptureStartResidualMs = 29;

/// 두 입력의 시작 타임스탬프 차이에서 실제 어긋남(ms)을 구한다. (순수 함수)
/// 음수는 0으로 눕힌다 — 반주가 보컬보다 먼저 열리는 일은 없다.
int dualCaptureSkewMs({
  required double vocalStartSeconds,
  required double backingStartSeconds,
}) {
  final raw = ((backingStartSeconds - vocalStartSeconds) * 1000).round();
  final corrected = raw - kDualCaptureStartResidualMs;
  return corrected < 0 ? 0 : corrected;
}

/// 자동 선택 시 쓸 입력 장치를 고른다. (순수 함수 — 테스트 대상)
///
/// 🔴 「첫 번째 장치」를 그냥 쓰면 안 된다. dshow 열거 순서는 **고정이 아니다** —
/// 2026-09-21에 실제로 순서가 바뀌어 믹서 루프백(FLOW 8 MAIN L/R)이 1번으로
/// 올라왔고, 그걸 녹음한 16초짜리 테이크가 **디지털 무음**으로 남았다.
/// 반주도 목소리도 없이 조용히 실패해서, 들어 보기 전에는 알 수가 없었다.
///
/// 그래서 이름으로 **실제 마이크를 먼저** 고른다. 믹서·루프백·스테레오 믹스는
/// 사용자가 직접 고르지 않는 한 자동 선택 대상이 아니다.
String? preferredInputDevice(List<String> devices) {
  if (devices.isEmpty) return null;
  bool looksLikeMic(String d) {
    final lower = d.toLowerCase();
    return d.contains('마이크') ||
        lower.contains('microphone') ||
        lower.startsWith('mic');
  }

  bool looksLikeLoopback(String d) {
    final lower = d.toLowerCase();
    return lower.contains('stereo mix') ||
        d.contains('스테레오 믹스') ||
        lower.contains('loopback') ||
        lower.contains('what u hear') ||
        // 믹서의 메인 아웃 — 이게 1번으로 올라오는 게 이번 사고의 원인이었다.
        lower.contains('main l/r');
  }

  for (final d in devices) {
    if (looksLikeMic(d) && !looksLikeLoopback(d)) return d;
  }
  for (final d in devices) {
    if (!looksLikeLoopback(d)) return d;
  }
  return devices.first;
}

/// 캡처 오디오 필터 체인. 게인은 astats **앞**에 두어 미터가 게인 반영
/// 값을 보여준다(클리핑을 실시간으로 경고할 수 있게). (순수 함수)
///
/// 🔴 `direct=1`이 없으면 레벨 줄이 **ffmpeg가 끝날 때** 한꺼번에 나온다.
/// ffmpeg 8.1.1은 `file=-` 출력을 내부 버퍼에 쌓아 두기 때문이다(2026-09-22
/// 실측: 14초 녹음에서 'q' 이전 RMS 줄 0개). 그 탓에 녹음 중 레벨 막대가
/// 멈춰 있었고, 입력 점검이 매번 4초 타임아웃을 다 채워 「녹음 고정 +
/// 스페이스」마다 4.5초 공백이 생겼다 — 「시작 시점을 못 잡겠다」의 원인.
///
/// 공개인 이유: 상시 캡처 세션(capture_session.dart)도 **같은 문자열**을 써야
/// 한다. 복사해 두면 위 옵션이 한쪽에서만 빠지는 사고가 다시 난다.
String captureFilterChain(double gain) {
  final volume = gain == 1.0 ? '' : 'volume=${gain.toStringAsFixed(2)},';
  return '${volume}astats=metadata=1:reset=1,'
      'ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-:direct=1';
}

/// dshow 오디오 버퍼(ms).
///
/// 기본값은 500ms라 WAV 길이가 0.5초 단위로 끊기고 **정지 직전 0~0.5초가
/// 잘려 나간다**(끝 음절이 끊기던 원인). 50ms면 프레임이 50ms 간격으로 오고
/// 'q' → 종료도 0.5초 → 0.15초로 준다. 2채널 시작 잔차(29ms)는 버퍼 크기와
/// 무관함을 실측해 두었다([kDualCaptureStartResidualMs]).
const int kDshowAudioBufferMs = 50;

/// ametadata가 프레임마다 내는 머리줄에서 프레임 시작 시각(ms)을 읽는다.
/// 입력 예: `frame:3    pts:3072    pts_time:0.0696599` (순수 함수)
int? parseAmetadataFramePtsMs(String line) {
  final match = RegExp(
    r'^frame:[0-9]+ +pts:-?[0-9]+ +pts_time:(-?[0-9.]+)',
  ).firstMatch(line.trim());
  if (match == null) return null;
  final seconds = double.tryParse(match.group(1)!);
  if (seconds == null) return null;
  return (seconds * 1000).round();
}

/// 조각 파일의 t=0이 **곡의 어디였는지**를 재는 추정기. (프로세스와 무관 — 테스트 대상)
///
/// 장치를 여는 데 0.45초쯤 걸려서 「녹음을 건 순간의 재생 위치」는 파일
/// t=0보다 그만큼 이르다. 그래서 프레임 줄이 도착할 때마다 그 순간의 재생
/// 위치를 찍어 두고, 다음 줄의 pts(= 앞 프레임의 끝 = 그때까지 파일에 담긴
/// 길이)를 빼서 t=0의 곡 좌표를 역산한다.
///
/// 줄의 도착은 늦어질 수만 있으므로(파이프·이벤트 루프) 값은 클 수만 있다 —
/// 최소값이 참값에 가장 가깝다.
class CaptureAnchorEstimator {
  CaptureAnchorEstimator({this.maxSamples = 12});

  /// 시작 직후 0.6초만 쓴다 — 오래 모을수록 정지 순간의 어긋난 표본이 섞인다.
  final int maxSamples;

  int? _prevPositionMs;
  int? _bestMs;
  int _samples = 0;
  bool _frozen = false;

  /// 역산한 t=0의 곡 좌표(ms). 표본이 없으면 null.
  int? get anchorMs => _bestMs;
  int get samples => _samples;

  /// 프레임 줄 하나. [positionMs]는 **도착 순간**의 재생 위치, 재생 중이
  /// 아니면 null(그 표본과 다음 표본은 버린다 — 위치가 흐르지 않으면 식이 안 선다).
  void addFrame({required int ptsMs, required int? positionMs}) {
    if (_frozen || _samples >= maxSamples) return;
    final prev = _prevPositionMs;
    if (prev != null && positionMs != null && ptsMs > 0) {
      final candidate = prev - ptsMs;
      if (_bestMs == null || candidate < _bestMs!) _bestMs = candidate;
      _samples++;
    }
    _prevPositionMs = positionMs;
  }

  /// 재생을 멈추기 **직전에** 부른다. 멈춘 뒤에도 프레임은 계속 오는데 위치는
  /// 서 있어서, 그대로 두면 최소값 필터가 그 틀린 표본을 골라 버린다.
  void freeze() => _frozen = true;
}

/// ffmpeg dshow 녹음 인자를 만든다. (순수 함수 — 프로세스를 띄우지 않는다)
///
/// [backingDeviceName]·[backingOutputPath]를 함께 주면 **독립 2채널 녹음**이
/// 된다 — 한 프로세스가 마이크와 PC 재생음을 각각 받아 **서로 다른 파일**로
/// 쓴다. 보컬에 반주가 섞이지 않아 AI 보컬 분리 단계가 필요 없어진다.
///
/// 🔴 두 파일의 시작점은 **같지 않다.** ffmpeg가 dshow 장치를 차례로 열어
/// 두 번째 장치가 수백 ms 늦게 캡처를 시작하는데 출력은 각자 0으로 정규화된다.
/// 그 어긋남은 [parseInputStreamStart]·[dualCaptureSkewMs]로 재서 저장 직후
/// 반주 앞에 무음을 덧대 맞춘다.
///
/// 게인·레벨 미터는 보컬 채널에만 건다(반주는 들어온 그대로 받아야 한다).
List<String> buildRecordArgs({
  required String deviceName,
  required String outputPath,
  double gain = 1.0,
  String? backingDeviceName,
  String? backingOutputPath,
}) {
  final dual =
      (backingDeviceName ?? '').isNotEmpty &&
      (backingOutputPath ?? '').isNotEmpty;
  return [
    '-hide_banner',
    '-f', 'dshow',
    '-audio_buffer_size', '$kDshowAudioBufferMs',
    '-i', 'audio=$deviceName',
    if (dual) ...[
      '-f', 'dshow',
      '-audio_buffer_size', '$kDshowAudioBufferMs',
      '-i', 'audio=$backingDeviceName',
    ],
    '-ac', '1',
    '-ar', '48000',
    // 파일을 쓰면서 동시에 입력 레벨을 표준출력으로 흘린다.
    '-af', captureFilterChain(gain),
    '-progress', 'pipe:1',
    '-nostats',
    '-y',
    // 입력이 둘이면 어느 입력을 쓸지 명시해야 한다(자동 선택에 맡기지 않는다).
    if (dual) ...['-map', '0:a'],
    outputPath,
    // 반주(PC 재생) 채널 — 스테레오 그대로.
    if (dual) ...['-map', '1:a', '-ac', '2', '-ar', '48000', backingOutputPath!],
  ];
}

/// 마이크 테스트(레벨 프로브) 인자 — 파일 대신 null 출력으로 레벨만 흘린다.
/// (순수 함수 — 테스트 대상)
List<String> buildLevelProbeArgs({
  required String deviceName,
  double gain = 1.0,
}) {
  return [
    '-hide_banner',
    '-f', 'dshow',
    '-audio_buffer_size', '$kDshowAudioBufferMs',
    '-i', 'audio=$deviceName',
    '-ac', '1',
    '-ar', '48000',
    '-af', captureFilterChain(gain),
    '-nostats',
    '-f', 'null',
    '-',
  ];
}

class RecordingController extends ChangeNotifier {
  final ProcessRunner _runner;
  final ExternalToolLocator _locator;

  /// 녹음 파일을 둘 전체 경로를 만들어 준다.
  final Future<String> Function(String fileName) pathBuilder;

  /// **지금 이 순간**의 재생 위치(ms)를 돌려준다. 재생 중이 아니면 null.
  ///
  /// dshow 장치를 여는 데 0.45초쯤 걸려서, 녹음을 기다렸다 재생하면 스페이스와
  /// 음악 사이에 공백이 생겨 첫 박을 잡을 수 없다. 그래서 재생을 먼저 걸고,
  /// 조각의 곡 좌표는 프레임 줄이 올 때마다 이 값을 찍어 역산한다
  /// ([CaptureAnchorEstimator]).
  ///
  /// 🔴 예전에는 「첫 RMS 줄이 온 순간」을 기준점으로 삼았는데, `direct=1`이
  /// 없던 탓에 그 줄이 **정지할 때** 와서 좌표가 조각의 끝 위치로 저장됐다.
  int? Function()? songPositionProbe;

  CaptureAnchorEstimator _anchor = CaptureAnchorEstimator();

  /// 재생을 멈추기 직전에 부른다 — [CaptureAnchorEstimator.freeze] 참고.
  void freezeSongAnchor() => _anchor.freeze();

  // 프레임 줄로 잰 파일 길이(ms). -progress는 0.5초 간격이라 짧은 조각의
  // 길이가 0.5초 단위로 뭉개진다 — 프레임 줄은 50ms 간격이다.
  int? _lastFramePtsMs;
  int _framedLengthMs = 0;

  /// 캡처가 stop() 전에 스스로 죽었을 때(장치 열기 실패 등) 호출된다 —
  /// 화면이 스낵으로 원인을 알리는 데 쓴다. 없으면 상태만 되돌린다.
  void Function(String message)? onError;

  JobHandle? _job;
  StreamSubscription<String>? _sub;

  // 마이크 테스트(레벨 프로브) — 녹음과 별개 프로세스로 레벨만 흘린다.
  JobHandle? _probeJob;
  StreamSubscription<String>? _probeSub;
  bool _isProbing = false;

  // 반주(PC 재생) 채널 테스트 — 마이크와 **다른 장치**라 별도 프로세스로 돈다.
  // 한 프로세스로 둘을 받으면 astats 메타데이터 키가 같아 어느 입력의
  // 레벨인지 가릴 수가 없다.
  JobHandle? _backingProbeJob;
  StreamSubscription<String>? _backingProbeSub;
  bool _isBackingProbing = false;
  double? _backingDbfs;

  /// 프로브 동안 관측한 최대 레벨. 녹음 전 입력 점검에 쓴다.
  double? _probePeakDbfs;

  DateTime _lastLevelNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// 레벨 갱신 알림 — 초당 8번 정도로 묶는다.
  ///
  /// astats는 프레임마다(초당 수십 번) 레벨을 흘린다. 그때마다 화면 전체가
  /// 다시 그려지면 접근성 트리도 그만큼 갱신돼, 키 입력 순간의 MSAA 질의와
  /// 부딪혀 엔진이 죽을 확률을 키운다(2026-09-22 크래시). 미터는 8Hz면 충분하다.
  /// 최대 레벨(_peakDbfs) 추적은 알림과 무관하게 매 줄 한다.
  void _notifyLevel() {
    final now = DateTime.now();
    if (now.difference(_lastLevelNotify) <
        const Duration(milliseconds: 120)) {
      return;
    }
    _lastLevelNotify = now;
    notifyListeners();
  }

  bool _isRecording = false;
  bool _stopping = false;
  Duration _elapsed = Duration.zero;
  double? _dbfs;

  /// 이번 녹음에서 관측한 가장 큰 입력 레벨. 무음 판정에 쓴다.
  double? _peakDbfs;
  String? _currentFileName;
  String? _currentBackingFileName;
  final Map<int, double> _inputStarts = {};
  String? _deviceName;
  String? _backingDeviceName;
  List<String> _devices = const [];

  /// [nowUs]는 고정 세션이 줄 도착과 마크를 찍는 단조 시계(µs, 기본 Stopwatch),
  /// [sessionDirBuilder]는 세션 파일을 둘 폴더다(기본 앱 지원 폴더/capture_sessions).
  /// 둘 다 테스트가 시간을 고정하고 임시 폴더를 쓰려고 주입한다.
  RecordingController({
    required this.pathBuilder,
    ProcessRunner runner = const SystemProcessRunner(),
    ExternalToolLocator? locator,
    int Function()? nowUs,
    Future<Directory> Function()? sessionDirBuilder,
    Duration? sessionWatchdogInterval = kSessionWatchdogInterval,
    Duration sessionLiveTimeout = kSessionLiveTimeout,
  }) : _runner = runner,
       _locator = locator ?? ExternalToolLocator(runner: runner) {
    _armed = ArmedCaptureSession(
      runner: runner,
      nowUs: nowUs,
      sessionDirBuilder: sessionDirBuilder,
      watchdogInterval: sessionWatchdogInterval,
      liveTimeout: sessionLiveTimeout,
      onChanged: notifyListeners,
      // 조각이 열려 있는 동안의 레벨 갱신은 테이크 녹음과 같은 120ms 묶음을 탄다.
      onLevel: _notifyLevel,
      onLost: (message, {openTake}) =>
          onSessionLost?.call(message, openTake: openTake),
      positionProbe: () => songPositionProbe?.call(),
    );
  }

  /// 녹음 고정(상시 캡처 세션). 화면은 아래 파사드만 쓴다.
  late final ArmedCaptureSession _armed;

  bool get isRecording => _isRecording;
  bool get isProbing => _isProbing;
  bool get isProbingBacking => _isBackingProbing;
  double? get backingDbfs => _backingDbfs;
  String get backingLevelLabel => inputLevelLabel(_backingDbfs);
  double get backingLevel => normalizedLevel(_backingDbfs);
  Duration get elapsed => _elapsed;
  /// 고정 세션이 열려 있으면 세션의 레벨을 준다(고정 대기 중에는 바뀌어도 알리지 않는다).
  double? get dbfs => _armed.isOpen ? _armed.dbfs : _dbfs;
  String get levelLabel => inputLevelLabel(dbfs);
  double get level => normalizedLevel(dbfs);
  List<String> get devices => List.unmodifiable(_devices);
  String? get deviceName => _deviceName;

  set deviceName(String? value) {
    _deviceName = value;
    notifyListeners();
  }

  /// 2채널 녹음의 반주(PC 재생) 입력 장치. null·빈 값이면 1채널로 녹음한다.
  String? get backingDeviceName => _backingDeviceName;

  set backingDeviceName(String? value) {
    _backingDeviceName = (value ?? '').isEmpty ? null : value;
    notifyListeners();
  }

  /// 이번 녹음이 2채널로 돌고 있는지.
  bool get isDualChannel => (_currentBackingFileName ?? '').isNotEmpty;

  /// 반주 장치가 목록에 실제로 있는지. 없으면 2채널을 시도하지 않는다 —
  /// ffmpeg는 입력 하나만 못 열어도 **프로세스째** 죽어서 보컬까지 잃는다.
  bool get canRecordDual {
    final backing = _backingDeviceName;
    if (backing == null || backing.isEmpty) return false;
    if (_devices.isEmpty) return false;
    if (!_devices.contains(backing)) return false;
    // 같은 장치를 두 번 열 수는 없다.
    return backing != (_deviceName ?? preferredInputDevice(_devices));
  }

  /// 입력 장치 목록을 새로 읽는다.
  ///
  /// run()이 아니라 start() 스트리밍으로 읽는 이유: Process.run의 기본
  /// 디코딩은 시스템 코드페이지(이 PC는 cp949)인데 ffmpeg는 UTF-8을
  /// 내보낸다. 한글 장치명("마이크(RØDE...)")이 깨진 채 저장됐다가 녹음
  /// 시작에서 장치를 못 찾아 캡처가 즉사하던 실사고(2026-08-16)가 있었다.
  /// start()의 스트림은 UTF-8(toolOutputDecoder)로 디코딩한다.
  Future<List<String>> refreshDevices() async {
    final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);
    if (!ffmpeg.found) return const [];

    // 장치 목록은 stderr로 나오고 종료 코드도 0이 아니다(정상 동작).
    final job = _runner.start(ffmpeg.path!, [
      '-hide_banner',
      '-list_devices', 'true',
      '-f', 'dshow',
      '-i', 'dummy',
    ]);
    final lines = <String>[];
    final sub = job.lines.listen(lines.add);
    await job.exitCode;
    await sub.cancel();
    _devices = parseDshowAudioDevices(lines.join('\n'));
    _deviceName ??= preferredInputDevice(_devices);
    notifyListeners();
    return _devices;
  }

  Future<bool> isAvailable() async {
    final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);
    if (!ffmpeg.found) return false;
    if (_devices.isEmpty) await refreshDevices();
    return _devices.isNotEmpty;
  }

  /// 이번에 열 입력 장치를 정한다. 없으면 null.
  /// 저장된 장치가 뽑혔을 수 있으니 목록에 없으면 자동 선택으로 폴백한다.
  Future<String?> _resolveInputDevice() async {
    if (_devices.isEmpty) await refreshDevices();
    var device = _deviceName ?? preferredInputDevice(_devices);
    if (device != null && _devices.isNotEmpty && !_devices.contains(device)) {
      device = preferredInputDevice(_devices);
    }
    return device;
  }

  // ── 녹음 고정(상시 캡처 세션) ──────────────────────────────────────────
  //
  // 테이크마다 ffmpeg를 띄우면 장치를 여는 0.44~0.53초 동안 마이크가 닫혀 있어
  // 스페이스 직후의 첫 음절을 구할 수 없다. 고정을 켜는 순간 세션 하나를 열어
  // 계속 받아 두고, 스페이스는 마크만 찍는다(armed_capture_session.dart).

  /// 세션이 죽었을 때(종료·멈춤·상한에서 조각이 끊김) 불린다. 열려 있던 조각이
  /// 있으면 [openTake]로 온다 — `sliceTake(openTake, null, …)`로 끊긴 데까지 살린다.
  void Function(String message, {TakeStartMark? openTake})? onSessionLost;

  Future<bool>? _sessionOpening;

  /// 고정 세션의 상태(off·opening·live·failed).
  ArmedSessionState get sessionState => _armed.state;

  /// 세션 프로세스가 떠 있는가(여는 중 포함).
  bool get isSessionOpen => _armed.isOpen;

  /// 마크를 받아도 되는가 — live + 시계 잠금 + 입력 점검 끝 + 무음 아님.
  bool get isSessionReady => _armed.isReady;

  /// 시작 마크를 찍고 끝 마크를 아직 안 찍었는가. 스페이스 분기의 기준이다 —
  /// 이벤트로 늦게 서는 `playing`이 아니라 마크와 **같은 순간** 뒤집히는 값을 본다.
  bool get isTakeOpen => _armed.isTakeOpen;

  /// 최근 2초의 입력 상태(좋음·작음·없음). 고정 대기 중에는 이게 바뀔 때만 알린다.
  InputLevelBucket get sessionLevelBucket => _armed.levelBucket;

  /// 조작판 고정 글자에 넣을 문구(설계 3.7). 고정이 꺼져 있으면 빈 문자열.
  String get sessionStatusLabel => _armed.statusLabel;

  /// 마지막 세션 실패 원인. 없으면 null.
  String? get sessionError => _armed.error;

  /// 입력 점검에서 본 최대 레벨(dBFS). 점검이 안 끝났으면 null.
  double? get sessionInputPeakDbfs => _armed.inputPeakDbfs;

  /// 입력 점검이 끝났는가(결과가 무음이어도 참).
  bool get isSessionInputChecked => _armed.isInputChecked;

  /// 입력 점검 결과를 기다린다(openSession 뒤 약 0.9초). [isSilentTake]로 판정한다.
  Future<double?> get sessionInputCheck => _armed.inputCheck;

  /// 열린 조각의 길이. 없으면 0.
  Duration get sessionTakeElapsed => _armed.takeElapsed;

  /// 아직 저장하지 않은 마크가 있는가(열린 조각 포함).
  bool get hasUnslicedSessionMarks => _armed.hasUnslicedMarks;

  @visibleForTesting
  String? get debugSessionPcmPath => _armed.currentPcmPath;

  @visibleForTesting
  CaptureClock? get debugSessionClock => _armed.currentClock;

  /// 멈춤 감시를 한 번 돌린다(테스트가 타이머 없이 부른다).
  @visibleForTesting
  Future<void> debugSessionWatchdogTick() => _armed.watchdogTick();

  /// 고정 세션을 연다. live가 되면 true(3초 상한). 입력 점검은 이어서 돈다 —
  /// 결과는 [sessionInputCheck]로 기다린다. 이미 여는 중이면 그 결과를 함께 기다린다.
  Future<bool> openSession({double gain = 1.0}) {
    return _sessionOpening ??= _openSession(gain).whenComplete(
      () => _sessionOpening = null,
    );
  }

  /// [openSession]의 본체 — ffmpeg와 장치를 찾아 세션에 넘긴다.
  Future<bool> _openSession(double gain) async {
    if (_isRecording) {
      debugPrint('고정 세션 거절 — 테이크 녹음이 돌고 있다.');
      return false;
    }
    if (_armed.isOpen) return _armed.waitLive();
    // 찾는 동안에도 화면이 「여는 중」을 보여 주게 먼저 알린다.
    final generation = _armed.markOpening();
    try {
      // 프로브가 돌고 있으면 장치를 놓아준다(같은 장치는 동시에 못 연다).
      await stopLevelProbe();
      final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);
      if (!ffmpeg.found) {
        _armed.failBeforeOpen(
          'ffmpeg를 찾지 못했습니다.',
          generation: generation,
        );
        return false;
      }
      final device = await _resolveInputDevice();
      if (device == null) {
        _armed.failBeforeOpen(
          '녹음 입력 장치를 찾지 못했습니다.',
          generation: generation,
        );
        return false;
      }
      return await _armed.open(
        ffmpegPath: ffmpeg.path!,
        deviceName: device,
        gain: gain,
        generation: generation,
      );
    } catch (e) {
      debugPrint('고정 세션 열기 실패: $e');
      _armed.failBeforeOpen(
        '녹음 고정을 시작하지 못했습니다 — $e',
        generation: generation,
      );
      return false;
    }
  }

  /// 조각 시작을 찍는다. **동기** — 같은 스택에서 곧바로 재생을 걸 수 있다.
  /// [isSessionReady]가 아니거나 이미 조각이 열려 있으면 null.
  TakeStartMark? markTakeStart({
    required int songPositionMs,
    bool playbackAlreadyRunning = false,
    Map<String, Object?> context = const {},
  }) => _armed.markTakeStart(
    songPositionMs: songPositionMs,
    playbackAlreadyRunning: playbackAlreadyRunning,
    context: context,
  );

  /// 조각 끝을 찍는다. **동기.** 열린 조각이 없으면 null.
  TakeEndMark? markTakeEnd() => _armed.markTakeEnd();

  /// 열린 조각을 없던 일로 한다(재생이 막혔을 때).
  void cancelOpenTake() => _armed.cancelOpenTake();

  /// 마크 한 쌍을 세션 파일에서 잘라 [outputPath]에 WAV로 저장한다.
  /// null = 너무 짧아 저장하지 않음, `ok == false` = 저장 실패(세션 파일은 남는다).
  /// [end]가 null이면 세션이 죽어 끝을 못 찍은 조각 — 파일 끝까지 살린다.
  ///
  /// 🔴 성공해도 마크는 세션의 저장 대기열에 남는다. 조각을 녹음 목록에 **등록한
  /// 뒤** [confirmTakeSaved]를 불러야 빠진다 — 그 전에 앱이 끝나면 다음 부팅의 복구가
  /// 되살린다.
  Future<SlicedTake?> sliceTake(
    TakeStartMark start,
    TakeEndMark? end, {
    required String outputPath,
  }) => _armed.sliceTake(start, end, outputPath: outputPath);

  /// [sliceTake]로 자른 조각이 녹음 목록에 등록됐다 — 대기열에서 빼고 세션 정리를 잇는다.
  Future<void> confirmTakeSaved(TakeStartMark start) =>
      _armed.confirmTakeSaved(start);

  /// 고정 세션을 닫는다('q' → 2초 → 핸들로 끊기). 저장하지 않은 마크가 있는 세션
  /// 파일은 지우지 않는다 — 저장이 끝나는 대로 지운다.
  Future<void> closeSession({bool deleteFiles = true}) =>
      _armed.close(deleteFiles: deleteFiles);

  /// 앱이 남기고 죽은 세션을 되살린다. 조각은 [pathBuilder]가 주는 자리에 쓴다.
  /// 지금 열려 있는 세션은 건드리지 않는다.
  ///
  /// [onSlice]는 조각을 쓴 직후에 불린다 — 목록에 등록하고 성공 여부를 돌려준다.
  /// 거짓이면 그 구간은 세션에 남아 다음 부팅에 다시 시도된다(등록이 디스크에 닿기
  /// 전에 세션을 지우면, 그사이 앱이 끝났을 때 조각이 어디에도 없다).
  Future<List<RecoveredSlice>> recoverStaleSessions({
    String Function(String sessionId, int index)? fileNameFor,
    Future<bool> Function(RecoveredSlice slice)? onSlice,
  }) => _armed.recoverStale(
    pathBuilder: pathBuilder,
    fileNameFor: fileNameFor,
    onSlice: onSlice,
  );

  /// 종료 훅용 — [cap] 안에 세션 프로세스를 끝낸다. 고아 ffmpeg를 PID로 죽일 수
  /// 없는 PC라(다른 작업의 ffmpeg가 상시 돈다) 여기서 핸들로 확실히 끊는다.
  ///
  /// [cap]은 **전체** 상한이다. 'q'를 그 60%까지 기다리고, 파일 정리까지 포함해
  /// 상한을 넘기면 핸들로 끊고 나간다 — 남은 파일은 다음 부팅의 복구가 치운다.
  Future<void> shutdown({Duration cap = const Duration(seconds: 1)}) async {
    try {
      await _armed.close(quitCap: cap * 0.6).timeout(cap);
    } on TimeoutException {
      _armed.killAll();
    }
  }

  /// 녹음을 시작한다. 성공하면 파일명을 돌려준다.
  ///
  /// WAV로 캡처하는 이유: 인코더 의존이 없고, 중간에 끊겨도 그때까지
  /// 쓰인 부분이 대체로 재생 가능한 파일로 남는다.
  Future<String?> start(
    String fileName, {
    double gain = 1.0,
    String? backingFileName,
  }) async {
    if (_isRecording) return null;
    // 고정 세션이 마이크를 쥐고 있다 — 아무것도 닫지 않고 거절한다.
    // 고정 중의 R·스페이스는 화면이 마크(markTakeStart)로 보낸다.
    if (_armed.isOpen) {
      debugPrint('녹음 시작 거절 — 고정 세션이 열려 있다(마크를 써야 한다).');
      return null;
    }
    // 프로브가 돌고 있으면 장치를 놓아준다(같은 장치는 동시에 못 연다).
    await stopLevelProbe();

    final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);
    if (!ffmpeg.found) return null;
    final device = await _resolveInputDevice();
    if (device == null) return null;

    // 반주 채널은 **장치가 목록에 있을 때만** 연다. 없는 장치를 넘기면
    // ffmpeg가 통째로 죽어 보컬까지 잃는다.
    final dual = (backingFileName ?? '').isNotEmpty && canRecordDual;

    try {
      final path = await pathBuilder(fileName);
      final backingPath = dual ? await pathBuilder(backingFileName!) : null;
      final job = _runner.start(
        ffmpeg.path!,
        buildRecordArgs(
          deviceName: device,
          outputPath: path,
          gain: gain,
          backingDeviceName: dual ? _backingDeviceName : null,
          backingOutputPath: backingPath,
        ),
      );

      _job = job;
      _isRecording = true;
      _stopping = false;
      _currentFileName = fileName;
      _currentBackingFileName = dual ? backingFileName : null;
      _inputStarts.clear();
      _elapsed = Duration.zero;
      _dbfs = null;
      _peakDbfs = null;
      _anchor = CaptureAnchorEstimator();
      _lastFramePtsMs = null;
      _framedLengthMs = 0;

      final errorLines = <String>[];
      _sub = job.lines.listen(
        (line) {
          final ptsMs = parseAmetadataFramePtsMs(line);
          if (ptsMs != null) {
            // 프레임 머리줄 — 좌표 역산과 길이 측정에 쓴다.
            final prev = _lastFramePtsMs;
            if (prev != null && ptsMs > prev) {
              // 이 프레임도 앞 프레임과 길이가 같다고 보고 끝을 어림한다.
              _framedLengthMs = ptsMs + (ptsMs - prev);
            }
            _lastFramePtsMs = ptsMs;
            if (!_stopping) {
              _anchor.addFrame(
                ptsMs: ptsMs,
                positionMs: songPositionProbe?.call(),
              );
            }
            return;
          }
          final rms = parseRmsLevel(line);
          if (rms != null) {
            _dbfs = rms;
            if (_peakDbfs == null || rms > _peakDbfs!) _peakDbfs = rms;
            _notifyLevel();
            return;
          }
          final out = FfmpegProgressParser.parseOutTime(line);
          if (out != null) {
            _elapsed = out;
            notifyListeners();
            return;
          }
          // 2채널 정렬용 — 입력별 시작 타임스탬프는 시작 직후 한 번만 나온다.
          final started = parseInputStreamStart(line);
          if (started != null) {
            _inputStarts.putIfAbsent(started.input, () => started.startSeconds);
            return;
          }
          // 즉사 원인 보고용 — 장치 열기 실패 등 ffmpeg의 오류 줄을 담아 둔다.
          final detail = ffmpegErrorDetail(line);
          if (detail != null && errorLines.length < 5) errorLines.add(detail);
        },
        onError: (Object e) => debugPrint('녹음 스트림 오류: $e'),
      );

      // 캡처가 stop() 전에 스스로 죽으면(장치 열기 실패 등) '녹음 중' 표시가
      // 유령으로 남고, 정지 시 0초 판정으로 조용히 버려진다 — 종료를 감시해
      // 즉시 상태를 되돌리고 원인을 알린다(2026-08-16 실사고).
      unawaited(
        job.exitCode.then((code) async {
          if (_stopping || !_isRecording || _currentFileName != fileName) {
            return;
          }
          final detail =
              errorLines.isEmpty ? '종료 코드 $code' : errorLines.first;
          await _cleanup();
          onError?.call('녹음을 시작하지 못했습니다 — $detail');
        }),
      );

      notifyListeners();
      return fileName;
    } catch (e) {
      debugPrint('녹음 시작 실패: $e');
      await _cleanup();
      return null;
    }
  }

  /// 녹음을 끝내고 파일명과 길이를 돌려준다.
  /// 2채널이면 [backingFileName]에 반주 채널 파일명이 함께 온다.
  Future<
    ({
      String fileName,
      String? backingFileName,
      int backingSkewMs,
      Duration duration,
      double? peakDbfs,
      int? songAnchorMs,
    })?
  >
  stop() async {
    if (!_isRecording) return null;
    // 종료 감시가 정상 정지를 즉사로 오인하지 않게 먼저 표시한다.
    _stopping = true;
    final fileName = _currentFileName;
    final backingFileName = _currentBackingFileName;
    final skewMs = _measuredSkewMs();
    final job = _job;
    _anchor.freeze();

    // 'q'로 우아하게 끝내야 WAV 헤더 크기가 제대로 기록된다.
    // 반응이 없으면 강제 종료로 넘어간다.
    if (job != null) {
      job.writeStdin('q');
      try {
        await job.exitCode.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        job.cancel();
        await job.exitCode;
      }
    }

    // 🔴 최대 레벨·길이는 **종료를 기다린 뒤에** 읽는다. 'q' 뒤에 마지막
    // 줄들이 마저 흘러나오는데, 그 전에 읽으면 짧은 조각은 값이 비어
    // 멀쩡한 녹음이 「소리 없음」으로 오판됐다.
    final peak = _peakDbfs;
    final framed = Duration(milliseconds: _framedLengthMs);
    final duration = framed > _elapsed ? framed : _elapsed;
    final anchorMs = _anchor.anchorMs;
    await _cleanup();
    if (fileName == null) return null;
    return (
      fileName: fileName,
      backingFileName: backingFileName,
      backingSkewMs: skewMs,
      duration: duration,
      peakDbfs: peak,
      songAnchorMs: anchorMs,
    );
  }

  /// 이번 2채널 녹음에서 반주 채널이 얼마나 늦게 열렸는지(ms).
  /// 한쪽이라도 시작 타임스탬프를 못 읽었으면 0(보정 안 함)이다.
  int _measuredSkewMs() {
    final vocal = _inputStarts[0];
    final backing = _inputStarts[1];
    if (vocal == null || backing == null) return 0;
    return dualCaptureSkewMs(
      vocalStartSeconds: vocal,
      backingStartSeconds: backing,
    );
  }

  /// 마이크 테스트를 시작한다 — 파일을 만들지 않고 레벨만 흘린다.
  /// 녹음 중에는 시작하지 않는다(장치 충돌).
  ///
  /// [includeBacking]이면 반주(PC 재생) 채널도 함께 연다. 2채널 설정에서
  /// 정작 확인해야 할 건 **두 입력이 동시에 들어오는지**라, 실제 녹음과 같은
  /// 조건으로 테스트해야 의미가 있다. 반주 쪽이 안 열려도 마이크 테스트는
  /// 그대로 진행한다(마이크 확인까지 막을 이유가 없다).
  Future<bool> startLevelProbe({
    double gain = 1.0,
    bool includeBacking = false,
  }) async {
    if (_isRecording || _isProbing) return false;
    // 고정 세션이 같은 장치를 쥐고 있다 — 두 번 열다 세션을 흔들지 않는다.
    if (_armed.isOpen) return false;

    final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);
    if (!ffmpeg.found) return false;
    final device = await _resolveInputDevice();
    if (device == null) return false;

    try {
      final job = _runner.start(
        ffmpeg.path!,
        buildLevelProbeArgs(deviceName: device, gain: gain),
      );
      _probeJob = job;
      _isProbing = true;
      _dbfs = null;
      _probePeakDbfs = null;
      _probeSub = job.lines.listen(
        (line) {
          final rms = parseRmsLevel(line);
          if (rms != null) {
            _dbfs = rms;
            if (_probePeakDbfs == null || rms > _probePeakDbfs!) {
              _probePeakDbfs = rms;
            }
            _notifyLevel();
          }
        },
        onError: (Object e) => debugPrint('마이크 테스트 스트림 오류: $e'),
      );
      if (includeBacking) await _startBackingLevelProbe(ffmpeg.path!);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('마이크 테스트 시작 실패: $e');
      await stopLevelProbe();
      return false;
    }
  }

  /// 반주(PC 재생) 채널 레벨 프로브. 마이크와 다른 장치라 별개 프로세스다.
  Future<void> _startBackingLevelProbe(String ffmpegPath) async {
    if (!canRecordDual) return;
    try {
      final job = _runner.start(
        ffmpegPath,
        // 반주는 들어온 그대로 봐야 하니 게인을 걸지 않는다.
        buildLevelProbeArgs(deviceName: _backingDeviceName!),
      );
      _backingProbeJob = job;
      _isBackingProbing = true;
      _backingDbfs = null;
      _backingProbeSub = job.lines.listen(
        (line) {
          final rms = parseRmsLevel(line);
          if (rms != null) {
            _backingDbfs = rms;
            _notifyLevel();
          }
        },
        onError: (Object e) => debugPrint('반주 채널 테스트 스트림 오류: $e'),
      );
    } catch (e) {
      debugPrint('반주 채널 테스트 시작 실패: $e');
      await _stopBackingLevelProbe();
    }
  }

  /// 녹음을 걸기 전에 입력이 살아 있는지 **미리** 잰다.
  ///
  /// 관측한 최대 레벨(dBFS)을 돌려준다. 프로브를 못 띄웠으면 null.
  /// 장치를 여는 데 수백 ms가 걸리므로 첫 값이 온 뒤부터 [window]를 센다 —
  /// 고정 시간만 기다리면 장치가 늦게 열렸을 때 아무것도 못 잰다.
  Future<double?> probeInputLevel({
    Duration window = const Duration(milliseconds: 900),
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (_isRecording || _isProbing) return null;
    if (!await startLevelProbe()) return null;

    final deadline = DateTime.now().add(timeout);
    DateTime? firstSeen;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (_probePeakDbfs != null) {
        firstSeen ??= DateTime.now();
        if (DateTime.now().difference(firstSeen) >= window) break;
      }
    }
    // 종료 때 밀려 나오는 마지막 줄까지 본 뒤에 읽는다.
    await stopLevelProbe();
    return _probePeakDbfs;
  }

  Future<void> stopLevelProbe() async {
    await _stopBackingLevelProbe();
    if (_probeJob == null && !_isProbing) return;
    final job = _probeJob;
    if (job != null) {
      job.writeStdin('q');
      try {
        await job.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        job.cancel();
      } catch (_) {}
    }
    await _probeSub?.cancel();
    _probeSub = null;
    _probeJob = null;
    _isProbing = false;
    if (!_isRecording) _dbfs = null;
    notifyListeners();
  }

  Future<void> _stopBackingLevelProbe() async {
    if (_backingProbeJob == null && !_isBackingProbing) return;
    final job = _backingProbeJob;
    if (job != null) {
      job.writeStdin('q');
      try {
        await job.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        job.cancel();
      } catch (_) {}
    }
    await _backingProbeSub?.cancel();
    _backingProbeSub = null;
    _backingProbeJob = null;
    _isBackingProbing = false;
    _backingDbfs = null;
    notifyListeners();
  }

  Future<void> _cleanup() async {
    await _sub?.cancel();
    _sub = null;
    _job = null;
    _isRecording = false;
    _currentFileName = null;
    _currentBackingFileName = null;
    _inputStarts.clear();
    _peakDbfs = null;
    _dbfs = null;
    notifyListeners();
  }

  bool _disposed = false;

  /// 폐기된 뒤에는 알리지 않는다.
  ///
  /// 녹음 중에 화면이 닫히면 dispose()가 ffmpeg를 끊고, 그 종료를 본 감시
  /// 콜백이 뒤늦게 _cleanup()을 돌려 **이미 폐기된 객체**에 알림을 보낸다
  /// (테스트로 드러난 결함). 경로가 여러 갈래라 한 곳에서 막는다.
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _armed.dispose();
    _sub?.cancel();
    _job?.cancel();
    _probeSub?.cancel();
    _probeJob?.cancel();
    _backingProbeSub?.cancel();
    _backingProbeJob?.cancel();
    super.dispose();
  }
}
