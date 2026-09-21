import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singpromfter_app/controllers/recording_controller.dart';
import 'package:singpromfter_app/models/recording_take.dart';
import 'package:singpromfter_app/services/process/process_runner.dart';
import 'package:singpromfter_app/services/recording_library_service.dart';

RecordingTake take({
  String id = 't1',
  String songId = 's1',
  String title = '봄날',
  String comment = '',
  int rating = 0,
  bool keep = false,
  DateTime? at,
}) {
  return RecordingTake(
    id: id,
    songId: songId,
    songTitle: title,
    fileName: '$id.wav',
    recordedAt: at ?? DateTime(2026, 7, 28, 10),
    durationMs: 60000,
    comment: comment,
    rating: rating,
    isKeep: keep,
  );
}

void main() {
  group('shouldAutoAdvance — 녹음 중 자동 진행 차단', () {
    test('녹음 중이면 다음 곡이 있어도 넘어가지 않는다', () {
      expect(
        shouldAutoAdvance(isRecording: true, queueHasNext: true),
        isFalse,
      );
    });

    test('녹음이 아니면 다음 곡이 있을 때 넘어간다', () {
      expect(
        shouldAutoAdvance(isRecording: false, queueHasNext: true),
        isTrue,
      );
    });

    test('다음 곡이 없으면 넘어가지 않는다', () {
      expect(
        shouldAutoAdvance(isRecording: false, queueHasNext: false),
        isFalse,
      );
    });
  });

  group('inputLevelLabel — 색이 아닌 말로 상태 전달', () {
    test('구간별 문구', () {
      expect(inputLevelLabel(null), '입력 확인 중');
      expect(inputLevelLabel(-60), '소리 없음');
      expect(inputLevelLabel(-35), '너무 작음');
      expect(inputLevelLabel(-15), '입력 좋음');
      expect(inputLevelLabel(-1), '너무 큼');
    });
  });

  group('normalizedLevel', () {
    test('0~1로 제한한다', () {
      expect(normalizedLevel(null), 0);
      expect(normalizedLevel(-100), 0);
      expect(normalizedLevel(0), 1);
      expect(normalizedLevel(10), 1);
      expect(normalizedLevel(-30), closeTo(0.5, 0.01));
    });
  });

  _ffmpegRecordingTests();

  group('RecordingFilter', () {
    final takes = [
      take(id: 'a', rating: 4),
      take(id: 'b', comment: '고음 불안'),
      take(id: 'c', keep: true),
      take(id: 'd', songId: 's2', title: '거리에서'),
    ];

    test('전체 모드는 다 보여준다', () {
      expect(RecordingFilter.apply(takes), hasLength(4));
    });

    test('평가함 / 코멘트 / 보관 필터', () {
      expect(
        RecordingFilter.apply(takes, mode: RecordingFilterMode.rated)
            .map((t) => t.id),
        ['a'],
      );
      expect(
        RecordingFilter.apply(takes, mode: RecordingFilterMode.commented)
            .map((t) => t.id),
        ['b'],
      );
      expect(
        RecordingFilter.apply(takes, mode: RecordingFilterMode.keep)
            .map((t) => t.id),
        ['c'],
      );
    });

    test('곡 제목으로 검색한다 (초성 포함)', () {
      expect(
        RecordingFilter.apply(takes, query: '거리').map((t) => t.id),
        ['d'],
      );
      expect(
        RecordingFilter.apply(takes, query: 'ㄱㄹㅇㅅ').map((t) => t.id),
        ['d'],
      );
    });

    test('코멘트로도 검색한다', () {
      expect(
        RecordingFilter.apply(takes, query: '고음').map((t) => t.id),
        ['b'],
      );
    });

    test('곡 id로 한정할 수 있다', () {
      expect(RecordingFilter.apply(takes, songId: 's2'), hasLength(1));
    });

    test('최근 순 정렬', () {
      final sorted = RecordingFilter.sortByNewest([
        take(id: 'old', at: DateTime(2026, 1, 1)),
        take(id: 'new', at: DateTime(2026, 7, 1)),
      ]);
      expect(sorted.first.id, 'new');
    });
  });

  group('RecordingTake JSON', () {
    test('왕복 후 값이 보존된다', () {
      final original = take(id: 'x', comment: '메모', rating: 3, keep: true);
      final restored = RecordingTake.fromJson(original.toJson());
      expect(restored.id, 'x');
      expect(restored.comment, '메모');
      expect(restored.rating, 3);
      expect(restored.isKeep, isTrue);
      expect(restored.durationMs, 60000);
    });

    test('AI 보정본 표시(correctedFrom)가 왕복에 살아남는다', () {
      final corrected = take(id: 'c').copyWith(correctedFrom: 'src-take');
      final restored = RecordingTake.fromJson(corrected.toJson());
      expect(restored.correctedFrom, 'src-take');
      expect(restored.isCorrected, isTrue);
      // v2.x 저장분(필드 없음)은 생녹음으로 읽힌다.
      expect(RecordingTake.fromJson(const {}).isCorrected, isFalse);
    });

    test('별점은 0~5로 제한한다', () {
      expect(RecordingTake.fromJson({'rating': 99}).rating, 5);
      expect(RecordingTake.fromJson({'rating': -3}).rating, 0);
    });

    test('필드가 없어도 안전하게 읽는다', () {
      final t = RecordingTake.fromJson({});
      expect(t.durationMs, 0);
      expect(t.isRated, isFalse);
      expect(t.hasComment, isFalse);
    });
  });
}

// ffmpeg 기반 녹음의 출력 파싱 — 실제 ffmpeg 출력 형태로 고정한다.
void _ffmpegRecordingTests() {
  group('parseRmsLevel', () {
    test('astats 메타데이터에서 RMS를 읽는다', () {
      expect(
        parseRmsLevel('lavfi.astats.Overall.RMS_level=-21.091524'),
        closeTo(-21.091524, 1e-6),
      );
    });

    test('앞에 다른 내용이 붙어도 읽는다', () {
      expect(
        parseRmsLevel('[Parsed_ametadata_1 @ 0x1] '
            'lavfi.astats.Overall.RMS_level=-30.5'),
        closeTo(-30.5, 1e-6),
      );
    });

    test('무음(-inf)은 매우 낮은 값으로 처리한다', () {
      expect(parseRmsLevel('lavfi.astats.Overall.RMS_level=-inf'), -100);
    });

    test('관계없는 줄은 null', () {
      expect(parseRmsLevel('out_time_us=1000000'), isNull);
      expect(parseRmsLevel(''), isNull);
    });
  });

  group('parseDshowAudioDevices', () {
    const sample = '''
[in#0 @ 0x1] "Code의 Z Fold4 (Windows 가상 카메라)" (video)
[in#0 @ 0x1]   Alternative name "@device_pnp_x"
[in#0 @ 0x1] "마이크(RØDE NT-USB Mini)" (audio)
[in#0 @ 0x1]   Alternative name "@device_cm_y"
[in#0 @ 0x1] "MAIN L/R(BEHRINGER FLOW 8 (Streaming))" (audio)
''';

    test('오디오 장치만 뽑는다 (비디오 제외)', () {
      final devices = parseDshowAudioDevices(sample);
      expect(devices, hasLength(2));
      expect(devices.first, '마이크(RØDE NT-USB Mini)');
      expect(devices.last, 'MAIN L/R(BEHRINGER FLOW 8 (Streaming))');
    });

    test('장치가 없으면 빈 목록', () {
      expect(parseDshowAudioDevices('nothing here'), isEmpty);
    });
  });

  group('buildRecordArgs', () {
    test('장치명과 출력 경로가 들어간다', () {
      final args = buildRecordArgs(
        deviceName: '마이크(RØDE NT-USB Mini)',
        outputPath: 'C:/out.wav',
      );
      expect(args, contains('dshow'));
      expect(args, contains('audio=마이크(RØDE NT-USB Mini)'));
      expect(args.last, 'C:/out.wav');
    });

    test('레벨 출력과 진행률을 함께 켠다', () {
      final args = buildRecordArgs(deviceName: 'mic', outputPath: 'o.wav');
      final filter = args[args.indexOf('-af') + 1];
      expect(filter, contains('astats'));
      expect(filter, contains('RMS_level'));
      expect(args, containsAllInOrder(['-progress', 'pipe:1']));
    });

    test('모노 48kHz로 캡처한다', () {
      final args = buildRecordArgs(deviceName: 'mic', outputPath: 'o.wav');
      expect(args[args.indexOf('-ac') + 1], '1');
      expect(args[args.indexOf('-ar') + 1], '48000');
    });

    test('게인 1.0이면 volume 필터를 넣지 않는다', () {
      final args = buildRecordArgs(deviceName: 'mic', outputPath: 'o.wav');
      expect(args[args.indexOf('-af') + 1], isNot(contains('volume=')));
    });

    test('게인이 다르면 volume이 astats 앞에 온다 (미터에 게인 반영)', () {
      final args = buildRecordArgs(
        deviceName: 'mic',
        outputPath: 'o.wav',
        gain: 1.5,
      );
      final filter = args[args.indexOf('-af') + 1];
      expect(filter, startsWith('volume=1.50,'));
      expect(filter.indexOf('volume='), lessThan(filter.indexOf('astats')));
    });
  });

  group('buildRecordArgs — 독립 2채널', () {
    List<String> dualArgs() => buildRecordArgs(
      deviceName: '마이크(RØDE NT-USB Mini)',
      outputPath: 'C:/vocal.wav',
      backingDeviceName: 'MAIN L/R(BEHRINGER FLOW 8 (Streaming))',
      backingOutputPath: 'C:/acc.wav',
    );

    test('입력이 둘, 출력도 둘이다', () {
      final args = dualArgs();
      expect(
        args.where((a) => a.startsWith('audio=')).length,
        2,
        reason: 'dshow 입력이 마이크와 반주 둘이어야 한다',
      );
      expect(args, contains('C:/vocal.wav'));
      expect(args.last, 'C:/acc.wav');
    });

    test('각 출력이 어느 입력을 쓸지 -map으로 못 박는다', () {
      final args = dualArgs();
      // 보컬 출력 앞에 0:a, 반주 출력 앞에 1:a.
      expect(args, containsAllInOrder(['-map', '0:a', 'C:/vocal.wav']));
      expect(args, containsAllInOrder(['-map', '1:a']));
      expect(
        args.indexOf('C:/vocal.wav'),
        lessThan(args.lastIndexOf('-map')),
        reason: '두 번째 -map은 보컬 출력 뒤에 와야 반주 출력에 걸린다',
      );
    });

    test('레벨 미터·게인은 보컬 채널에만 건다', () {
      final args = buildRecordArgs(
        deviceName: 'mic',
        outputPath: 'v.wav',
        gain: 1.5,
        backingDeviceName: 'pc',
        backingOutputPath: 'a.wav',
      );
      // -af는 하나뿐이고 보컬 출력보다 앞에 있다.
      expect(args.where((a) => a == '-af').length, 1);
      expect(args.indexOf('-af'), lessThan(args.indexOf('v.wav')));
      expect(args[args.indexOf('-af') + 1], startsWith('volume=1.50,'));
    });

    test('반주 채널은 스테레오로 받는다', () {
      final args = dualArgs();
      final tail = args.sublist(args.lastIndexOf('-map'));
      expect(tail[tail.indexOf('-ac') + 1], '2');
      expect(tail[tail.indexOf('-ar') + 1], '48000');
    });

    test('반주 장치나 경로가 비면 1채널 인자 그대로다', () {
      final base = buildRecordArgs(deviceName: 'mic', outputPath: 'v.wav');
      expect(
        buildRecordArgs(
          deviceName: 'mic',
          outputPath: 'v.wav',
          backingDeviceName: 'pc',
        ),
        base,
        reason: '출력 경로가 없으면 2채널로 가지 않는다',
      );
      expect(
        buildRecordArgs(
          deviceName: 'mic',
          outputPath: 'v.wav',
          backingOutputPath: 'a.wav',
        ),
        base,
        reason: '장치가 없으면 2채널로 가지 않는다',
      );
    });
  });

  group('isSilentTake — 조용히 실패하는 녹음을 잡는다', () {
    // 2026-09-21 실측. 같은 PC의 세 장치를 3초씩 받아 본 최대 레벨:
    //   RØDE NT-USB Mini  -68.7dB  ← 살아 있는 마이크(실제 노이즈 플로어)
    //   FLOW 8 MAIN L/R   -84.3dB  ← 아무것도 안 들어옴
    //   Razer(꺼진 헤드셋) -90.3dB  ← 완전 디지털 무음
    test('살아 있는 마이크의 노이즈 플로어는 무음이 아니다', () {
      expect(isSilentTake(-68.7), isFalse);
    });

    test('아무것도 안 들어오는 장치는 무음으로 잡는다', () {
      expect(isSilentTake(-84.3), isTrue);
      expect(isSilentTake(-90.3), isTrue);
      expect(isSilentTake(-102), isTrue);
    });

    test('레벨을 한 번도 못 읽었으면 무음으로 본다', () {
      // 캡처가 즉사하면 astats 줄이 한 번도 안 온다.
      expect(isSilentTake(null), isTrue);
    });

    test('정상 노래 레벨은 당연히 무음이 아니다', () {
      expect(isSilentTake(-20), isFalse);
      expect(isSilentTake(-3), isFalse);
    });
  });

  group('preferredInputDevice — 자동 선택이 믹서를 잡지 않게', () {
    // 2026-09-21 실사고: dshow 열거 순서가 바뀌어 FLOW 8 MAIN L/R이 1번으로
    // 올라왔고, 그걸 녹음한 테이크가 디지털 무음으로 남았다. 반주도 목소리도
    // 없이 조용히 실패해서 들어 보기 전에는 알 수가 없었다.
    const sawOrder = [
      'MAIN L/R(BEHRINGER FLOW 8 (Streaming))',
      '마이크(Razer Barracuda X 2.4)',
      '마이크(RØDE NT-USB Mini)',
    ];

    test('믹서 루프백이 1번이어도 마이크를 고른다', () {
      expect(preferredInputDevice(sawOrder), '마이크(Razer Barracuda X 2.4)');
    });

    test('순서가 바뀌어도 마이크를 고른다', () {
      expect(
        preferredInputDevice(const [
          'MAIN L/R(BEHRINGER FLOW 8 (Streaming))',
          '마이크(RØDE NT-USB Mini)',
        ]),
        '마이크(RØDE NT-USB Mini)',
      );
    });

    test('영문 Microphone도 마이크로 본다', () {
      expect(
        preferredInputDevice(const ['Stereo Mix', 'Microphone (USB Audio)']),
        'Microphone (USB Audio)',
      );
    });

    test('마이크가 없으면 루프백이 아닌 것을 고른다', () {
      expect(
        preferredInputDevice(const ['Stereo Mix', 'Line In (Realtek)']),
        'Line In (Realtek)',
      );
    });

    test('전부 루프백뿐이면 첫 번째로 물러난다', () {
      expect(preferredInputDevice(const ['Stereo Mix']), 'Stereo Mix');
    });

    test('장치가 없으면 null', () {
      expect(preferredInputDevice(const []), isNull);
    });
  });

  group('kMinimumTakeDuration — 짧은 조각을 지우지 않는다', () {
    test('한 줄짜리 랩(1초 미만)도 저장된다', () {
      // 「우리는 펑클」은 0.88초다. 옛 3초 기준은 이런 조각을 통째로
      // 삭제했다(2026-09-21 실사고 — 한 줄씩 받은 조각이 거의 다 사라졌다).
      expect(
        const Duration(milliseconds: 880) >= kMinimumTakeDuration,
        isTrue,
      );
    });

    test('눌렀다 뗀 수준만 거른다', () {
      expect(const Duration(milliseconds: 200) < kMinimumTakeDuration, isTrue);
    });

    test('옛 3초 기준보다 확실히 느슨하다', () {
      expect(kMinimumTakeDuration < const Duration(seconds: 3), isTrue);
    });
  });

  group('2채널 정렬 — 늦게 열리는 반주 장치 보정', () {
    // 실측 줄 그대로(2026-09-21).
    const vocalLine =
        '  Stream #0:0: Audio: pcm_s16le, 44100 Hz, stereo, s16, '
        '1411 kb/s, start 148764.026000';
    const backingLine =
        '  Stream #1:0: Audio: pcm_s16le, 44100 Hz, stereo, s16, '
        '1411 kb/s, start 148764.841000';

    test('입력 스트림 줄에서 번호와 시작 시각을 뽑는다', () {
      final v = parseInputStreamStart(vocalLine);
      expect(v?.input, 0);
      expect(v?.startSeconds, closeTo(148764.026, 0.0005));
      expect(parseInputStreamStart(backingLine)?.input, 1);
    });

    test('start가 없는 출력 스트림 줄은 걸리지 않는다', () {
      expect(
        parseInputStreamStart(
          '  Stream #0:0: Audio: pcm_s16le ([1][0][0][0] / 0x0001), '
          '48000 Hz, mono, s16, 768 kb/s',
        ),
        isNull,
      );
      expect(parseInputStreamStart('  Stream #0:0 -> #0:0 (pcm_s16le)'), isNull);
      expect(parseInputStreamStart('아무 줄'), isNull);
    });

    test('두 줄에서 잰 어긋남이 실측값과 맞는다', () {
      final v = parseInputStreamStart(vocalLine)!;
      final b = parseInputStreamStart(backingLine)!;
      final skew = dualCaptureSkewMs(
        vocalStartSeconds: v.startSeconds,
        backingStartSeconds: b.startSeconds,
      );
      // 보고 차이 815ms - 잔차 29ms = 786ms. 이 값으로 덧댄 뒤 실측 잔여 4ms.
      expect(skew, 786);
    });

    test('차이가 잔차보다 작으면 0으로 눕는다 (앞당기지 않는다)', () {
      expect(
        dualCaptureSkewMs(vocalStartSeconds: 100, backingStartSeconds: 100.01),
        0,
      );
      expect(
        dualCaptureSkewMs(vocalStartSeconds: 100, backingStartSeconds: 99.5),
        0,
      );
    });
  });

  group('canRecordDual — 못 여는 장치로 보컬까지 잃지 않는다', () {
    RecordingController make() =>
        RecordingController(pathBuilder: (name) async => name);

    test('반주 장치가 비면 false', () {
      expect(make().canRecordDual, isFalse);
    });

    test('장치 목록에 없는 이름이면 false', () {
      final c = make()..backingDeviceName = '없는 장치';
      expect(c.canRecordDual, isFalse);
    });

    test('빈 문자열은 null로 눕는다', () {
      final c = make()..backingDeviceName = '';
      expect(c.backingDeviceName, isNull);
    });
  });

  group('buildLevelProbeArgs — 마이크 테스트', () {
    test('파일 대신 null 출력으로 레벨만 흘린다', () {
      final args = buildLevelProbeArgs(deviceName: 'mic');
      expect(args.last, '-');
      expect(args[args.length - 2], 'null');
      expect(args, isNot(contains('-progress')));
      final filter = args[args.indexOf('-af') + 1];
      expect(filter, contains('RMS_level'));
    });

    test('녹음과 같은 게인 체인을 쓴다', () {
      final args = buildLevelProbeArgs(deviceName: 'mic', gain: 0.8);
      expect(args[args.indexOf('-af') + 1], startsWith('volume=0.80,'));
    });
  });

  group('refreshDevices — UTF-8 스트리밍 디코딩 (2026-08-16 회귀)', () {
    test('한글 장치명이 깨지지 않고 들어온다', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final recording = RecordingController(
        pathBuilder: (name) async => name,
        runner: _DeviceListFakeRunner(),
      );

      final devices = await recording.refreshDevices();

      // Process.run의 시스템 인코딩(cp949) 경로였다면 "留덉씠??..."처럼
      // 깨졌다 — start() 스트리밍(UTF-8) 경로는 원형을 보존해야 한다.
      expect(devices, contains('마이크(RØDE NT-USB Mini)'));
      expect(recording.deviceName, '마이크(RØDE NT-USB Mini)');
      recording.dispose();
    });
  });
  group('onCaptureStarted — 기다림 없이 재생하려면 기준점이 필요하다', () {
    // 🔴 testWidgets로 짜면 안 된다 — 가짜 시계 안에서는 start()의 실제
    // 비동기(프로세스 스트림)가 영영 안 끝나 테스트당 10분씩 타임아웃한다
    // (2026-09-22에 실제로 그렇게 20분을 태웠다).
    test('장치가 열려 첫 소리가 들어올 때 한 번만 알린다', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final recording = RecordingController(
        pathBuilder: (name) async => name,
        runner: _CaptureFakeRunner(),
      );
      addTearDown(recording.dispose);

      var calls = 0;
      recording.onCaptureStarted = () => calls++;
      await recording.start('t.wav');
      // 레벨 줄이 여러 번 와도 알림은 한 번이다.
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(calls, 1);
    });

    test('콜백을 안 걸어도 녹음은 정상으로 돈다', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final recording = RecordingController(
        pathBuilder: (name) async => name,
        runner: _CaptureFakeRunner(),
      );
      addTearDown(recording.dispose);

      expect(await recording.start('t.wav'), 't.wav');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(recording.isRecording, isTrue);
    });
  });
}

/// 장치 목록 시나리오용 러너 — start()는 ffmpeg -list_devices 출력을,
/// run()은 locate(where·-version)에 성공 응답을 흉내 낸다.
/// 장치 목록 + 녹음 캡처를 둘 다 흉내낸다. 녹음 쪽은 astats 줄을 흘려
/// 「장치가 열렸다」를 재현한다.
class _CaptureFakeRunner implements ProcessRunner {
  @override
  JobHandle start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) {
    final controller = StreamController<String>();
    if (arguments.contains('-list_devices')) {
      controller.add('[in#0 @ 0x1] "마이크(RØDE NT-USB Mini)" (audio)');
      final closed = controller.close();
      return JobHandle(
        lines: controller.stream,
        exitCode: closed.then((_) => 1),
        cancel: () {},
      );
    }
    // 캡처 — 레벨 줄을 여러 번 흘린다. 첫 줄에서만 콜백이 나와야 한다.
    for (var i = 0; i < 3; i++) {
      controller.add('lavfi.astats.Overall.RMS_level=-21.0');
    }
    final done = Completer<int>();
    return JobHandle(
      lines: controller.stream,
      exitCode: done.future,
      cancel: () {
        if (!done.isCompleted) done.complete(0);
      },
    );
  }

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async =>
      const ProcessOutput(exitCode: 0, stdout: 'ffmpeg', stderr: '');
}

class _DeviceListFakeRunner implements ProcessRunner {
  @override
  JobHandle start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) {
    final controller = StreamController<String>();
    controller.add('[in#0 @ 0x1] "마이크(RØDE NT-USB Mini)" (audio)');
    controller.add('[in#0 @ 0x1] "MAIN L/R(BEHRINGER FLOW 8)" (audio)');
    final closed = controller.close();
    return JobHandle(
      lines: controller.stream,
      // 실제 러너처럼 스트림이 다 흐른 뒤에 종료 코드를 준다.
      exitCode: closed.then((_) => 1),
      cancel: () {},
    );
  }

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    // locate(): where/-version 조회는 전부 성공으로 응답한다.
    return const ProcessOutput(
      exitCode: 0,
      stdout: 'ffmpeg',
      stderr: '',
    );
  }
}
