// file: test/real/real_ffmpeg_capture_test.dart
//
// 실제 ffmpeg + 실제 마이크로 도는 **옵트인** 회귀 테스트.
//
// 가짜 러너로는 못 잡는 결함이 있었다(2026-09-22): ffmpeg 8.1.1이 ametadata
// 출력을 종료 때까지 쌓아 둬서 레벨 줄이 'q' 뒤에야 왔고, 입력 점검이 매번
// 4초를 다 채웠다. 가짜 러너는 줄을 곧바로 흘려 주니 테스트는 전부 초록이었다.
//
// 평소 `flutter test`에서는 건너뛴다. 돌리려면:
//   SP_REAL_FFMPEG=1 flutter test test/real/real_ffmpeg_capture_test.dart
//
// 🔴 testWidgets로 짜면 안 된다 — 가짜 시계에서는 실제 프로세스 스트림이 안 흐른다.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singpromfter_app/controllers/auto_input_selection.dart';
import 'package:singpromfter_app/controllers/capture_session.dart';
import 'package:singpromfter_app/controllers/recording_controller.dart';
import 'package:singpromfter_app/services/process/external_tool_locator.dart';
import 'package:singpromfter_app/services/process/process_runner.dart';

/// 시간·길이를 재는 실기 테스트는 장치를 **이름으로** 고른다. 자동 선택은 후보의
/// 소리를 재느라(꺼진 Razer 동글이 먼저 열거되면 1초 넘게) 시간이 들쭉날쭉해져서,
/// 「0.9초 안에 열린다」 같은 단언이 장치 사정에 흔들린다. 자동 선택 자체는 맨 아래
/// 테스트가 따로 확인한다.
Future<void> _selectRode(RecordingController recording) async {
  final devices = await recording.refreshDevices();
  final rode = devices.where((d) => d.contains('RØDE')).firstOrNull;
  if (rode != null) recording.deviceName = rode;
  // ignore: avoid_print
  print('device: rode=${rode != null} (${devices.length} devices)');
}

/// 실제 프로세스를 띄우되 핸들을 적어 둔다 — 끝난 뒤 「남은 자식 프로세스 0」을
/// 이름·PID가 아니라 **우리 핸들**로 확인하려는 것이다(이 PC는 남의 ffmpeg가 상시 돈다).
class _TrackingRunner implements ProcessRunner {
  final ProcessRunner _inner = const SystemProcessRunner();
  final List<JobHandle> started = [];

  @override
  JobHandle start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) {
    final job = _inner.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
    started.add(job);
    return job;
  }

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) => _inner.run(executable, arguments, workingDirectory: workingDirectory);
}

void main() {
  final enabled = Platform.environment['SP_REAL_FFMPEG'] == '1';
  final skip = enabled ? null : 'SP_REAL_FFMPEG=1 일 때만 돈다(실제 마이크 사용)';

  late Directory tmp;
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('sp_real_ffmpeg_');
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('입력 점검이 타임아웃 전에 값을 돌려준다', () async {
    final recording = RecordingController(
      pathBuilder: (name) async => '${tmp.path}${Platform.pathSeparator}$name',
    );
    addTearDown(recording.dispose);
    await _selectRode(recording);

    final watch = Stopwatch()..start();
    final peak = await recording.probeInputLevel();
    watch.stop();

    // ignore: avoid_print
    print('probe: ${watch.elapsedMilliseconds}ms peak=$peak');
    expect(peak, isNotNull, reason: '레벨 줄이 실시간으로 안 온다(direct=1 회귀)');
    // 장치 열기 0.5 + 창 0.9 + 종료 0.2 — 예전에는 4.5초였다.
    expect(watch.elapsedMilliseconds, lessThan(2600));
  }, skip: skip, timeout: const Timeout(Duration(seconds: 30)));

  test("녹음 중에 레벨·좌표 표본이 'q' 전에 들어온다", () async {
    final recording = RecordingController(
      pathBuilder: (name) async => '${tmp.path}${Platform.pathSeparator}$name',
    );
    addTearDown(recording.dispose);
    await _selectRode(recording);

    // 재생 위치 대신 벽시계를 넣는다 — t=0의 「벽시계 좌표」가 역산된다.
    final clock = Stopwatch()..start();
    recording.songPositionProbe = () => clock.elapsedMilliseconds;

    final spawnAt = clock.elapsedMilliseconds;
    expect(await recording.start('real.wav'), 'real.wav');
    await Future<void>.delayed(const Duration(milliseconds: 2500));

    final levelBeforeQuit = recording.dbfs;
    final qAt = clock.elapsedMilliseconds;
    final result = await recording.stop();
    final stopTook = clock.elapsedMilliseconds - qAt;

    // ignore: avoid_print
    print(
      'level-before-q=$levelBeforeQuit anchor=${result?.songAnchorMs} '
      '(spawn=$spawnAt) duration=${result?.duration.inMilliseconds}ms '
      'q→exit=${stopTook}ms peak=${result?.peakDbfs}',
    );
    expect(levelBeforeQuit, isNotNull, reason: "레벨 줄이 'q' 전에 안 왔다");
    expect(result, isNotNull);
    expect(result!.songAnchorMs, isNotNull);
    // 장치 열기는 spawn 뒤 0.3~0.9초.
    final openMs = result.songAnchorMs! - spawnAt;
    expect(openMs, inInclusiveRange(200, 1200));
    // 길이 = q 시각 − t=0, 버퍼 50ms라 오차는 0.2초 안쪽(예전에는 0.5초 단위).
    final expected = qAt - result.songAnchorMs!;
    expect(
      (result.duration.inMilliseconds - expected).abs(),
      lessThan(250),
    );
    expect(stopTook, lessThan(1000));
  }, skip: skip, timeout: const Timeout(Duration(seconds: 30)));

  test('고정 세션 — 0.9초 안에 열리고, 임의 마크 5쌍이 제 길이로 잘린다', () async {
    final sessionDir = Directory(
      '${tmp.path}${Platform.pathSeparator}capture_sessions',
    );
    final runner = _TrackingRunner();
    // 마크·줄 도착과 **같은 시계**로 파일시각을 물어보려고 시계를 주입한다.
    final wall = Stopwatch()..start();
    final recording = RecordingController(
      pathBuilder: (name) async => '${tmp.path}${Platform.pathSeparator}$name',
      runner: runner,
      nowUs: () => wall.elapsedMicroseconds,
      sessionDirBuilder: () async => sessionDir,
    );
    addTearDown(recording.dispose);
    final lost = <String>[];
    recording.onSessionLost = (message, {openTake}) => lost.add(message);
    // 장치 목록·ffmpeg 위치는 미리 읽어 둔다 — 앱에서도 고정을 켤 때는 이미 읽혀 있다.
    await _selectRode(recording);

    final watch = Stopwatch()..start();
    final opened = await recording.openSession();
    final liveMs = watch.elapsedMilliseconds;
    final peak = await recording.sessionInputCheck;
    final checkedMs = watch.elapsedMilliseconds;
    // ignore: avoid_print
    print(
      'session: live=${liveMs}ms input-check=${checkedMs}ms peak=$peak '
      'ready=${recording.isSessionReady} label=${recording.sessionLevelBucket}',
    );
    expect(opened, isTrue, reason: recording.sessionError);
    expect(liveMs, lessThanOrEqualTo(900));
    expect(
      recording.isSessionReady,
      isTrue,
      reason: '입력이 무음이거나 시계가 안 잠겼다(peak=$peak) — 마이크를 확인',
    );

    final seed = DateTime.now().millisecondsSinceEpoch & 0xFFFF;
    final random = Random(seed);
    // ignore: avoid_print
    print('random seed=$seed');
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(
        Duration(milliseconds: 200 + random.nextInt(300)),
      );
      final spanTarget = 700 + random.nextInt(801);
      final start = recording.markTakeStart(songPositionMs: 10000 + i * 5000);
      expect(start, isNotNull);
      expect(recording.isTakeOpen, isTrue);
      await Future<void>.delayed(Duration(milliseconds: spanTarget));
      final end = recording.markTakeEnd();
      expect(end, isNotNull);

      final sliceWatch = Stopwatch()..start();
      final out = '${tmp.path}${Platform.pathSeparator}armed_$i.wav';
      final sliced = await recording.sliceTake(start!, end, outputPath: out);
      final sliceMs = sliceWatch.elapsedMilliseconds;
      expect(sliced, isNotNull);
      expect(sliced!.ok, isTrue, reason: sliced.message);
      // 화면이 목록 등록 뒤에 하는 일 — 안 하면 마크가 대기열에 남아, 닫아도 세션
      // 파일이 지워지지 않는다(아래 left-pcm 단언).
      await recording.confirmTakeSaved(start);

      final spanMs = (end!.wallUs - start.wallUs) / 1000;
      final wavMs = (File(out).lengthSync() - 44) / kSessionBytesPerMs;
      final expectedMs = spanMs + sliced.leadInMs - kStopClickTrimMs;
      final errorMs = wavMs - expectedMs;
      // ignore: avoid_print
      print(
        'take $i: span=${spanMs.toStringAsFixed(1)}ms '
        'wav=${wavMs.toStringAsFixed(1)}ms '
        'expected=${expectedMs.toStringAsFixed(1)}ms '
        'error=${errorMs.toStringAsFixed(1)}ms leadIn=${sliced.leadInMs} '
        'truncated=${sliced.truncated} peak=${sliced.peakDbfs?.toStringAsFixed(1)} '
        'markPeak=${end.peakDbfs?.toStringAsFixed(1)} slice=${sliceMs}ms',
      );
      expect(sliced.leadInMs, lessThanOrEqualTo(kArmedLeadInMs));
      expect(errorMs.abs(), lessThanOrEqualTo(55));
      expect(sliced.durationMs, wavMs.round());
    }

    // 시계↔파일 대조: 「지금」의 파일시각과 디스크에 닿은 길이의 차이는 쓰기 지연
    // (실측 0~70ms + 프레임 50ms)뿐이어야 한다. pts가 파일 위치와 어긋나 있다면
    // (드롭 처리·시작 오프셋) 조각 길이는 맞아도 **자리**가 틀린다 — 여기서 잡힌다.
    //
    // 최소값은 「파일이 막 자란 직후」라 쓰기 지연이 0에 가깝다 — 그때의 값이 곧
    // 기준점의 치우침(줄 도착의 최소 지연)이다. 음수로 크게 내려가면 마크가 그만큼
    // 앞당겨 잘린다.
    final clock = recording.debugSessionClock!;
    final pcm = File(recording.debugSessionPcmPath!);
    final handle = await pcm.open();
    var minLagMs = double.infinity;
    var maxLagMs = double.negativeInfinity;
    var bytes = 0;
    final sampling = Stopwatch()..start();
    while (sampling.elapsedMilliseconds < 1200) {
      bytes = await handle.length();
      final fileNowUs = clock.fileTimeUsAt(wall.elapsedMicroseconds)!;
      final lagMs = fileNowUs / 1000 - bytes / kSessionBytesPerMs;
      if (lagMs < minLagMs) minLagMs = lagMs;
      if (lagMs > maxLagMs) maxLagMs = lagMs;
      await Future<void>.delayed(const Duration(milliseconds: 7));
    }
    await handle.close();
    // ignore: avoid_print
    print(
      'clock: file=${(bytes / kSessionBytesPerMs).toStringAsFixed(1)}ms '
      'lag(F(now)-file) min=${minLagMs.toStringAsFixed(1)}ms '
      'max=${maxLagMs.toStringAsFixed(1)}ms '
      'confirmed=${(clock.confirmedFileUs / 1000).toStringAsFixed(1)}ms '
      'gap=${(clock.totalGapUs / 1000).toStringAsFixed(1)}ms '
      'nominal=${clock.nominalFrameUs}us samples=${clock.sampleCount}',
    );
    expect(minLagMs, greaterThanOrEqualTo(-60));
    // 상한이 있어야 **세지 못한 시작 구멍**을 잡는다. dshow의 시작 점프(17~36ms)를
    // 구멍으로 못 세면 파일시각이 그만큼 뒤로 밀려 최소 지연이 3+J ms로 올라간다
    // (정상 실측 2.9~5.8ms). 하한을 조여서는 이 방향을 못 잡는다.
    expect(minLagMs, lessThanOrEqualTo(20));
    expect(maxLagMs, lessThanOrEqualTo(300));

    final closeWatch = Stopwatch()..start();
    await recording.closeSession();
    final closeMs = closeWatch.elapsedMilliseconds;
    final leftPcm = sessionDir.existsSync()
        ? sessionDir.listSync().where((e) => e.path.endsWith('.pcm')).length
        : 0;
    // 남은 자식 프로세스 — 우리가 띄운 핸들이 전부 종료 코드를 냈는가.
    var running = 0;
    for (final job in runner.started) {
      final code = await job.exitCode
          .then<int?>((value) => value)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
      if (code == null) running++;
    }
    // ignore: avoid_print
    print(
      'close: ${closeMs}ms left-pcm=$leftPcm '
      'spawned=${runner.started.length} still-running=$running lost=$lost',
    );
    expect(leftPcm, 0);
    expect(running, 0);
    expect(lost, isEmpty);
    expect(recording.sessionState.name, 'off');
  }, skip: skip, timeout: const Timeout(Duration(seconds: 60)));

  test('입력 장치 자동 — 이 PC에서는 소리가 들어오는 RØDE를 고른다', () async {
    // 이 PC의 마이크는 둘이다: RØDE NT-USB Mini(살아 있음)와 Razer Barracuda X 2.4
    // 동글(헤드셋이 꺼져 있어도 목록에 남아 디지털 무음을 보낸다). 열거 순서가 어느
    // 쪽이 먼저든 자동은 RØDE로 끝나야 한다.
    final runner = _TrackingRunner();
    final recording = RecordingController(
      pathBuilder: (name) async => '${tmp.path}${Platform.pathSeparator}$name',
      runner: runner,
    );
    addTearDown(recording.dispose);
    // 자동 — 장치 이름을 넣지 않는다.
    final devices = await recording.refreshDevices();
    final candidates = inputDeviceCandidates(devices);
    final listJobs = runner.started.length;

    final watch = Stopwatch()..start();
    final selection = await recording.resolveAutoInput();
    final tookMs = watch.elapsedMilliseconds;
    final probes = runner.started.length - listJobs;
    // ignore: avoid_print
    print(
      'auto: candidates=${candidates.length} first-is-rode='
      '${candidates.isNotEmpty && candidates.first.contains('RØDE')} '
      'picked-rode=${selection.picked?.contains('RØDE')} '
      'skipped=${selection.silent.length} probed=${selection.probed} '
      'peak=${selection.pickedPeakDbfs?.toStringAsFixed(1)} '
      'confirmed=${selection.inputConfirmed} probes=$probes took=${tookMs}ms',
    );
    expect(selection.allSilent, isFalse, reason: '후보가 전부 무음이다 — 마이크를 확인');
    expect(selection.picked, isNotNull);
    expect(selection.picked, contains('RØDE'));
    expect(recording.autoInputDevice, contains('RØDE'));
    if (candidates.length > 1) expect(selection.probed, isTrue);
    expect(probes, lessThanOrEqualTo(kAutoInputMaxProbes));
    // 후보마다 최대 1.7초(첫 줄 상한 1.2 + 무음 창 0.5) + 핸들 종료(실측 0.01초).
    expect(tookMs, lessThan(probes * 1800 + 400));

    // 두 번째는 기억한 값이다 — 장치를 다시 열지 않는다.
    final again = Stopwatch()..start();
    expect((await recording.resolveAutoInput()).picked, selection.picked);
    expect(again.elapsedMilliseconds, lessThan(100));
    expect(runner.started.length, listJobs + probes);

    // 프로브를 핸들로 끊은 직후에도 그 장치가 곧바로 녹음으로 열린다(장치가 물려
    // 있으면 레벨 줄이 안 오거나 「Could not」으로 즉사한다).
    final errors = <String>[];
    recording.onError = errors.add;
    expect(await recording.start('auto.wav'), 'auto.wav');
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final levelWhileRecording = recording.dbfs;
    final result = await recording.stop();
    // ignore: avoid_print
    print(
      'auto-record: level=${levelWhileRecording?.toStringAsFixed(1)} '
      'duration=${result?.duration.inMilliseconds}ms '
      'peak=${result?.peakDbfs?.toStringAsFixed(1)} errors=${errors.length}',
    );
    expect(errors, isEmpty);
    expect(levelWhileRecording, isNotNull, reason: '녹음 중 레벨 줄이 안 왔다');
    expect(result, isNotNull);
    expect(isDeadInput(result!.peakDbfs), isFalse);
    // 녹음을 걸 때도 다시 재지 않았다: 프로브 뒤에 뜬 것은 녹음 하나뿐이다.
    expect(runner.started.length, listJobs + probes + 1);

    // 남은 자식 프로세스 — 우리가 띄운 핸들이 전부 종료 코드를 냈는가.
    var running = 0;
    for (final job in runner.started) {
      final code = await job.exitCode
          .then<int?>((value) => value)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
      if (code == null) running++;
    }
    expect(running, 0);
  }, skip: skip, timeout: const Timeout(Duration(seconds: 30)));

  test('후보 하나를 재는 비용 — 무음 장치도 1.7초(+종료) 안에 판정한다', () async {
    final runner = _TrackingRunner();
    final located = await ExternalToolLocator(
      runner: runner,
    ).locate(ExternalTool.ffmpeg);
    expect(located.found, isTrue);
    final recording = RecordingController(
      pathBuilder: (name) async => '${tmp.path}${Platform.pathSeparator}$name',
      runner: runner,
    );
    addTearDown(recording.dispose);
    final candidates = inputDeviceCandidates(await recording.refreshDevices());
    expect(candidates, isNotEmpty);

    for (final device in candidates) {
      final watch = Stopwatch()..start();
      final peak = await probeInputPeakDbfs(
        runner: runner,
        ffmpegPath: located.path!,
        deviceName: device,
      );
      final tookMs = watch.elapsedMilliseconds;
      final isRode = device.contains('RØDE');
      // ignore: avoid_print
      print(
        'probe-one: rode=$isRode peak=${peak?.toStringAsFixed(1)} '
        'live=${!isSilentTake(peak)} took=${tookMs}ms',
      );
      // 첫 줄 상한 1.2초 + 무음 창 0.5초 + 핸들 종료(실측 0.01초).
      expect(tookMs, lessThan(1200 + 500 + 300));
      // 조용한 방의 RØDE는 줄마다 −62~−78dBFS다 — 죽은 장치(−96.7)와는 확실히 갈린다.
      if (isRode) expect(isDeadInput(peak), isFalse, reason: 'RØDE가 죽어 있다');
    }
  }, skip: skip, timeout: const Timeout(Duration(seconds: 30)));
}
