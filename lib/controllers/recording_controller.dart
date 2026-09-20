// file: lib/controllers/recording_controller.dart
//
// 마이크 녹음. ffmpeg의 DirectShow 입력으로 캡처한다.
//
// 플러그인(record) 대신 ffmpeg를 쓰는 이유: record_windows가 CMake 3.23+를
// 요구하는데 이 환경의 Visual Studio 번들 CMake가 그보다 낮다. 이미 갖춰 둔
// ffmpeg + ProcessRunner를 재사용하면 툴체인을 건드리지 않고 같은 일을 하며,
// astats 메타데이터로 라이브 입력 레벨까지 얻을 수 있다.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/process/external_tool_locator.dart';
import '../services/process/process_runner.dart';
import '../services/process/tool_progress_parsers.dart';

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

/// 캡처 오디오 필터 체인. 게인은 astats **앞**에 두어 미터가 게인 반영
/// 값을 보여준다(클리핑을 실시간으로 경고할 수 있게). (순수 함수)
String _captureFilterChain(double gain) {
  final volume = gain == 1.0 ? '' : 'volume=${gain.toStringAsFixed(2)},';
  return '${volume}astats=metadata=1:reset=1,'
      'ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-';
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
    '-i', 'audio=$deviceName',
    if (dual) ...['-f', 'dshow', '-i', 'audio=$backingDeviceName'],
    '-ac', '1',
    '-ar', '48000',
    // 파일을 쓰면서 동시에 입력 레벨을 표준출력으로 흘린다.
    '-af', _captureFilterChain(gain),
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
    '-i', 'audio=$deviceName',
    '-ac', '1',
    '-ar', '48000',
    '-af', _captureFilterChain(gain),
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

  /// 캡처가 stop() 전에 스스로 죽었을 때(장치 열기 실패 등) 호출된다 —
  /// 화면이 스낵으로 원인을 알리는 데 쓴다. 없으면 상태만 되돌린다.
  void Function(String message)? onError;

  JobHandle? _job;
  StreamSubscription<String>? _sub;

  // 마이크 테스트(레벨 프로브) — 녹음과 별개 프로세스로 레벨만 흘린다.
  JobHandle? _probeJob;
  StreamSubscription<String>? _probeSub;
  bool _isProbing = false;

  bool _isRecording = false;
  bool _stopping = false;
  Duration _elapsed = Duration.zero;
  double? _dbfs;
  String? _currentFileName;
  String? _currentBackingFileName;
  final Map<int, double> _inputStarts = {};
  String? _deviceName;
  String? _backingDeviceName;
  List<String> _devices = const [];

  RecordingController({
    required this.pathBuilder,
    ProcessRunner runner = const SystemProcessRunner(),
    ExternalToolLocator? locator,
  }) : _runner = runner,
       _locator = locator ?? ExternalToolLocator(runner: runner);

  bool get isRecording => _isRecording;
  bool get isProbing => _isProbing;
  Duration get elapsed => _elapsed;
  double? get dbfs => _dbfs;
  String get levelLabel => inputLevelLabel(_dbfs);
  double get level => normalizedLevel(_dbfs);
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
    return backing != (_deviceName ?? _devices.first);
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
    _deviceName ??= _devices.isEmpty ? null : _devices.first;
    notifyListeners();
    return _devices;
  }

  Future<bool> isAvailable() async {
    final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);
    if (!ffmpeg.found) return false;
    if (_devices.isEmpty) await refreshDevices();
    return _devices.isNotEmpty;
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
    // 프로브가 돌고 있으면 장치를 놓아준다(같은 장치는 동시에 못 연다).
    await stopLevelProbe();

    final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);
    if (!ffmpeg.found) return null;
    if (_devices.isEmpty) await refreshDevices();
    // 저장된 장치가 뽑혔을 수 있으니 목록에 없으면 첫 장치로 폴백한다.
    var device = _deviceName ?? (_devices.isEmpty ? null : _devices.first);
    if (device != null && _devices.isNotEmpty && !_devices.contains(device)) {
      device = _devices.first;
    }
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

      final errorLines = <String>[];
      _sub = job.lines.listen(
        (line) {
          final rms = parseRmsLevel(line);
          if (rms != null) {
            _dbfs = rms;
            notifyListeners();
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
          final trimmed = line.trim();
          if (errorLines.length < 5 &&
              (trimmed.startsWith('Error') || trimmed.contains('Could not'))) {
            errorLines.add(trimmed);
          }
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

    final duration = _elapsed;
    await _cleanup();
    if (fileName == null) return null;
    return (
      fileName: fileName,
      backingFileName: backingFileName,
      backingSkewMs: skewMs,
      duration: duration,
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
  Future<bool> startLevelProbe({double gain = 1.0}) async {
    if (_isRecording || _isProbing) return false;

    final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);
    if (!ffmpeg.found) return false;
    if (_devices.isEmpty) await refreshDevices();
    var device = _deviceName ?? (_devices.isEmpty ? null : _devices.first);
    if (device != null && _devices.isNotEmpty && !_devices.contains(device)) {
      device = _devices.first;
    }
    if (device == null) return false;

    try {
      final job = _runner.start(
        ffmpeg.path!,
        buildLevelProbeArgs(deviceName: device, gain: gain),
      );
      _probeJob = job;
      _isProbing = true;
      _dbfs = null;
      _probeSub = job.lines.listen(
        (line) {
          final rms = parseRmsLevel(line);
          if (rms != null) {
            _dbfs = rms;
            notifyListeners();
          }
        },
        onError: (Object e) => debugPrint('마이크 테스트 스트림 오류: $e'),
      );
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('마이크 테스트 시작 실패: $e');
      await stopLevelProbe();
      return false;
    }
  }

  Future<void> stopLevelProbe() async {
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

  Future<void> _cleanup() async {
    await _sub?.cancel();
    _sub = null;
    _job = null;
    _isRecording = false;
    _currentFileName = null;
    _currentBackingFileName = null;
    _inputStarts.clear();
    _dbfs = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _job?.cancel();
    _probeSub?.cancel();
    _probeJob?.cancel();
    super.dispose();
  }
}
