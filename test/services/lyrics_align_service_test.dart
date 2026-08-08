import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/timed_lyrics.dart';
import 'package:singpromfter_app/services/lyrics_align_service.dart';

// 가사 싱크 자동 맞춤.
//
// v2.8.1은 원곡에서 MR을 위상 반전으로 빼 보컬만 남기려 했는데, 실측에서
// 두 파일이 정렬돼 있지 않아 상쇄가 전혀 안 됐다. 지금은 포락선끼리 뺀다.
// 그리고 "앞이 조용했던 줄"만 쓴다 — 노래가 이어지는 구간에서는 줄 시작을
// 소리만으로 찾을 수 없고, 가드가 없으면 탐색 창 시작점을 시작점으로 착각한다.
void main() {
  const fps = alignFps;

  /// 보컬이 [spans]구간(ms)에만 있는 존재도 신호를 만든다.
  /// 반주만: 0dB, 노래: 10dB.
  List<double> presenceWith(
    List<(int, int)> spans, {
    int lengthMs = 200000,
  }) {
    final frames = List<double>.filled(lengthMs * fps ~/ 1000, 0);
    for (final (start, end) in spans) {
      for (var i = start * fps ~/ 1000; i < end * fps ~/ 1000; i++) {
        if (i < frames.length) frames[i] = 10;
      }
    }
    return frames;
  }

  TimedLyrics lyricsAt(List<int> times) => TimedLyrics(
    lines: [
      for (final t in times)
        TimedLyricLine(time: Duration(milliseconds: t), text: '한 줄'),
    ],
  );

  group('buildEnvelopeArgs', () {
    test('사람 목소리 대역만 남긴다', () {
      final args = buildEnvelopeArgs('a.mp3');
      final chain = args[args.indexOf('-af') + 1];
      expect(chain, contains('highpass=f=$vocalLowHz'));
      expect(chain, contains('lowpass=f=$vocalHighHz'));
    });

    test('25fps를 유지한다', () {
      final args = buildEnvelopeArgs('a.mp3');
      expect(args[args.indexOf('-af') + 1], contains('asetnsamples=n=1764'));
    });

    test('입력 경로를 그대로 넘긴다', () {
      final args = buildEnvelopeArgs(r'C:\음악\원곡.mp3');
      expect(args[args.indexOf('-i') + 1], r'C:\음악\원곡.mp3');
    });
  });

  group('vocalPresence', () {
    test('원곡이 MR보다 큰 만큼을 준다', () {
      final p = vocalPresence(
        List.filled(10, -10),
        List.filled(10, -20),
      );
      expect(p.every((v) => (v - 10).abs() < 0.001), isTrue);
    });

    test('반주만인 구간은 0에 가깝다', () {
      final p = vocalPresence(List.filled(10, -17), List.filled(10, -17));
      expect(p.every((v) => v.abs() < 0.001), isTrue);
    });

    test('짧은 쪽 길이에 맞춘다', () {
      expect(vocalPresence(List.filled(10, 0), List.filled(4, 0)), hasLength(4));
    });

    test('빈 입력은 빈 결과', () {
      expect(vocalPresence(const [], const []), isEmpty);
    });

    test('한 프레임 튄 값은 이동평균으로 눌린다', () {
      final orig = List.filled(10, -20.0);
      orig[5] = 0; // 20dB 스파이크
      final p = vocalPresence(orig, List.filled(10, -20));
      expect(p[5], lessThan(20));
      expect(p[5], greaterThan(0));
    });
  });

  group('estimateLyricsOffset', () {
    test('일정하게 늦은 가사는 양수 오프셋을 준다', () {
      // 노래는 20·40·60·80초에 시작하고, LRC는 그보다 1초 이르다.
      final presence = presenceWith([
        (20000, 23000),
        (40000, 43000),
        (60000, 63000),
        (80000, 83000),
      ]);
      final outcome = estimateLyricsOffset(
        presence: presence,
        lyrics: lyricsAt([19000, 39000, 59000, 79000]),
      );
      expect(outcome.ok, isTrue);
      expect(outcome.result!.offsetMs, closeTo(1000, 120));
      expect(outcome.result!.samples, 4);
    });

    test('이미 맞는 곡은 0 근처', () {
      final presence = presenceWith([
        (20000, 23000),
        (40000, 43000),
        (60000, 63000),
        (80000, 83000),
      ]);
      final outcome = estimateLyricsOffset(
        presence: presence,
        lyrics: lyricsAt([20000, 40000, 60000, 80000]),
      );
      expect(outcome.result!.offsetMs.abs(), lessThan(120));
    });

    // v2.8.1의 실제 버그. 노래가 이어지면 줄마다 시작점을 찾을 수 없다.
    test('앞이 조용하지 않은 줄은 표본에서 뺀다', () {
      // 20~80초 내내 노래한다 — 시작점은 20초 하나뿐이다.
      final presence = presenceWith([(20000, 80000)]);
      final outcome = estimateLyricsOffset(
        presence: presence,
        lyrics: lyricsAt([19000, 30000, 40000, 50000, 60000, 70000]),
      );
      // 표본이 하나뿐이라 판정하지 않는다 — 억지로 값을 내지 않는다.
      expect(outcome.ok, isFalse);
      expect(outcome.failure, LyricsAlignFailure.notEnoughSamples);
    });

    test('여러 줄이 같은 시작점에 붙으면 첫 줄만 센다', () {
      final presence = presenceWith([
        (20000, 30000),
        (50000, 60000),
        (80000, 90000),
        (110000, 120000),
      ]);
      // 각 구간마다 줄이 둘씩 있지만 시작점은 하나뿐이다.
      final outcome = estimateLyricsOffset(
        presence: presence,
        lyrics: lyricsAt([
          19000, 24000, 49000, 54000, 79000, 84000, 109000, 114000,
        ]),
      );
      expect(outcome.result?.samples ?? 0, lessThanOrEqualTo(4));
    });

    // 실측 사례: LRC가 곡과 속도가 달라 어긋남이 +640ms → +3740ms로 커졌다.
    test('어긋남이 곡마다 커지면 한 값으로 맞추지 않는다', () {
      final presence = presenceWith([
        (20000, 23000),
        (60000, 63000),
        (100000, 103000),
        (140000, 143000),
      ]);
      // 점점 더 이르게 적힌 가사 — 드리프트.
      final outcome = estimateLyricsOffset(
        presence: presence,
        lyrics: lyricsAt([19700, 58800, 97800, 136800]),
      );
      expect(outcome.ok, isFalse);
      expect(outcome.failure, LyricsAlignFailure.inconsistent);
      expect(outcome.spreadMs, greaterThan(maxAlignSpreadMs));
      // 어긋남이 직선이므로 재타이밍 보정안이 함께 온다.
      expect(outcome.drift, isNotNull);
      expect(outcome.drift!.scale, greaterThan(1.0));
      expect(outcome.drift!.scale, lessThan(1.1));
      expect(outcome.drift!.r2, greaterThan(0.95));
    });

    test('신호가 없으면 판정하지 않는다', () {
      expect(
        estimateLyricsOffset(
          presence: const [],
          lyrics: lyricsAt([1000]),
        ).failure,
        LyricsAlignFailure.noSignal,
      );
    });

    test('가사가 없으면 판정하지 않는다', () {
      expect(
        estimateLyricsOffset(
          presence: presenceWith([(20000, 23000)]),
          lyrics: const TimedLyrics(lines: []),
        ).failure,
        LyricsAlignFailure.noSignal,
      );
    });

    test('LRC 자체 오프셋도 계산에 넣는다', () {
      final presence = presenceWith([
        (20000, 23000),
        (40000, 43000),
        (60000, 63000),
        (80000, 83000),
      ]);
      // [offset:1000]이 붙어 실제 표시 시각이 1초씩 밀린 가사.
      final outcome = estimateLyricsOffset(
        presence: presence,
        lyrics: TimedLyrics(
          lines: lyricsAt([19000, 39000, 59000, 79000]).lines,
          offsetMs: 1000,
        ),
      );
      expect(outcome.result!.offsetMs.abs(), lessThan(120));
    });
  });

  group('vocalThreshold', () {
    test('바닥과 봉우리 사이에 놓인다', () {
      final p = [...List.filled(50, 0.0), ...List.filled(50, 10.0)];
      final t = vocalThreshold(p);
      expect(t, greaterThan(0));
      expect(t, lessThan(10));
    });

    // 상위 85%를 봉우리로 쓰면 여기서 문턱이 0이 돼 전부 "보컬 있음"이 된다.
    test('노래가 드문 곡에서도 무너지지 않는다', () {
      final p = [...List.filled(94, 0.0), ...List.filled(6, 10.0)];
      final t = vocalThreshold(p);
      expect(t, greaterThan(minVocalGainDb - 0.01));
      expect(t, lessThan(10));
    });

    test('차이가 거의 없으면 최소 문턱을 지킨다', () {
      expect(vocalThreshold(List.filled(100, 3.0)), closeTo(3 + minVocalGainDb, 0.01));
    });

    test('빈 입력은 0', () {
      expect(vocalThreshold(const []), 0);
    });
  });
}
