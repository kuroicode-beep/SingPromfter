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

/// ffmpeg dshow 녹음 인자를 만든다. (순수 함수 — 프로세스를 띄우지 않는다)
List<String> buildRecordArgs({
  required String deviceName,
  required String outputPath,
}) {
  return [
    '-hide_banner',
    '-f', 'dshow',
    '-i', 'audio=$deviceName',
    '-ac', '1',
    '-ar', '48000',
    // 파일을 쓰면서 동시에 입력 레벨을 표준출력으로 흘린다.
    '-af',
    'astats=metadata=1:reset=1,'
        'ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-',
    '-progress', 'pipe:1',
    '-nostats',
    '-y',
    outputPath,
  ];
}

class RecordingController extends ChangeNotifier {
  final ProcessRunner _runner;
  final ExternalToolLocator _locator;

  /// 녹음 파일을 둘 전체 경로를 만들어 준다.
  final Future<String> Function(String fileName) pathBuilder;

  JobHandle? _job;
  StreamSubscription<String>? _sub;

  bool _isRecording = false;
  Duration _elapsed = Duration.zero;
  double? _dbfs;
  String? _currentFileName;
  String? _deviceName;
  List<String> _devices = const [];

  RecordingController({
    required this.pathBuilder,
    ProcessRunner runner = const SystemProcessRunner(),
    ExternalToolLocator? locator,
  }) : _runner = runner,
       _locator = locator ?? ExternalToolLocator(runner: runner);

  bool get isRecording => _isRecording;
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

  /// 입력 장치 목록을 새로 읽는다.
  Future<List<String>> refreshDevices() async {
    final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);
    if (!ffmpeg.found) return const [];

    // 장치 목록은 stderr로 나오고 종료 코드도 0이 아니다(정상 동작).
    final result = await _runner.run(ffmpeg.path!, [
      '-hide_banner',
      '-list_devices', 'true',
      '-f', 'dshow',
      '-i', 'dummy',
    ]);
    _devices = parseDshowAudioDevices('${result.stdout}\n${result.stderr}');
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
  Future<String?> start(String fileName) async {
    if (_isRecording) return null;

    final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);
    if (!ffmpeg.found) return null;
    if (_devices.isEmpty) await refreshDevices();
    final device = _deviceName ?? (_devices.isEmpty ? null : _devices.first);
    if (device == null) return null;

    try {
      final path = await pathBuilder(fileName);
      final job = _runner.start(
        ffmpeg.path!,
        buildRecordArgs(deviceName: device, outputPath: path),
      );

      _job = job;
      _isRecording = true;
      _currentFileName = fileName;
      _elapsed = Duration.zero;
      _dbfs = null;

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
          }
        },
        onError: (Object e) => debugPrint('녹음 스트림 오류: $e'),
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
  Future<({String fileName, Duration duration})?> stop() async {
    if (!_isRecording) return null;
    final fileName = _currentFileName;
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
    return (fileName: fileName, duration: duration);
  }

  Future<void> _cleanup() async {
    await _sub?.cancel();
    _sub = null;
    _job = null;
    _isRecording = false;
    _currentFileName = null;
    _dbfs = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _job?.cancel();
    super.dispose();
  }
}
