// file: test/controllers/auto_input_selection_test.dart
//
// 입력 장치 「자동」 — 소리가 들어오는 마이크를 고르는 규칙.
//
// 2026-09-22 실측: 이 PC의 마이크 둘 중 Razer 동글은 헤드셋이 꺼져 있어도 목록에
// 남아 디지털 무음(−96.7dBFS)을 보내고, RØDE는 −36.6dBFS로 살아 있다. 열거 순서는
// 고정이 아니라서, 「첫 번째 마이크」를 쓰던 자동은 동글이 먼저 열거된 날에 무음을
// 녹음한다. 그날은 실기로 재현할 수 없으니(오늘은 RØDE가 1번이다) 가짜 러너로
// 「A는 무음, B는 정상」을 만들어 확인한다.
//
// 🔴 testWidgets로 짜면 안 된다 — 가짜 시계에서는 프로세스 스트림·타이머가 영영
// 안 끝나 테스트당 10분씩 타임아웃한다. 전부 plain test()다.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singpromfter_app/controllers/auto_input_selection.dart';
import 'package:singpromfter_app/controllers/recording_controller.dart';
import 'package:singpromfter_app/services/process/process_runner.dart';

const _razer = '마이크(Razer Barracuda X 2.4)';
const _rode = '마이크(RØDE NT-USB Mini)';
const _flow8 = 'MAIN L/R(BEHRINGER FLOW 8 (Streaming))';

/// 실측한 디지털 무음과 살아 있는 마이크의 레벨(dBFS).
const _deadDbfs = -96.7;
const _liveDbfs = -36.6;

/// 테스트가 오래 기다리지 않게 줄인 시간 규칙.
const _fastTiming = AutoProbeTiming(
  firstLineCap: Duration(milliseconds: 300),
  silentWindow: Duration(milliseconds: 40),
  quitCap: Duration(milliseconds: 150),
);

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('inputDeviceCandidates — 소리를 재 볼 후보', () {
    test('마이크 같은 장치만, 열거 순서대로 — 믹서 루프백은 뺀다', () {
      expect(inputDeviceCandidates(const [_flow8, _razer, _rode]), [
        _razer,
        _rode,
      ]);
    });

    test('preferredInputDevice가 고르는 장치가 늘 첫 후보다', () {
      for (final devices in const [
        [_flow8, _razer, _rode],
        [_rode, _razer, _flow8],
        ['Stereo Mix', 'Microphone (USB Audio)'],
        ['Stereo Mix', 'Line In (Realtek)'],
      ]) {
        expect(
          inputDeviceCandidates(devices).first,
          preferredInputDevice(devices),
        );
      }
    });

    test('마이크가 하나도 없을 때만 루프백 아닌 나머지가 후보다', () {
      expect(inputDeviceCandidates(const ['Stereo Mix', 'Line In (Realtek)']), [
        'Line In (Realtek)',
      ]);
      // 마이크가 있으면 라인 입력은 후보가 아니다 — 반주가 흐르는 입력일 수 있다.
      expect(inputDeviceCandidates(const ['Line In (Realtek)', _rode]), [
        _rode,
      ]);
    });

    test('루프백뿐이면 후보가 없다', () {
      expect(inputDeviceCandidates(const ['Stereo Mix', _flow8]), isEmpty);
      expect(inputDeviceCandidates(const []), isEmpty);
    });

    test('직전에 살아 있던 장치를 먼저 잰다 — 후보에 없으면 무시한다', () {
      expect(inputDeviceCandidates(const [_razer, _rode], tryFirst: _rode), [
        _rode,
        _razer,
      ]);
      expect(inputDeviceCandidates(const [_razer, _rode], tryFirst: _flow8), [
        _razer,
        _rode,
      ]);
    });
  });

  group('selectLiveInputDevice — 처음으로 소리가 들어오는 후보', () {
    /// 장치별 레벨표로 도는 가짜 프로브. 부른 순서를 [calls]에 적는다.
    Future<double?> Function(String) probeOf(
      Map<String, double?> levels,
      List<String> calls,
    ) => (device) async {
      calls.add(device);
      return levels[device];
    };

    test('A가 무음이고 B가 살아 있으면 B를 고른다', () async {
      final calls = <String>[];
      final selection = await selectLiveInputDevice(
        candidates: const [_razer, _rode],
        probePeakDbfs: probeOf({_razer: _deadDbfs, _rode: _liveDbfs}, calls),
      );
      expect(selection.picked, _rode);
      expect(selection.silent, [_razer]);
      expect(selection.probed, isTrue);
      expect(selection.allSilent, isFalse);
      expect(calls, [_razer, _rode]);
    });

    test('첫 후보가 살아 있으면 거기서 끝낸다(나머지는 열지 않는다)', () async {
      final calls = <String>[];
      final selection = await selectLiveInputDevice(
        candidates: const [_rode, _razer],
        probePeakDbfs: probeOf({_rode: _liveDbfs, _razer: _deadDbfs}, calls),
      );
      expect(selection.picked, _rode);
      expect(selection.silent, isEmpty);
      expect(calls, [_rode]);
    });

    test('후보가 하나뿐이면 재지 않는다 — 고를 것이 없다', () async {
      final calls = <String>[];
      final selection = await selectLiveInputDevice(
        candidates: const [_rode],
        probePeakDbfs: probeOf({_rode: _deadDbfs}, calls),
      );
      expect(selection.picked, _rode);
      expect(selection.probed, isFalse);
      expect(selection.allSilent, isFalse);
      expect(calls, isEmpty);
    });

    test('후보가 없으면 고른 장치도 없다(무음 판정은 아니다)', () async {
      final selection = await selectLiveInputDevice(
        candidates: const [],
        probePeakDbfs: (_) async => fail('부르면 안 된다'),
      );
      expect(selection.picked, isNull);
      expect(selection.allSilent, isFalse);
    });

    test('전부 무음이면 재 본 장치를 모두 돌려준다', () async {
      final calls = <String>[];
      final selection = await selectLiveInputDevice(
        candidates: const [_razer, _rode],
        probePeakDbfs: probeOf({_razer: _deadDbfs, _rode: _deadDbfs}, calls),
      );
      expect(selection.picked, isNull);
      expect(selection.allSilent, isTrue);
      expect(selection.silent, [_razer, _rode]);
      expect(selection.untried, 0);
    });

    test('살아는 있는데 아주 조용한 마이크도 고른다 — 다만 「확인됨」은 아니다', () async {
      final calls = <String>[];
      final selection = await selectLiveInputDevice(
        candidates: const [_razer, _rode],
        probePeakDbfs: probeOf({_razer: _deadDbfs, _rode: -78.2}, calls),
      );
      // −75(무음 기준)로 고르면 멀쩡한 RØDE를 건너뛰고 「전부 무음」으로 막는다.
      expect(selection.picked, _rode);
      expect(selection.pickedPeakDbfs, -78.2);
      expect(selection.allSilent, isFalse);
      // 녹음해도 될 만큼인지는 기존 입력 점검이 한 번 더 본다.
      expect(selection.inputConfirmed, isFalse);
    });

    test('죽은 장치의 기준은 −85dBFS — 실측한 양쪽과 10dB 넘게 떨어져 있다', () {
      expect(kDeadInputDbfs, -85);
      expect(isDeadInput(null), isTrue);
      expect(isDeadInput(-96.7), isTrue);
      expect(isDeadInput(-100), isTrue);
      expect(isDeadInput(-78.2), isFalse);
      expect(isDeadInput(-36.6), isFalse);
    });

    test('못 연 장치(레벨 줄 없음)는 무음으로 보고 넘어간다', () async {
      final calls = <String>[];
      final selection = await selectLiveInputDevice(
        candidates: const [_razer, _rode],
        probePeakDbfs: probeOf({_razer: null, _rode: _liveDbfs}, calls),
      );
      expect(selection.picked, _rode);
      expect(selection.silent, [_razer]);
    });

    test('한 번에 3개까지만 잰다 — 남은 후보 수를 알려 준다', () async {
      final calls = <String>[];
      const many = ['마이크 1', '마이크 2', '마이크 3', '마이크 4', '마이크 5'];
      final selection = await selectLiveInputDevice(
        candidates: many,
        // 다섯 번째만 살아 있다 — 상한 때문에 닿지 못한다.
        probePeakDbfs: probeOf({'마이크 5': _liveDbfs}, calls),
      );
      expect(kAutoInputMaxProbes, 3);
      expect(calls, ['마이크 1', '마이크 2', '마이크 3']);
      expect(selection.allSilent, isTrue);
      expect(selection.silent, hasLength(3));
      expect(selection.untried, 2);
    });
  });

  group('probeInputPeakDbfs — 후보 하나의 소리 재기', () {
    test('소리가 들어오는 줄을 본 그 자리에서 끝낸다', () async {
      final runner = _AutoRunner(
        deviceLists: const [
          [_rode],
        ],
        levels: const {_rode: _liveDbfs},
      );
      final watch = Stopwatch()..start();
      final peak = await probeInputPeakDbfs(
        runner: runner,
        ffmpegPath: 'ffmpeg',
        deviceName: _rode,
        // 무음 창을 길게 잡아도 살아 있는 장치는 기다리지 않아야 한다.
        timing: const AutoProbeTiming(
          firstLineCap: Duration(seconds: 2),
          silentWindow: Duration(seconds: 2),
          quitCap: Duration(milliseconds: 150),
        ),
      );
      expect(peak, _liveDbfs);
      expect(watch.elapsedMilliseconds, lessThan(1000));
      // 파일을 쓰지 않는 프로브는 'q'(실측 0.5초) 대신 우리 핸들로 곧바로 끊는다.
      expect(runner.jobs.single.cancelled, isTrue);
      expect(runner.jobs.single.stdin, isEmpty);
    });

    test('무음 줄만 오면 창만큼 지켜본 뒤 무음 레벨을 돌려준다', () async {
      final runner = _AutoRunner(
        deviceLists: const [
          [_razer],
        ],
        levels: const {_razer: _deadDbfs},
      );
      final peak = await probeInputPeakDbfs(
        runner: runner,
        ffmpegPath: 'ffmpeg',
        deviceName: _razer,
        timing: _fastTiming,
      );
      expect(peak, _deadDbfs);
      expect(isDeadInput(peak), isTrue);
      expect(runner.jobs.single.cancelled, isTrue);
    });

    test('게인을 걸지 않는다 — 입력 볼륨 0%여도 장치가 살아 있는지는 보인다', () async {
      final runner = _AutoRunner(
        deviceLists: const [
          [_rode],
        ],
        levels: const {_rode: _liveDbfs},
      );
      await probeInputPeakDbfs(
        runner: runner,
        ffmpegPath: 'ffmpeg',
        deviceName: _rode,
        timing: _fastTiming,
      );
      expect(
        runner.jobs.single.arguments.join(' '),
        isNot(contains('volume=')),
      );
    });

    test('레벨 줄이 안 오면 상한에서 null로 끝내고 프로세스를 정리한다', () async {
      final runner = _AutoRunner(
        deviceLists: const [
          [_razer],
        ],
        // 레벨표에 없다 = 줄을 하나도 안 낸다(먹통 장치).
        levels: const {},
      );
      final peak = await probeInputPeakDbfs(
        runner: runner,
        ffmpegPath: 'ffmpeg',
        deviceName: _razer,
        timing: _fastTiming,
      );
      expect(peak, isNull);
      expect(runner.jobs.single.cancelled, isTrue);
      expect(await runner.jobs.single.handle.exitCode, 1);
    });

    test('장치를 못 열어 스스로 죽으면 상한까지 기다리지 않는다', () async {
      final runner = _AutoRunner(
        deviceLists: const [
          [_razer],
        ],
        levels: const {},
        diesOnStart: const {_razer},
      );
      final watch = Stopwatch()..start();
      final peak = await probeInputPeakDbfs(
        runner: runner,
        ffmpegPath: 'ffmpeg',
        deviceName: _razer,
        timing: const AutoProbeTiming(
          firstLineCap: Duration(seconds: 5),
          silentWindow: Duration(seconds: 5),
          quitCap: Duration(milliseconds: 150),
        ),
      );
      expect(peak, isNull);
      expect(watch.elapsedMilliseconds, lessThan(2000));
      // 이미 죽은 프로세스는 다시 끊지 않는다.
      expect(runner.jobs.single.cancelled, isFalse);
    });

    test('끊어도 안 끝나는 먹통 프로세스는 상한까지만 기다린다', () async {
      final runner = _AutoRunner(
        deviceLists: const [
          [_rode],
        ],
        levels: const {_rode: _liveDbfs},
        survivesCancel: const {_rode},
      );
      final watch = Stopwatch()..start();
      final peak = await probeInputPeakDbfs(
        runner: runner,
        ffmpegPath: 'ffmpeg',
        deviceName: _rode,
        timing: _fastTiming,
      );
      expect(peak, _liveDbfs);
      expect(runner.jobs.single.cancelled, isTrue);
      // 종료 상한 150ms — 녹음 시작을 붙들지 않는다.
      expect(watch.elapsedMilliseconds, lessThan(1500));
    });

    test('살아는 있는데 아주 조용한 줄만 오면 창 끝에서 그 레벨을 돌려준다', () async {
      // 실측: 조용한 방의 RØDE는 줄마다 −62~−78dBFS를 오간다. −75 아래 줄만 이어져도
      // 죽은 장치(−96.7)와는 20dB 가까이 떨어져 있다.
      final runner = _AutoRunner(
        deviceLists: const [
          [_rode],
        ],
        levels: const {_rode: -78.2},
      );
      final peak = await probeInputPeakDbfs(
        runner: runner,
        ffmpegPath: 'ffmpeg',
        deviceName: _rode,
        timing: _fastTiming,
      );
      expect(peak, -78.2);
      expect(isSilentTake(peak), isTrue);
      expect(isDeadInput(peak), isFalse);
    });
  });

  group('RecordingController — 자동 입력 선택', () {
    late Directory tmp;
    final controllers = <RecordingController>[];

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sp_auto_input_');
    });

    tearDown(() async {
      for (final c in controllers) {
        c.dispose();
      }
      controllers.clear();
      // 막 닫은 핸들이 늦게 풀릴 수 있어 조건 루프로 지운다.
      for (var attempt = 0; attempt < 20 && tmp.existsSync(); attempt++) {
        try {
          tmp.deleteSync(recursive: true);
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
    });

    RecordingController make(_AutoRunner runner) {
      final recording = RecordingController(
        pathBuilder: (name) async =>
            '${tmp.path}${Platform.pathSeparator}$name',
        runner: runner,
        sessionDirBuilder: () async =>
            Directory('${tmp.path}${Platform.pathSeparator}sessions'),
        sessionWatchdogInterval: null,
        autoProbeTiming: _fastTiming,
      );
      controllers.add(recording);
      return recording;
    }

    /// 동글(무음)이 먼저 열거된 날.
    _AutoRunner dongleFirst({Map<String, double>? levels}) => _AutoRunner(
      deviceLists: const [
        [_flow8, _razer, _rode],
      ],
      levels: levels ?? const {_razer: _deadDbfs, _rode: _liveDbfs},
    );

    test('자동 — 무음인 A를 건너뛰고 소리가 들어오는 B로 녹음한다', () async {
      final runner = dongleFirst();
      final recording = make(runner);
      await recording.refreshDevices();
      // 재기 전에는 이름으로 고른 첫 후보를 가리킨다.
      expect(recording.deviceName, _razer);
      expect(recording.autoInputNeedsProbe, isTrue);

      expect(await recording.start('a.wav'), 'a.wav');

      expect(runner.probedDevices, [_razer, _rode]);
      expect(runner.recordedDevices, [_rode]);
      expect(recording.deviceName, _rode);
      expect(recording.autoInputDevice, _rode);
      expect(recording.currentInputDevice, _rode);
      final selection = recording.autoInputSelection!;
      expect(selection.picked, _rode);
      expect(selection.silent, [_razer]);
      expect(selection.probed, isTrue);
      expect(recording.autoInputNeedsProbe, isFalse);
      await recording.stop();
    });

    test('직접 고른 A는 A 그대로 — 재지 않고(지연 0), 무음은 입력 점검이 알린다', () async {
      final runner = dongleFirst();
      final recording = make(runner);
      await recording.refreshDevices();
      recording.deviceName = _razer;
      expect(recording.usesAutoInput, isFalse);
      expect(recording.autoInputNeedsProbe, isFalse);
      expect(recording.autoInputDevice, isNull);

      expect(await recording.start('a.wav'), 'a.wav');
      // 자동 선택의 프로브가 하나도 뜨지 않았다.
      expect(runner.probedDevices, isEmpty);
      expect(runner.recordedDevices, [_razer]);
      expect(recording.autoInputSelection, isNull);
      await recording.stop();

      // 화면의 녹음 전 입력 점검(probeInputLevel)은 **그 장치만** 재고 무음을 알린다.
      final peak = await recording.probeInputLevel(
        window: const Duration(milliseconds: 40),
        timeout: const Duration(seconds: 2),
      );
      expect(runner.probedDevices, [_razer]);
      expect(peak, _deadDbfs);
      expect(isSilentTake(peak), isTrue);
    });

    test('후보가 전부 무음이면 녹음을 걸지 않고, 재 본 장치를 돌려준다', () async {
      final runner = dongleFirst(
        levels: const {_razer: _deadDbfs, _rode: _deadDbfs},
      );
      final recording = make(runner);
      await recording.refreshDevices();

      final selection = await recording.resolveAutoInput();
      expect(selection.allSilent, isTrue);
      expect(selection.silent, [_razer, _rode]);
      expect(await recording.start('a.wav'), isNull);
      expect(runner.recordedDevices, isEmpty);
      expect(recording.isRecording, isFalse);
      expect(
        silentInputDeviceNote(
          selection: recording.autoInputSelection,
          device: recording.currentInputDevice,
          auto: recording.usesAutoInput,
        ),
        '확인한 장치: $_razer, $_rode — 모두 소리 없음',
      );
      // 무음 결과는 기억하지 않는다 — 다음 시도에서 다시 잰다(그사이 마이크를 켰을 수 있다).
      expect(recording.autoInputNeedsProbe, isTrue);
    });

    test('🔴 전부 무음이었으면 다음 시도는 장치 목록부터 다시 읽는다 — 그사이 꽂은 마이크', () async {
      // 「A, B 모두 소리 없음」 경고 뒤 USB 마이크를 꽂고 다시 R. 예전에는 목록을 다시
      // 읽지 않아 옛 후보 둘만 또 재고 같은 경고가 떴다(설정 새로고침을 눌러야 풀렸다).
      final runner = _AutoRunner(
        deviceLists: const [
          [_razer, _rode],
          [_razer, _rode, '마이크(USB Audio)'],
        ],
        levels: const {
          _razer: _deadDbfs,
          _rode: _deadDbfs,
          '마이크(USB Audio)': _liveDbfs,
        },
      );
      final recording = make(runner);
      await recording.refreshDevices();

      final first = await recording.resolveAutoInput();
      expect(first.allSilent, isTrue);
      expect(runner.listCalls, 1);
      // 경고 문구가 쓸 「확인한 장치」는 남아 있다.
      expect(recording.autoInputSelection?.silent, [_razer, _rode]);

      final again = await recording.resolveAutoInput();
      expect(runner.listCalls, 2);
      expect(again.picked, '마이크(USB Audio)');
      expect(runner.probedDevices, [
        _razer,
        _rode,
        _razer,
        _rode,
        '마이크(USB Audio)',
      ]);
    });

    test('🔴 캡처 중의 새로고침은 「지금 쓰는 장치」를 첫 후보로 되돌리지 않는다', () async {
      // RØDE 하나뿐이라 재지 않고 세션을 열었다 → 웹캠(마이크 이름, 먼저 열거)을 꽂고
      // 설정 > 녹음의 [새로고침]. 세션은 RØDE로 받는데 예전에는 상태 줄·무음 경고가
      // 웹캠을 가리켰다(invalidateAutoInput은 보존하는데 이 길만 안 했다).
      const webcam = '마이크(USB 웹캠)';
      final runner = _AutoRunner(
        deviceLists: const [
          [_rode],
          [webcam, _rode],
        ],
        levels: const {_rode: _liveDbfs, webcam: _liveDbfs},
      );
      final recording = make(runner);
      await recording.refreshDevices();

      final opening = recording.openSession();
      final session = await runner.firstSession();
      expect(session.arguments, contains('audio=$_rode'));
      session.emit('frame:0    pts:0    pts_time:0.000000');
      session.emit('lavfi.astats.Overall.RMS_level=-20.000000');
      expect(await opening, isTrue);
      expect(recording.currentInputDevice, _rode);

      await recording.refreshDevices();
      expect(recording.devices, [webcam, _rode]);
      expect(recording.currentInputDevice, _rode);
      expect(recording.autoInputDevice, _rode);
      expect(
        inputDeviceStatusLabel(
          explicitDevice: null,
          devices: recording.devices,
          autoDevice: recording.autoInputDevice,
          selection: recording.autoInputSelection,
        ),
        contains(_rode),
      );
      // 세션 중에 다시 고르지도 않는다(같은 장치를 또 열지 않는다).
      expect((await recording.resolveAutoInput()).picked, _rode);
      expect(runner.probedDevices, isEmpty);

      // 세션을 닫으면 기억이 비어 있어 새 목록으로 다시 고른다.
      await recording.closeSession();
      expect(recording.autoInputNeedsProbe, isTrue);
      final after = await recording.resolveAutoInput();
      expect(after.picked, webcam);
      expect(runner.probedDevices, [webcam]);
    });

    test('한 번 고르면 기억한다 — 두 번째 녹음은 다시 재지 않는다', () async {
      final runner = dongleFirst();
      final recording = make(runner);
      await recording.refreshDevices();

      expect(await recording.start('a.wav'), 'a.wav');
      await recording.stop();
      final probesAfterFirst = runner.probedDevices.length;
      expect(probesAfterFirst, 2);

      expect(await recording.start('b.wav'), 'b.wav');
      await recording.stop();
      expect(runner.probedDevices, hasLength(probesAfterFirst));
      expect(runner.recordedDevices, [_rode, _rode]);
    });

    test('장치 목록이 달라지면 기억을 버리고 다시 고른다', () async {
      final runner = _AutoRunner(
        deviceLists: const [
          [_razer, _rode],
          // 새로고침 뒤 — 마이크가 하나 더 꽂혔다.
          [_razer, _rode, '마이크(USB Audio)'],
        ],
        levels: const {_razer: _deadDbfs, _rode: _liveDbfs},
      );
      final recording = make(runner);
      await recording.refreshDevices();
      expect((await recording.resolveAutoInput()).picked, _rode);
      expect(runner.probedDevices, [_razer, _rode]);

      await recording.refreshDevices();
      expect(recording.autoInputSelection, isNull);
      expect(recording.autoInputNeedsProbe, isTrue);

      expect(await recording.start('a.wav'), 'a.wav');
      // 직전에 살아 있던 RØDE를 먼저 재서 한 번에 끝난다.
      expect(runner.probedDevices, [_razer, _rode, _rode]);
      expect(runner.recordedDevices, [_rode]);
      await recording.stop();
    });

    test('순서만 바뀐 목록은 변화가 아니다 — 다시 재지 않는다', () async {
      final runner = _AutoRunner(
        deviceLists: const [
          [_razer, _rode, _flow8],
          [_flow8, _rode, _razer],
        ],
        levels: const {_razer: _deadDbfs, _rode: _liveDbfs},
      );
      final recording = make(runner);
      await recording.refreshDevices();
      await recording.resolveAutoInput();
      await recording.refreshDevices();

      expect(recording.autoInputSelection?.picked, _rode);
      expect(recording.autoInputNeedsProbe, isFalse);
      await recording.resolveAutoInput();
      expect(runner.probedDevices, [_razer, _rode]);
    });

    test('고른 장치가 무음이었다고 알리면 목록부터 다시 읽고 처음부터 고른다', () async {
      final runner = dongleFirst();
      final recording = make(runner);
      await recording.refreshDevices();
      expect((await recording.resolveAutoInput()).picked, _rode);
      expect(runner.listCalls, 1);

      // 그사이 RØDE가 죽고 동글이 켜졌다.
      runner.levels = const {_razer: _liveDbfs, _rode: _deadDbfs};
      recording.invalidateAutoInput();
      // 열려 있을지 모를 세션과 어긋나지 않게, 가리키는 장치는 그대로 둔다.
      expect(recording.currentInputDevice, _rode);
      expect(recording.autoInputSelection, isNull);

      final again = await recording.resolveAutoInput();
      expect(runner.listCalls, 2);
      expect(again.picked, _razer);
      // 무음이었던 장치를 먼저 재지 않는다 — 열거 순서대로 처음부터.
      expect(runner.probedDevices, [_razer, _rode, _razer]);
    });

    test('직접 고름 → 자동으로 되돌리면 예전 장치를 쓰지 않는다 (잠복 결함)', () async {
      final runner = dongleFirst();
      final recording = make(runner);
      await recording.refreshDevices();
      recording.deviceName = _flow8;
      expect(recording.currentInputDevice, _flow8);

      // 설정의 「자동」은 null이다 — 화면이 그대로 넣는다.
      recording.deviceName = null;
      expect(recording.usesAutoInput, isTrue);
      expect(await recording.start('a.wav'), 'a.wav');
      expect(runner.recordedDevices, [_rode]);
      await recording.stop();
    });

    test('빈 문자열도 자동이다', () async {
      final recording = make(dongleFirst());
      await recording.refreshDevices();
      recording.deviceName = _flow8;
      recording.deviceName = '';
      expect(recording.usesAutoInput, isTrue);
      expect(recording.deviceName, _razer);
    });

    test('저장해 둔 장치가 목록에 없으면 자동으로 물러나 소리를 재서 고른다', () async {
      final runner = dongleFirst();
      final recording = make(runner);
      recording.deviceName = '마이크(뽑힌 장치)';
      await recording.refreshDevices();
      expect(recording.usesAutoInput, isTrue);
      expect(recording.missingExplicitDevice, '마이크(뽑힌 장치)');

      expect(await recording.start('a.wav'), 'a.wav');
      expect(runner.recordedDevices, [_rode]);
      expect(
        autoInputNotice(
          device: recording.autoInputDevice,
          selection: recording.autoInputSelection,
          missingExplicit: recording.missingExplicitDevice,
        ),
        '저장된 입력 장치 「마이크(뽑힌 장치)」를 찾지 못했습니다 — 입력 장치 자동 선택: $_rode',
      );
      await recording.stop();
    });

    test('마이크가 하나뿐이면 재지 않는다 — 기존 가짜 러너·단일 마이크 PC 보호', () async {
      final runner = _AutoRunner(
        deviceLists: const [
          [_rode, _flow8],
        ],
        levels: const {_rode: _deadDbfs},
      );
      final recording = make(runner);
      await recording.refreshDevices();
      expect(recording.autoInputNeedsProbe, isFalse);

      expect(await recording.start('a.wav'), 'a.wav');
      expect(runner.probedDevices, isEmpty);
      expect(runner.recordedDevices, [_rode]);
      expect(recording.autoInputSelection?.probed, isFalse);
      await recording.stop();
    });

    test('루프백뿐이면 예전처럼 첫 장치로 물러난다(재지 않는다)', () async {
      final runner = _AutoRunner(
        deviceLists: const [
          ['Stereo Mix', _flow8],
        ],
        levels: const {},
      );
      final recording = make(runner);
      await recording.refreshDevices();
      expect(await recording.start('a.wav'), 'a.wav');
      expect(runner.probedDevices, isEmpty);
      expect(runner.recordedDevices, ['Stereo Mix']);
      await recording.stop();
    });

    test('재는 중에 또 불려도 장치를 두 번 열지 않는다', () async {
      final runner = dongleFirst();
      final recording = make(runner);
      await recording.refreshDevices();

      final results = await Future.wait([
        recording.resolveAutoInput(),
        recording.resolveAutoInput(),
      ]);
      expect(results[0].picked, _rode);
      expect(identical(results[0], results[1]), isTrue);
      expect(runner.probedDevices, [_razer, _rode]);
    });

    test('재는 중에 목록이 달라지면 그 결과는 기억하지 않는다', () async {
      final runner = _AutoRunner(
        deviceLists: const [
          [_razer, _rode],
          [_razer, _rode, '마이크(USB Audio)'],
        ],
        levels: const {_razer: _deadDbfs, _rode: _liveDbfs},
      );
      final recording = make(runner);
      await recording.refreshDevices();

      final resolving = recording.resolveAutoInput();
      await recording.refreshDevices();
      final selection = await resolving;
      // 부른 쪽은 결과를 받지만, 컨트롤러는 옛 목록으로 잰 값을 믿지 않는다.
      expect(selection.picked, _rode);
      expect(recording.autoInputSelection, isNull);
      expect(recording.autoInputNeedsProbe, isTrue);
    });

    test('2채널 — 자동이 고른 마이크와 반주 장치가 다르면 함께 연다', () async {
      final runner = dongleFirst();
      final recording = make(runner);
      await recording.refreshDevices();
      recording.backingDeviceName = _flow8;

      expect(
        await recording.start('v.wav', backingFileName: 'acc.wav'),
        'v.wav',
      );
      expect(recording.isDualChannel, isTrue);
      final args = runner.jobs.last.arguments;
      expect(args, contains('audio=$_rode'));
      expect(args, contains('audio=$_flow8'));
      await recording.stop();
    });

    test('녹음 고정도 같은 길을 탄다 — 세션이 B로 열린다', () async {
      final runner = dongleFirst();
      final recording = make(runner);
      await recording.refreshDevices();

      final opening = recording.openSession();
      final session = await runner.firstSession();
      expect(runner.probedDevices, [_razer, _rode]);
      expect(session.arguments, contains('audio=$_rode'));
      session.emit('frame:0    pts:0    pts_time:0.000000');
      session.emit('lavfi.astats.Overall.RMS_level=-20.000000');
      expect(await opening, isTrue);
      expect(recording.sessionBlockedBySilentInput, isFalse);

      await recording.closeSession();
      // 다시 켜도 재지 않는다.
      final reopening = recording.openSession();
      final second = await runner.session(1);
      second.emit('frame:0    pts:0    pts_time:0.000000');
      expect(await reopening, isTrue);
      expect(runner.probedDevices, [_razer, _rode]);
      expect(second.arguments, contains('audio=$_rode'));
      await recording.closeSession();
    });

    test('녹음 고정 — 후보가 전부 무음이면 세션을 열지 않고 그 사유를 남긴다', () async {
      final runner = dongleFirst(
        levels: const {_razer: _deadDbfs, _rode: _deadDbfs},
      );
      final recording = make(runner);
      await recording.refreshDevices();

      expect(await recording.openSession(), isFalse);
      expect(runner.sessions, isEmpty);
      expect(recording.sessionBlockedBySilentInput, isTrue);
      expect(recording.sessionError, contains('소리가 들어오는 입력 장치가 없습니다'));
      expect(recording.sessionError, contains(_razer));
      expect(recording.sessionError, contains(_rode));
      await recording.closeSession();
    });

    test('마이크 테스트는 전부 무음이어도 첫 후보로 연다 — 막대를 볼 수 있어야 한다', () async {
      final runner = dongleFirst(
        levels: const {_razer: _deadDbfs, _rode: _deadDbfs},
      );
      final recording = make(runner);
      await recording.refreshDevices();

      expect(await recording.startLevelProbe(), isTrue);
      expect(recording.isProbing, isTrue);
      // 자동 선택 2번 + 테스트 본체 1번.
      expect(runner.probedDevices, [_razer, _rode, _razer]);
      expect(recording.autoInputSelection?.allSilent, isTrue);
      await recording.stopLevelProbe();
    });

    test('폐기하면 재던 프로브를 우리 핸들로 끊는다', () async {
      final runner = _AutoRunner(
        deviceLists: const [
          [_razer, _rode],
        ],
        // 줄을 안 낸다 — 상한까지 매달려 있는다.
        levels: const {},
      );
      final recording = RecordingController(
        pathBuilder: (name) async => name,
        runner: runner,
        sessionWatchdogInterval: null,
        autoProbeTiming: const AutoProbeTiming(
          firstLineCap: Duration(seconds: 30),
          silentWindow: Duration(seconds: 30),
          quitCap: Duration(milliseconds: 100),
        ),
      );
      await recording.refreshDevices();
      final resolving = recording.resolveAutoInput();
      await runner.waitForJobs(1);
      recording.dispose();

      // 끊긴 프로브는 곧바로 끝나고, 남은 후보는 열지 않는다.
      await resolving.timeout(const Duration(seconds: 5));
      expect(runner.jobs, hasLength(1));
      expect(runner.jobs.single.cancelled, isTrue);
    });
  });

  group('자동 선택을 알리는 글', () {
    const skipped = AutoInputSelection(
      picked: _rode,
      silent: [_razer],
      probed: true,
      pickedPeakDbfs: _liveDbfs,
    );

    test('녹음·고정 토스트 — 「입력 장치 자동 선택: <이름>」', () {
      expect(
        autoInputNotice(device: _rode, selection: skipped),
        '입력 장치 자동 선택: $_rode',
      );
      // 건너뛴 장치는 그 결과를 처음 알릴 때만 덧붙인다.
      expect(
        autoInputNotice(device: _rode, selection: skipped, withSkipped: true),
        '입력 장치 자동 선택: $_rode (소리가 없어 건너뜀: $_razer)',
      );
      // 직접 고른 장치면 알릴 것이 없다.
      expect(autoInputNotice(device: null, selection: skipped), isNull);
    });

    test('기존 토스트 앞에 얹는다 — 안내가 없으면 문구는 그대로', () {
      expect(withAutoInputNotice(null, '녹음을 시작했습니다.'), '녹음을 시작했습니다.');
      expect(
        withAutoInputNotice('입력 장치 자동 선택: $_rode', '녹음을 시작했습니다.'),
        '입력 장치 자동 선택: $_rode\n녹음을 시작했습니다.',
      );
    });

    test('무음 경고 — 확인한 장치를 이름으로, 상한에 걸린 후보 수까지', () {
      expect(
        silentInputDeviceNote(
          selection: const AutoInputSelection(
            picked: null,
            silent: ['마이크 1', '마이크 2', '마이크 3'],
            untried: 2,
            probed: true,
          ),
          device: '마이크 1',
          auto: true,
        ),
        '확인한 장치: 마이크 1, 마이크 2, 마이크 3 — 모두 소리 없음 '
        '(나머지 후보 2개는 확인하지 않았습니다 — 한 번에 3개까지만 확인합니다)',
      );
      // 고른 장치가 나중에 무음이 된 경우·직접 고른 경우는 그 장치 하나를 적는다.
      expect(
        silentInputDeviceNote(selection: skipped, device: _rode, auto: true),
        '입력 장치(자동 선택): $_rode',
      );
      expect(
        silentInputDeviceNote(selection: null, device: _razer, auto: false),
        '입력 장치: $_razer',
      );
      expect(
        silentInputDeviceNote(selection: null, device: null, auto: true),
        '입력 장치를 찾지 못했습니다',
      );
    });

    test('설정 상태 줄 — 「자동 — 지금은 <이름>」', () {
      const devices = [_flow8, _razer, _rode];
      // 재기 전: 이름으로 고른 첫 후보 + 언제 확인하는지.
      expect(
        inputDeviceStatusLabel(explicitDevice: null, devices: devices),
        '자동 — 지금은 $_razer (녹음을 시작할 때 소리가 들어오는 마이크인지 확인합니다)',
      );
      // 잰 뒤.
      expect(
        inputDeviceStatusLabel(
          explicitDevice: null,
          devices: devices,
          autoDevice: _rode,
          selection: skipped,
        ),
        '자동 — 지금은 $_rode (소리 확인됨 · 소리 없는 장치 1개 건너뜀)',
      );
      // 살아는 있는데 아주 조용했으면 「확인됨」이라고 하지 않는다.
      expect(
        inputDeviceStatusLabel(
          explicitDevice: null,
          devices: devices,
          selection: const AutoInputSelection(
            picked: _rode,
            probed: true,
            pickedPeakDbfs: -78.2,
          ),
        ),
        '자동 — 지금은 $_rode (장치 살아 있음 · 입력이 아주 작음)',
      );
      // 마이크가 하나뿐이면 덧붙일 말이 없다.
      expect(
        inputDeviceStatusLabel(
          explicitDevice: null,
          devices: const [_rode, _flow8],
        ),
        '자동 — 지금은 $_rode',
      );
      expect(
        inputDeviceStatusLabel(
          explicitDevice: null,
          devices: devices,
          selection: const AutoInputSelection(
            picked: null,
            silent: [_razer, _rode],
            probed: true,
          ),
        ),
        '자동 — 소리가 들어오는 마이크를 찾지 못했습니다 (확인한 장치: $_razer, $_rode)',
      );
    });

    test('설정 상태 줄 — 직접 고름·사라진 저장 장치·장치 없음', () {
      expect(
        inputDeviceStatusLabel(
          explicitDevice: _rode,
          devices: const [_razer, _rode],
        ),
        '직접 고른 장치를 그대로 씁니다 — 자동으로 바꾸지 않습니다',
      );
      expect(
        inputDeviceStatusLabel(
          explicitDevice: '마이크(뽑힌 장치)',
          devices: const [_rode],
        ),
        '저장된 장치 「마이크(뽑힌 장치)」가 목록에 없습니다. 자동 — 지금은 $_rode',
      );
      expect(
        inputDeviceStatusLabel(explicitDevice: null, devices: const []),
        '자동 — 입력 장치가 없습니다. 새로고침을 눌러 주세요',
      );
    });

    test('상태 줄은 어떤 경우에도 비지 않는다 — 접근성 노드를 없애지 않으려고', () {
      for (final explicit in [null, '', _rode, '없는 장치']) {
        for (final devices in const [
          <String>[],
          [_rode],
          [_razer, _rode],
          [_flow8],
        ]) {
          for (final selection in [
            null,
            skipped,
            const AutoInputSelection(
              picked: null,
              silent: [_razer],
              probed: true,
            ),
            const AutoInputSelection(picked: _rode),
          ]) {
            expect(
              inputDeviceStatusLabel(
                explicitDevice: explicit,
                devices: devices,
                selection: selection,
              ).trim(),
              isNotEmpty,
            );
          }
        }
      }
    });
  });
}

/// 조건이 참이 될 때까지 기다린다(고정 sleep 한 번으로 때우지 않는다).
Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('조건을 기다리다 시간이 넘었다');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// 가짜 ffmpeg 하나.
class _FakeJob {
  _FakeJob(this.arguments, {this.exitsOnCancel = true});

  final List<String> arguments;

  /// 핸들로 끊으면 끝나는가. 거짓이면 끊어도 안 끝나는 먹통 프로세스다.
  final bool exitsOnCancel;
  final StreamController<String> _lines = StreamController<String>();
  final Completer<int> _done = Completer<int>();
  final List<String> stdin = [];
  bool cancelled = false;

  /// `-i audio=<이름>`의 이름(첫 입력).
  String get device {
    final input = arguments[arguments.indexOf('-i') + 1];
    return input.substring('audio='.length);
  }

  late final JobHandle handle = JobHandle(
    lines: _lines.stream,
    exitCode: _done.future,
    cancel: () {
      cancelled = true;
      if (exitsOnCancel) exit(1);
    },
    writeStdin: (data) {
      stdin.add(data);
      if (data == 'q') exit(0);
    },
  );

  /// 줄 하나를 낸다. 끝난 뒤에는 무시한다.
  void emit(String line) {
    if (_lines.isClosed) return;
    _lines.add(line);
  }

  /// 프로세스를 끝낸다. 실제 러너처럼 줄이 다 흐른 뒤에 종료 코드가 난다.
  void exit(int code) {
    if (_done.isCompleted) return;
    unawaited(_lines.close());
    _done.complete(code);
  }
}

/// 장치 목록·레벨 프로브·녹음·고정 세션을 흉내 내는 러너.
///
/// 프로브(`-f null -`)는 [levels]에 적힌 그 장치의 RMS 줄을 곧바로 흘린다 — 표에
/// 없는 장치는 줄을 내지 않는다(먹통). 녹음·세션은 테스트가 직접 줄을 낸다.
class _AutoRunner implements ProcessRunner {
  _AutoRunner({
    required this.deviceLists,
    required this.levels,
    this.diesOnStart = const {},
    this.survivesCancel = const {},
  });

  /// `-list_devices`가 불릴 때마다 차례로 돌려줄 목록(마지막 것은 계속 쓴다).
  final List<List<String>> deviceLists;

  /// 장치별 프로브 레벨(dBFS). 테스트가 도중에 바꿀 수 있다.
  Map<String, double> levels;

  /// 뜨자마자 스스로 죽는 장치(열기 실패).
  final Set<String> diesOnStart;

  /// 핸들로 끊어도 안 끝나는 장치(먹통 프로세스).
  final Set<String> survivesCancel;

  int listCalls = 0;

  /// 목록 조회를 뺀 모든 작업(뜬 순서).
  final List<_FakeJob> jobs = [];
  final List<_FakeJob> sessions = [];

  /// 프로브로 열린 장치(자동 선택 + 마이크 테스트, 뜬 순서).
  final List<String> probedDevices = [];

  /// 녹음으로 열린 장치.
  final List<String> recordedDevices = [];

  /// 작업이 [count]개 뜰 때까지 기다린다.
  Future<void> waitForJobs(int count) => _waitFor(() => jobs.length >= count);

  /// [index]번째 세션 작업이 뜰 때까지 기다린다.
  Future<_FakeJob> session(int index) async {
    await _waitFor(() => sessions.length > index);
    return sessions[index];
  }

  Future<_FakeJob> firstSession() => session(0);

  @override
  JobHandle start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) {
    if (arguments.contains('-list_devices')) {
      final list =
          deviceLists[listCalls < deviceLists.length
              ? listCalls
              : deviceLists.length - 1];
      listCalls++;
      final controller = StreamController<String>();
      for (final d in list) {
        controller.add('[in#0 @ 0x1] "$d" (audio)');
      }
      final closed = controller.close();
      return JobHandle(
        lines: controller.stream,
        exitCode: closed.then((_) => 1),
        cancel: () {},
      );
    }

    final isProbe =
        arguments.length >= 2 &&
        arguments[arguments.length - 2] == 'null' &&
        arguments.last == '-';
    final isSession = arguments.contains('s16le');
    final input = arguments[arguments.indexOf('-i') + 1];
    final device = input.substring('audio='.length);
    final job = _FakeJob(
      arguments,
      exitsOnCancel: !survivesCancel.contains(device),
    );
    jobs.add(job);
    if (isSession) {
      sessions.add(job);
    } else if (isProbe) {
      probedDevices.add(device);
      if (diesOnStart.contains(device)) {
        job.emit('[dshow @ 0x1] Could not find audio only device');
        job.exit(1);
      } else {
        final level = levels[device];
        if (level != null) {
          for (var k = 0; k < 3; k++) {
            job.emit('frame:$k    pts:${k * 2400}    pts_time:${k * 0.05}');
            job.emit(
              'lavfi.astats.Overall.RMS_level=${level.toStringAsFixed(6)}',
            );
          }
        }
      }
    } else {
      recordedDevices.add(device);
    }
    return job.handle;
  }

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async => const ProcessOutput(exitCode: 0, stdout: 'ffmpeg', stderr: '');
}
