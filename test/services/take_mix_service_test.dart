import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singpromfter_app/models/recording_take.dart';
import 'package:singpromfter_app/services/process/process_runner.dart';
import 'package:singpromfter_app/services/take_mix_service.dart';

/// ffmpeg 흉내 — `-i`가 있는 호출이면 출력 파일(마지막 인자)에 표식을 써 준다.
/// 그 밖의 호출(where·-version)은 도구 찾기용이라 'ffmpeg'만 돌려준다.
class _TrimFakeRunner implements ProcessRunner {
  _TrimFakeRunner({this.failOn});

  /// 이 입력 파일을 만나면 실패(종료 코드 1)한다.
  final String? failOn;

  /// 머리 자르기로 띄운 호출의 인자(띄운 순서대로).
  final List<List<String>> trims = [];

  @override
  JobHandle start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) => throw UnimplementedError('이 테스트는 run()만 쓴다');

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    if (!arguments.contains('-i')) {
      return const ProcessOutput(exitCode: 0, stdout: 'ffmpeg', stderr: '');
    }
    trims.add(arguments);
    final source = arguments[arguments.indexOf('-i') + 1];
    if (failOn != null && source.endsWith(failOn!)) {
      return const ProcessOutput(exitCode: 1, stdout: '', stderr: 'boom');
    }
    final trim = arguments[arguments.indexOf('-ss') + 1];
    File(arguments.last).writeAsStringSync('trimmed $trim');
    return const ProcessOutput(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  group('mixGains — 밸런스→게인', () {
    test('0.5는 양쪽 1.0 (현행 동작 유지)', () {
      final g = mixGains(0.5);
      expect(g.acc, closeTo(1.0, 1e-9));
      expect(g.vocal, closeTo(1.0, 1e-9));
    });

    test('보컬 쪽 극단은 1.6으로 제한하고 반주는 0으로', () {
      final g = mixGains(1.0);
      expect(g.vocal, closeTo(1.6, 1e-9));
      expect(g.acc, closeTo(0.0, 1e-9));
    });

    test('범위 밖 입력은 0~1로 잘라 계산한다', () {
      expect(mixGains(-3).vocal, 0);
      expect(mixGains(9).acc, 0);
    });
  });

  group('buildAccompanimentCutArgs — 반주 조각 잘라내기', () {
    test('시작·길이를 초 단위 소수 3자리로 변환한다', () {
      final args = buildAccompanimentCutArgs(
        sourcePath: 'mr.mp3',
        outputPath: 'acc.m4a',
        startMs: 2500,
        durationMs: 61234,
      );
      expect(args[args.indexOf('-ss') + 1], '2.500');
      expect(args[args.indexOf('-t') + 1], '61.234');
      expect(args.last, 'acc.m4a');
      expect(args, containsAllInOrder(['-c:a', 'aac']));
    });

    test('음수 시작은 0으로 막는다', () {
      final args = buildAccompanimentCutArgs(
        sourcePath: 's',
        outputPath: 'o',
        startMs: -100,
        durationMs: 1000,
      );
      expect(args[args.indexOf('-ss') + 1], '0.000');
    });
  });

  group('buildMixArgs — 이펙트 체인', () {
    String filterOf(List<String> args) =>
        args[args.indexOf('-filter_complex') + 1];

    test('기본 설정은 볼륨 1.0/1.0에 이펙트 없음', () {
      final filter = filterOf(
        buildMixArgs(
          backingPath: 'a',
          vocalPath: 'b',
          outputPath: 'c',
          alignMs: 0,
        ),
      );
      expect(filter, contains('[0:a]volume=1.00[b]'));
      expect(filter, contains('adelay=0|0,volume=1.00[v]'));
      expect(filter, isNot(contains('afftdn')));
      expect(filter, isNot(contains('aecho')));
    });

    test('보컬 체인 순서: adelay → 노이즈 → 리버브 → 볼륨', () {
      final filter = filterOf(
        buildMixArgs(
          backingPath: 'a',
          vocalPath: 'b',
          outputPath: 'c',
          alignMs: 100,
          mixBalance: 0.8,
          reverbPreset: ReverbPreset.karaoke,
          noiseReduction: true,
        ),
      );
      final delayAt = filter.indexOf('adelay');
      final noiseAt = filter.indexOf('afftdn');
      final echoAt = filter.indexOf('aecho');
      final volumeAt = filter.indexOf('volume=1.60');
      expect(delayAt, lessThan(noiseAt));
      expect(noiseAt, lessThan(echoAt));
      expect(echoAt, lessThan(volumeAt));
      // 반주 게인은 (1-0.8)*2 = 0.4
      expect(filter, contains('[0:a]volume=0.40[b]'));
    });

    test('리버브 프리셋 파라미터', () {
      expect(reverbFilter(ReverbPreset.none), isNull);
      expect(reverbFilter(ReverbPreset.karaoke), 'aecho=0.8:0.85:60:0.35');
      expect(reverbFilter(ReverbPreset.hall), 'aecho=0.8:0.88:220:0.4');
      expect(reverbFilter(ReverbPreset.studio), 'aecho=0.7:0.8:40:0.25');
    });
  });

  group('buildMixArgs', () {
    test('보컬에 정렬 지연을 걸고 반주 길이에 맞춘다', () {
      final args = buildMixArgs(
        backingPath: 'mr.mp3',
        vocalPath: 'vocal.wav',
        outputPath: 'out.m4a',
        alignMs: 2500,
      );
      final filter = args[args.indexOf('-filter_complex') + 1];
      expect(filter, contains('adelay=2500|2500'));
      expect(filter, contains('duration=first'));
      expect(args.last, 'out.m4a');
      // 입력 순서: 반주(0) → 보컬(1)
      expect(args.indexOf('mr.mp3'), lessThan(args.indexOf('vocal.wav')));
    });

    test('음수 정렬값은 0으로 막는다', () {
      final args = buildMixArgs(
        backingPath: 'a',
        vocalPath: 'b',
        outputPath: 'c',
        alignMs: -300,
      );
      final filter = args[args.indexOf('-filter_complex') + 1];
      expect(filter, contains('adelay=0|0'));
    });

    test('정렬 0이면 지연 없이 섞는다', () {
      final args = buildMixArgs(
        backingPath: 'a',
        vocalPath: 'b',
        outputPath: 'c',
        alignMs: 0,
      );
      expect(args[args.indexOf('-filter_complex') + 1], contains('adelay=0|0'));
    });

    test('볼륨 정규화를 끈다 (amix 기본 감쇠 방지)', () {
      final args = buildMixArgs(
        backingPath: 'a',
        vocalPath: 'b',
        outputPath: 'c',
        alignMs: 100,
      );
      expect(args[args.indexOf('-filter_complex') + 1], contains('normalize=0'));
    });
  });

  group('buildDuetMixArgs', () {
    test('반주 + 두 보컬을 각자 지연으로 얹고 반주 길이에 맞춘다', () {
      final args = buildDuetMixArgs(
        backingPath: 'mr.mp3',
        vocalAPath: 'male.wav',
        vocalBPath: 'female.wav',
        outputPath: 'duet.m4a',
        alignAMs: 1200,
        alignBMs: 3400,
      );
      final filter = args[args.indexOf('-filter_complex') + 1];
      expect(filter, contains('adelay=1200|1200'));
      expect(filter, contains('adelay=3400|3400'));
      expect(filter, contains('amix=inputs=3'));
      expect(filter, contains('duration=first'));
      expect(filter, contains('normalize=0'));
      // 입력 순서: 반주(0) → 남(1) → 여(2)
      expect(args.indexOf('mr.mp3'), lessThan(args.indexOf('male.wav')));
      expect(args.indexOf('male.wav'), lessThan(args.indexOf('female.wav')));
      expect(args.last, 'duet.m4a');
    });

    test('반주가 없으면 보컬 둘만 긴 쪽 길이로 겹친다', () {
      final args = buildDuetMixArgs(
        backingPath: null,
        vocalAPath: 'a.wav',
        vocalBPath: 'b.wav',
        outputPath: 'c.m4a',
        alignAMs: -100,
        alignBMs: 0,
      );
      final filter = args[args.indexOf('-filter_complex') + 1];
      expect(filter, contains('amix=inputs=2'));
      expect(filter, contains('duration=longest'));
      expect(filter, contains('adelay=0|0'));
      expect(args, isNot(contains('mr.mp3')));
    });
  });

  group('buildHeadPadArgs — 2채널 반주 정렬', () {
    test('앞에 무음을 덧대고 전 채널에 같은 값을 건다', () {
      final args = buildHeadPadArgs(
        sourcePath: 'acc.wav',
        outputPath: 'acc.tmp.wav',
        delayMs: 786,
      );
      expect(args[args.indexOf('-af') + 1], 'adelay=786:all=1');
      expect(args[args.indexOf('-i') + 1], 'acc.wav');
      expect(args.last, 'acc.tmp.wav');
      // 녹음 원본이라 무손실로 다시 쓴다.
      expect(args[args.indexOf('-c:a') + 1], 'pcm_s16le');
    });
  });

  group('buildHeadTrimArgs — 녹음 지연 보정의 머리 자르기 (v5.17.0)', () {
    test('-ss를 입력 **뒤에** 둔다 — 표본 단위로 정확하게 버린다', () {
      final args = buildHeadTrimArgs(
        sourcePath: 'take.wav',
        outputPath: 'take.wav.trim.wav',
        trimMs: 40,
      );
      expect(args[args.indexOf('-ss') + 1], '0.040');
      expect(args.indexOf('-ss'), greaterThan(args.indexOf('-i')));
      expect(args[args.indexOf('-i') + 1], 'take.wav');
      expect(args.last, 'take.wav.trim.wav');
      // 녹음 원본이라 무손실로 다시 쓴다.
      expect(args[args.indexOf('-c:a') + 1], 'pcm_s16le');
    });

    test('음수는 0으로 막는다', () {
      final args = buildHeadTrimArgs(
        sourcePath: 's',
        outputPath: 'o',
        trimMs: -5,
      );
      expect(args[args.indexOf('-ss') + 1], '0.000');
    });
  });

  // 🔴 plain test() — 실제 파일 IO를 기다린다(testWidgets의 가짜 시계에서는 안 끝난다).
  group('trimHeads — 전부 아니면 전무 (가짜 러너)', () {
    late Directory tmp;
    String pathOf(String name) => '${tmp.path}${Platform.pathSeparator}$name';
    List<String> names() =>
        tmp.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      tmp = Directory.systemTemp.createTempSync('sp_trim_heads_');
      File(pathOf('v.wav')).writeAsStringSync('vocal');
      File(pathOf('v_acc.wav')).writeAsStringSync('backing');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('보컬 하나 — 제자리에서 갈아 끼우고 임시·백업 파일을 남기지 않는다', () async {
      final runner = _TrimFakeRunner();
      final result = await TakeMixService(
        runner: runner,
      ).trimHeads(paths: [pathOf('v.wav')], trimMs: 40);

      expect(result.success, isTrue);
      expect(File(pathOf('v.wav')).readAsStringSync(), 'trimmed 0.040');
      expect(File(pathOf('v_acc.wav')).readAsStringSync(), 'backing');
      expect(names(), ['v.wav', 'v_acc.wav']);
      expect(runner.trims, hasLength(1));
    });

    test('2채널 — 보컬과 반주 채널을 **같은 길이**로 자른다', () async {
      final runner = _TrimFakeRunner();
      final result = await TakeMixService(
        runner: runner,
      ).trimHeads(paths: [pathOf('v.wav'), pathOf('v_acc.wav')], trimMs: 125);

      expect(result.success, isTrue);
      expect(File(pathOf('v.wav')).readAsStringSync(), 'trimmed 0.125');
      expect(File(pathOf('v_acc.wav')).readAsStringSync(), 'trimmed 0.125');
      expect(names(), ['v.wav', 'v_acc.wav']);
    });

    test('🔴 한쪽이라도 실패하면 둘 다 원본 그대로다 — 한쪽만 잘리면 둘이 어긋난다', () async {
      final runner = _TrimFakeRunner(failOn: 'v_acc.wav');
      final result = await TakeMixService(
        runner: runner,
      ).trimHeads(paths: [pathOf('v.wav'), pathOf('v_acc.wav')], trimMs: 125);

      expect(result.success, isFalse);
      expect(File(pathOf('v.wav')).readAsStringSync(), 'vocal');
      expect(File(pathOf('v_acc.wav')).readAsStringSync(), 'backing');
      // 먼저 만들어 둔 보컬 사본도 치운다.
      expect(names(), ['v.wav', 'v_acc.wav']);
    });

    test('파일이 없으면 ffmpeg를 띄우지 않고 실패로 알린다', () async {
      final runner = _TrimFakeRunner();
      final result = await TakeMixService(
        runner: runner,
      ).trimHeads(paths: [pathOf('v.wav'), pathOf('missing.wav')], trimMs: 40);
      expect(result.success, isFalse);
      expect(runner.trims, isEmpty);
      expect(File(pathOf('v.wav')).readAsStringSync(), 'vocal');
    });

    test('자를 길이가 0이면 아무것도 하지 않는다', () async {
      final runner = _TrimFakeRunner();
      final result = await TakeMixService(
        runner: runner,
      ).trimHeads(paths: [pathOf('v.wav')], trimMs: 0);
      expect(result.success, isTrue);
      expect(runner.trims, isEmpty);
      expect(File(pathOf('v.wav')).readAsStringSync(), 'vocal');
    });
  });
}
