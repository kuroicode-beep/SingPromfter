// file: test/services/take_stitch_service_test.dart
//
// 조각 이어붙이기의 좌표 계산과 ffmpeg 인자. 귀로 맞추는 일이 아니라
// 계산이어야 하므로, 이음새가 어디로 가는지를 숫자로 고정해 둔다.
//
// 프로세스를 기다리는 테스트는 전부 plain test()다 — testWidgets의 가짜 시계
// 아래에서는 스트림이 영영 안 끝난다.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singpromfter_app/models/timed_lyrics.dart';
import 'package:singpromfter_app/services/lyrics_sync_math.dart';
import 'package:singpromfter_app/services/process/process_runner.dart';
import 'package:singpromfter_app/services/take_stitch_service.dart';

StitchSegment seg(
  int posMs,
  int durMs, {
  String path = 'v.wav',
  int lead = 0,
  int leadIn = 0,
  double? peak,
}) => StitchSegment(
  vocalPath: path,
  songPositionMs: posMs,
  durationMs: durMs,
  contentOffsetMs: lead,
  leadInMs: leadIn,
  peakDbfs: peak,
);

TimedLyrics lyricsAt(List<int> ms, {int offsetMs = 0}) => TimedLyrics(
  lines: [
    for (final t in ms)
      TimedLyricLine(
        time: Duration(milliseconds: t),
        text: '줄 $t',
      ),
  ],
  offsetMs: offsetMs,
);

void main() {
  group('parseSilenceScan — 리드인 무음 재기', () {
    test('맨 앞이 무음이면 소리가 나는 지점을 돌려준다', () {
      const out = '''
[silencedetect @ 0000] silence_start: 0
[silencedetect @ 0000] silence_end: 3.58 | silence_duration: 3.58
''';
      final scan = parseSilenceScan(out);
      expect(scan.soundAtStart, isFalse);
      expect(scan.firstSoundMs, 3580);
      expect(scan.isAllSilent, isFalse);
    });

    test('맨 앞부터 소리가 있으면 리드인이 없다', () {
      const out = '[silencedetect @ 0000] silence_start: 4.2';
      final scan = parseSilenceScan(out);
      expect(scan.soundAtStart, isTrue);
      expect(scan.firstSoundMs, 0);
    });

    test('무음 구간 자체가 없으면 맨 앞부터 소리다', () {
      final scan = parseSilenceScan('아무것도 없음');
      expect(scan.soundAtStart, isTrue);
      expect(scan.firstSoundMs, 0);
    });

    test('중간 무음만 있으면 리드인으로 보지 않는다', () {
      const out = '''
[silencedetect @ 0000] silence_start: 2.5
[silencedetect @ 0000] silence_end: 3.1 | silence_duration: 0.6
''';
      expect(parseSilenceScan(out).soundAtStart, isTrue);
    });

    test('끝까지 무음이면 EOF의 silence_end에 속지 않는다 (ffmpeg 8.1.1 실측 출력)', () {
      // 최신 ffmpeg는 끝까지 조용한 파일에서도 EOF에 silence_end를 찍는다.
      // 이 값만 보면 「2.0초에서 소리가 시작했다」로 읽힌다.
      const out = '''
[Parsed_silencedetect_0 @ 000001be] silence_start: 0
[Parsed_silencedetect_0 @ 000001be] silence_end: 2 | silence_duration: 2
[Parsed_volumedetect_1 @ 000001bf] mean_volume: -91.0 dB
[Parsed_volumedetect_1 @ 000001bf] max_volume: -91.0 dB
''';
      final scan = parseSilenceScan(out);
      expect(scan.isAllSilent, isTrue);
      expect(scan.firstSoundMs, isNull);
    });

    test('silence_end가 없으면 끝까지 무음이다 (EOF에 안 찍는 옛 ffmpeg)', () {
      const out = '[silencedetect @ 0000] silence_start: 0';
      expect(parseSilenceScan(out).isAllSilent, isTrue);
    });

    test('최대 음량이 -inf여도 무음으로 읽는다', () {
      const out = '[Parsed_volumedetect_1 @ 0] max_volume: -inf dB';
      expect(parseSilenceScan(out).isAllSilent, isTrue);
    });

    test('너무 짧아 무음 줄이 안 나와도 최대 음량으로 무음을 가린다', () {
      // silencedetect는 0.2초가 차야 줄을 낸다 — 0.19초짜리 무음에는 아무 줄도 없다.
      const out = '[Parsed_volumedetect_1 @ 0] max_volume: -78.3 dB';
      expect(parseSilenceScan(out).isAllSilent, isTrue);
    });

    test('소리가 있는 파일은 최대 음량 줄이 있어도 그대로 잰다', () {
      const out = '''
[Parsed_silencedetect_0 @ 0] silence_start: 0
[Parsed_silencedetect_0 @ 0] silence_end: 1.450021 | silence_duration: 1.450021
[Parsed_volumedetect_1 @ 0] max_volume: -6.0 dB
''';
      final scan = parseSilenceScan(out);
      expect(scan.isAllSilent, isFalse);
      expect(scan.firstSoundMs, 1450);
    });

    test('-ss 뒤의 살짝 음수인 시작도 맨 앞 무음이다', () {
      const out = '''
[silencedetect @ 0] silence_start: -0.00133
[silencedetect @ 0] silence_end: 0.8 | silence_duration: 0.80133
''';
      expect(parseSilenceScan(out).firstSoundMs, 800);
    });
  });

  group('buildSilenceDetectArgs — 어디서부터 잴지', () {
    test('건너뛰지 않으면 -ss가 없다', () {
      final args = buildSilenceDetectArgs('v.wav');
      expect(args, isNot(contains('-ss')));
      expect(args, containsAllInOrder(['-i', 'v.wav']));
      final filter = args[args.indexOf('-af') + 1];
      expect(filter, startsWith('silencedetect=noise=-40dB:d=0.2'));
      // 끝까지 무음인 파일을 가리려면 최대 음량이 함께 있어야 한다.
      expect(filter, endsWith(',volumedetect'));
    });

    test('건너뛸 때는 -ss가 -i 앞(입력 쪽)에 온다', () {
      // 출력 쪽 -ss면 필터가 파일 전체를 그대로 본다 — 건너뛴 효과가 없다.
      final args = buildSilenceDetectArgs('v.wav', skipMs: 550);
      expect(args, containsAllInOrder(['-ss', '0.550', '-i', 'v.wav']));
      expect(args.indexOf('-ss'), lessThan(args.indexOf('-i')));
    });

    test('stitchScanSkipMs — 리드인이 있을 때만 리드인 + 250ms', () {
      expect(stitchScanSkipMs(0), 0);
      expect(stitchScanSkipMs(300), 550);
      // 곡 앞머리에서 찍은 조각은 리드인이 300보다 짧다.
      expect(stitchScanSkipMs(85), 335);
    });
  });

  group('contentOffsetFromDetection — 세 갈래', () {
    test('① 건너뛴 자리에 이미 소리가 있으면 키를 누른 자리가 내용 시작', () {
      expect(
        contentOffsetFromDetection(
          leadInMs: 300,
          skipMs: 550,
          detectedAfterSkipMs: 0,
          soundAtSkip: true,
        ),
        300,
      );
      // 리드인이 없는 조각(R 녹음)은 예전처럼 0이다.
      expect(
        contentOffsetFromDetection(
          leadInMs: 0,
          skipMs: 0,
          detectedAfterSkipMs: 0,
          soundAtSkip: true,
        ),
        0,
      );
    });

    test('② 무음 뒤에 소리가 났으면 건너뛴 길이를 더해 파일 기준으로 되돌린다', () {
      expect(
        contentOffsetFromDetection(
          leadInMs: 300,
          skipMs: 550,
          detectedAfterSkipMs: 1450,
          soundAtSkip: false,
        ),
        2000,
      );
      expect(
        contentOffsetFromDetection(
          leadInMs: 0,
          skipMs: 0,
          detectedAfterSkipMs: 3580,
          soundAtSkip: false,
        ),
        3580,
      );
    });

    test('③ 끝까지 조용했으면 내용이 없다(null)', () {
      expect(
        contentOffsetFromDetection(
          leadInMs: 300,
          skipMs: 550,
          detectedAfterSkipMs: null,
          soundAtSkip: false,
        ),
        isNull,
      );
    });
  });

  group('stitchLineStartsMs — 줄 경계를 플레이어 축으로', () {
    test('lyricsOffsetMs=1800 — 줄 시작이 1800ms 뒤로 옮겨진다', () {
      final starts = stitchLineStartsMs(
        lyrics: lyricsAt([10000, 14000, 18000]),
        lyricsOffsetMs: 1800,
      );
      expect(starts, [11800, 15800, 19800]);
    });

    test('lyricsOffsetMs=1800 회귀 — 스냅이 맞는 줄을 잡는다', () {
      // 1.9초 간격의 두 줄. 화면에는 11.8초와 13.7초에 뜬다(플레이어 축).
      final lyrics = lyricsAt([10000, 11900]);
      // 가수는 첫 줄이 뜬 직후(11.85초)에 부르기 시작했다.
      const contentStart = 11850;

      // 옛 코드: LRC 원본 축 그대로. 11.85초에 가장 가까운 값이 **둘째 줄**의
      // LRC 시각(11.9초)이라 엉뚱한 줄로 50ms 늦게 끌려간다.
      final lrcAxis = [
        for (final l in lyrics.lines) l.time.inMilliseconds + lyrics.offsetMs,
      ];
      expect(snapToLineStart(contentStart, lrcAxis), 11900);

      // 고친 코드: 플레이어 축. 첫 줄이 실제로 뜨는 11.8초로 간다.
      final playerAxis = stitchLineStartsMs(
        lyrics: lyrics,
        lyricsOffsetMs: 1800,
      );
      expect(snapToLineStart(contentStart, playerAxis), 11800);
    });

    test('옛 축에서는 아예 못 잡던 경계도 잡는다', () {
      // 줄 간격이 넓으면 1800ms 어긋난 경계는 허용 오차(200ms) 밖이라 스냅이 안 됐다.
      final lyrics = lyricsAt([10000, 14000, 18000]);
      final lrcAxis = [for (final l in lyrics.lines) l.time.inMilliseconds];
      expect(snapToLineStart(15750, lrcAxis), 15750);
      expect(
        snapToLineStart(
          15750,
          stitchLineStartsMs(lyrics: lyrics, lyricsOffsetMs: 1800),
        ),
        15800,
      );
    });

    test('돌려준 시각은 그 줄이 화면에 뜨는 바로 그 순간이다', () {
      final lyrics = lyricsAt([10000, 14000, 18000], offsetMs: 120);
      final starts = stitchLineStartsMs(lyrics: lyrics, lyricsOffsetMs: 1800);
      for (var i = 0; i < starts.length; i++) {
        int indexAt(int playerMs) => lyrics.indexAt(
          LyricsSyncMath.songTimeFor(
            playerPosition: Duration(milliseconds: playerMs),
            lyricsOffsetMs: 1800,
          ),
        );
        expect(indexAt(starts[i]), i, reason: '줄 $i 경계에서 그 줄이 켜진다');
        if (i > 0) expect(indexAt(starts[i] - 1), i - 1);
      }
    });

    test('트림 시작과 템포도 재생 컨트롤러와 같은 식으로 옮긴다', () {
      // 0.8배 렌더는 1/0.8배 길다. 트림 시작(원본 축 2000ms)도 같이 늘어난다.
      final starts = stitchLineStartsMs(
        lyrics: lyricsAt([10000]),
        trackStartMs: 2000,
        lyricsOffsetMs: 1800,
        tempoScale: 0.8,
      );
      expect(starts, [(11800 / 0.8).round() + (2000 / 0.8).round()]);
    });

    test('가사가 없으면 빈 목록, 같은 자리로 뭉친 줄은 하나로', () {
      expect(stitchLineStartsMs(lyrics: lyricsAt(const [])), isEmpty);
      // 가사를 크게 당기면 앞 줄들이 0으로 막힌다 — 경계 하나로 합친다.
      final starts = stitchLineStartsMs(
        lyrics: lyricsAt([500, 900, 5000]),
        lyricsOffsetMs: -1000,
      );
      expect(starts, [0, 4000]);
    });

    test('이음새가 플레이어 축 줄 경계에 선다 (끝에서 끝까지)', () {
      final lines = stitchLineStartsMs(
        lyrics: lyricsAt([10000, 14000, 18000]),
        lyricsOffsetMs: 1800,
      );
      final spans = computeStitchSpans(
        segments: [
          seg(8000, 9000, path: 'a.wav', lead: 3760), // 내용 11760 → 11800
          seg(12000, 8000, path: 'b.wav', lead: 3850), // 내용 15850 → 15800
        ],
        lineStartsMs: lines,
      );
      expect(spans[0].startMs, 11800);
      expect(spans[0].endMs, 15800);
      expect(spans[1].startMs, 15800);
    });

    test('isSameStitchTimeline — 템포가 다르면 한 타임라인에 못 올린다', () {
      expect(isSameStitchTimeline(1.0, 1.0), isTrue);
      expect(isSameStitchTimeline(0.85, 0.85000001), isTrue);
      expect(isSameStitchTimeline(1.0, 0.95), isFalse);
    });
  });

  group('snapToLineStart — 줄 경계로 당기기', () {
    const lines = [120380, 122167, 123050];

    test('허용 오차 안이면 가장 가까운 줄 경계로 간다', () {
      expect(snapToLineStart(120420, lines), 120380);
      expect(snapToLineStart(123000, lines), 123050);
    });

    test('허용 오차 밖이면 잰 값을 그대로 믿는다', () {
      expect(snapToLineStart(121500, lines), 121500);
    });

    test('줄이 없으면 그대로', () {
      expect(snapToLineStart(999, const []), 999);
    });
  });

  group('computeStitchSpans — 이음새 계산', () {
    test('리드인이 앞 조각 줄을 덮어도 내용 시작점으로 갈린다', () {
      // 박을 타려고 2마디 앞에서 녹음을 걸었다. 조각 시작 위치만 보면
      // 두 조각이 같은 줄을 가리켜 앞 조각이 통째로 버려진다(초안의 결함).
      final spans = computeStitchSpans(
        segments: [
          seg(116800, 6700, path: 'a.wav', lead: 3580), // 내용 120380부터
          seg(119500, 7000, path: 'b.wav', lead: 3550), // 내용 123050부터
        ],
        lineStartsMs: const [120380, 122167, 123050, 124373],
      );
      expect(spans.length, 2);
      expect(spans[0].startMs, 120380);
      expect(spans[0].endMs, 123050); // 뒤 조각 내용이 시작하는 곳에서 넘긴다
      expect(spans[1].startMs, 123050);
      expect(spans[1].endMs, 126500); // 자기 녹음 끝까지
    });

    test('앞 조각의 꼬리는 다음 조각의 녹음 시작이 아니라 말 시작에서 끝난다', () {
      // 뒤 조각은 104.0초에 녹음을 걸고 3초 뒤(107.0초)에야 부르기 시작했다.
      // 녹음 시작에서 자르면 앞 조각의 104~107초 — 마지막 줄 — 가 통째로 사라진다.
      final spans = computeStitchSpans(
        segments: [
          seg(100000, 10000, path: 'a.wav'),
          seg(104000, 8000, path: 'b.wav', lead: 3000),
        ],
      );
      expect(spans[0].endMs, 107000);
      expect(spans[0].endMs, isNot(104000));
      expect(spans[1].startMs, 107000);
    });

    test('다음 조각의 말 시작이 스냅되면 앞 조각의 꼬리도 스냅된 자리에서 끝난다', () {
      final spans = computeStitchSpans(
        segments: [
          seg(100000, 10000, path: 'a.wav'),
          seg(104000, 8000, path: 'b.wav', lead: 3060), // 내용 107060
        ],
        lineStartsMs: const [107000],
      );
      expect(spans[0].endMs, 107000);
      expect(spans[1].startMs, 107000);
    });

    test('리드인이 없으면 조각 시작점이 그대로 내용 시작점', () {
      final spans = computeStitchSpans(
        segments: [
          seg(120000, 5000, path: 'a.wav'),
          seg(123000, 5000, path: 'b.wav'),
        ],
      );
      expect(spans[0].startMs, 120000);
      expect(spans[0].endMs, 123000);
      expect(spans[1].endMs, 128000);
    });

    test('조각이 다음 조각까지 못 닿으면 자기 끝에서 멈춘다', () {
      final spans = computeStitchSpans(
        segments: [
          seg(120000, 2000, path: 'a.wav'),
          seg(125000, 3000, path: 'b.wav'),
        ],
      );
      // 없는 소리를 지어내 늘이지 않는다.
      expect(spans[0].endMs, 122000);
      expect(spans[1].startMs, 125000);
    });

    test('같은 자리를 다시 녹음하면 나중 것만 남는다', () {
      final spans = computeStitchSpans(
        segments: [
          seg(120000, 1000, path: 'a.wav'),
          seg(120000, 5000, path: 'b.wav'),
        ],
      );
      expect(spans.length, 1);
      expect(spans.single.segment.vocalPath, 'b.wav');
    });

    test('순서가 뒤섞여 들어와도 내용 시작 순으로 잇는다', () {
      final spans = computeStitchSpans(
        segments: [
          seg(126000, 4000, path: 'c.wav'),
          seg(120000, 4000, path: 'a.wav'),
        ],
      );
      expect(spans.map((s) => s.segment.vocalPath), ['a.wav', 'c.wav']);
    });

    test('조각이 없거나 하나면 빈 결과·한 구간', () {
      expect(computeStitchSpans(segments: const []), isEmpty);
      expect(computeStitchSpans(segments: [seg(0, 1000)]).length, 1);
    });
  });

  group('스냅은 조각 자기 시작보다 앞으로 가지 않는다', () {
    test('줄 경계가 조각 시작보다 앞이면 조각 시작에서 막는다', () {
      // 박보다 120ms 늦게 녹음을 걸고 곧바로 불렀다. 줄 경계(119880)에는 이 조각의
      // 소리가 없다 — 거기로 스냅하면 파일 오프셋이 -120ms가 된다.
      final s = seg(120000, 5000, path: 'a.wav', lead: 30);
      expect(snapToLineStart(s.contentStartMs, const [119880]), 119880);
      expect(snappedContentStartMs(s, const [119880]), 120000);
    });

    test('조각 안쪽으로 가는 스냅은 그대로 둔다', () {
      final s = seg(120000, 5000, path: 'a.wav', lead: 400);
      expect(snappedContentStartMs(s, const [120300]), 120300);
    });

    test('computeStitchSpans의 어느 구간도 파일 오프셋이 음수가 아니다', () {
      final spans = computeStitchSpans(
        segments: [
          seg(120000, 5000, path: 'a.wav', lead: 30),
          seg(124000, 5000, path: 'b.wav', lead: 50),
        ],
        lineStartsMs: const [119880, 123900],
      );
      expect(spans.length, 2);
      for (final span in spans) {
        expect(
          span.startMs,
          greaterThanOrEqualTo(span.segment.songPositionMs),
          reason: '${span.segment.vocalPath}의 시작이 자기 녹음보다 앞이다',
        );
      }
      // 앞 조각의 꼬리도 막힌 자리(뒤 조각의 시작)에서 끝난다.
      expect(spans[0].endMs, 124000);

      final args = buildStitchArgs(spans: spans, outputPath: 'o.wav');
      final f = args[args.indexOf('-filter_complex') + 1];
      expect(f, isNot(contains('start=-')));
      expect(f, contains('adelay=120000:all=1'));
      expect(f, contains('adelay=124000:all=1'));
    });

    test('buildStitchArgs — 앞으로 삐져나온 구간을 받아도 조각 시작에서 막는다', () {
      // 손으로 만든 구간. 막지 않으면 atrim=start=-0.120 · adelay=119880 —
      // 조각이 120ms 일찍 놓여 박이 어긋난다.
      final s = seg(120000, 5000, path: 'a.wav');
      final args = buildStitchArgs(
        spans: [
          StitchSpan(segment: s, startMs: 119880, endMs: 123000),
          StitchSpan(
            segment: seg(123000, 2000, path: 'b.wav'),
            startMs: 123000,
            endMs: 125000,
          ),
        ],
        outputPath: 'o.wav',
      );
      final f = args[args.indexOf('-filter_complex') + 1];
      expect(f, contains('[0:a]atrim=start=0.000:end=3.000'));
      expect(f, contains('adelay=120000:all=1[s0]'));
      // 페이드아웃 자리도 줄어든 길이(3.0초) 기준이다.
      expect(f, contains('afade=t=out:st=2.970'));
      expect(f, isNot(contains('start=-')));
    });
  });

  group('withDetectedOffsets — 무음 제외·리드인 건너뛰기 (가짜 러너)', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    const soundAfter1450 = [
      '[silencedetect @ 0] silence_start: 0',
      '[silencedetect @ 0] silence_end: 1.45 | silence_duration: 1.45',
      '[Parsed_volumedetect_1 @ 0] max_volume: -6.0 dB',
    ];
    const allSilent = [
      '[silencedetect @ 0] silence_start: 0',
      '[silencedetect @ 0] silence_end: 2 | silence_duration: 2',
      '[Parsed_volumedetect_1 @ 0] max_volume: -91.0 dB',
    ];

    test('리드인이 있는 조각은 리드인 + 250ms부터 재고 파일 기준으로 되돌린다', () async {
      final runner = _ScanFakeRunner({'armed.wav': soundAfter1450});
      final out = await TakeStitchService(runner: runner).withDetectedOffsets([
        seg(100000, 4000, path: 'armed.wav', leadIn: 300, peak: -20),
      ]);

      expect(runner.scans.single, containsAllInOrder(['-ss', '0.550', '-i']));
      // 550(건너뜀) + 1450(그 뒤 첫 소리) = 파일 2000ms.
      expect(out.single.contentOffsetMs, 2000);
      expect(out.single.contentStartMs, 102000);
      // 좌표는 그대로 들고 간다.
      expect(out.single.leadInMs, 300);
      expect(out.single.peakDbfs, -20);
    });

    test('리드인이 없는 조각(R 녹음)은 맨 앞부터 잰다', () async {
      final runner = _ScanFakeRunner({'r.wav': soundAfter1450});
      final out = await TakeStitchService(
        runner: runner,
      ).withDetectedOffsets([seg(100000, 4000, path: 'r.wav')]);
      expect(runner.scans.single, isNot(contains('-ss')));
      expect(out.single.contentOffsetMs, 1450);
    });

    test('건너뛴 자리에 이미 소리가 있으면 키를 누른 자리가 내용 시작이다', () async {
      final runner = _ScanFakeRunner({
        'armed.wav': ['[Parsed_volumedetect_1 @ 0] max_volume: -3.0 dB'],
      });
      final out = await TakeStitchService(runner: runner).withDetectedOffsets([
        seg(100000, 4000, path: 'armed.wav', leadIn: 300),
      ]);
      expect(out.single.contentOffsetMs, 300);
    });

    test('잰 레벨이 디지털 무음이면 파일을 열지도 않고 뺀다', () async {
      final runner = _ScanFakeRunner({'ok.wav': soundAfter1450});
      final out = await TakeStitchService(runner: runner).withDetectedOffsets([
        seg(100000, 4000, path: 'dead.wav', peak: -100),
        seg(104000, 4000, path: 'ok.wav', peak: -18),
      ]);
      expect(out.map((s) => s.vocalPath), ['ok.wav']);
      expect(runner.scans.length, 1, reason: '무음 조각은 ffmpeg를 띄우지 않는다');
    });

    test('잰 레벨이 없는 옛 테이크는 파일 전체가 조용한지로 가린다', () async {
      final runner = _ScanFakeRunner({
        'old_dead.wav': allSilent,
        'old_ok.wav': soundAfter1450,
      });
      final out = await TakeStitchService(runner: runner).withDetectedOffsets([
        seg(100000, 2000, path: 'old_dead.wav'),
        seg(104000, 4000, path: 'old_ok.wav'),
      ]);
      expect(out.map((s) => s.vocalPath), ['old_ok.wav']);
      expect(runner.scans.length, 2);
    });

    test('레벨은 정상이어도 건너뛴 뒤로 끝까지 조용하면 이을 내용이 없다', () async {
      // 스페이스를 잘못 누르고 부르지 않은 조각 — 방 소음(-60dB대)은 디지털 무음이
      // 아니라서 레벨로는 안 걸린다.
      final runner = _ScanFakeRunner({'mispress.wav': allSilent});
      final out = await TakeStitchService(runner: runner).withDetectedOffsets([
        seg(100000, 2500, path: 'mispress.wav', leadIn: 300, peak: -58),
      ]);
      expect(out, isEmpty);
    });

    test('무음 조각을 빼면 앞 조각의 꼬리가 살아난다', () async {
      // a(100~110초) 뒤에 무음 조각(103~105초)이 끼고, b가 108초부터 부른다.
      final runner = _ScanFakeRunner({
        'a.wav': ['[Parsed_volumedetect_1 @ 0] max_volume: -5.0 dB'],
        'dead.wav': allSilent,
        'b.wav': ['[Parsed_volumedetect_1 @ 0] max_volume: -5.0 dB'],
      });
      final segments = [
        seg(100000, 10000, path: 'a.wav'),
        seg(103000, 2000, path: 'dead.wav'),
        seg(108000, 4000, path: 'b.wav'),
      ];

      // 예전 동작(무음 조각 포함, EOF의 silence_end = 내용 시작 105.0초):
      // a가 105초에서 끊기고 105~108초가 비었다.
      final before = computeStitchSpans(
        segments: [
          segments[0],
          segments[1].withContentOffset(2000),
          segments[2],
        ],
      );
      expect(before.first.endMs, 105000);

      final measured = await TakeStitchService(
        runner: runner,
      ).withDetectedOffsets(segments);
      final after = computeStitchSpans(segments: measured);
      expect(after.map((s) => s.segment.vocalPath), ['a.wav', 'b.wav']);
      expect(after.first.endMs, 108000);
    });

    test('건너뛸 자리가 조각 밖이면 재지 않고 키를 누른 자리로 둔다', () async {
      final runner = _ScanFakeRunner(const {});
      final out = await TakeStitchService(
        runner: runner,
      ).withDetectedOffsets([seg(100000, 540, path: 'tiny.wav', leadIn: 300)]);
      expect(runner.scans, isEmpty);
      expect(out.single.contentOffsetMs, 300);
    });
  });

  group('buildStitchArgs — ffmpeg 인자', () {
    List<String> args() => buildStitchArgs(
      spans: computeStitchSpans(
        segments: [
          seg(120000, 5000, path: 'a.wav'),
          seg(123000, 5000, path: 'b.wav'),
        ],
      ),
      outputPath: 'out.wav',
    );

    test('조각 수만큼 입력을 연다', () {
      final a = args();
      expect(a.where((x) => x == '-i').length, 2);
      expect(a, containsAllInOrder(['-i', 'a.wav']));
      expect(a, containsAllInOrder(['-i', 'b.wav']));
      expect(a.last, 'out.wav');
    });

    test('곡 시각을 파일 시각으로 되돌려 자른다', () {
      final a = args();
      final f = a[a.indexOf('-filter_complex') + 1];
      // 앞 조각: 곡 120.0~123.0 → 파일 0.0~3.0
      expect(f, contains('atrim=start=0.000:end=3.000'));
      // 뒤 조각: 곡 123.0~128.0 → 파일 0.0~5.0
      expect(f, contains('atrim=start=0.000:end=5.000'));
    });

    test('리드인이 있으면 그만큼 뒤에서 자른다', () {
      final a = buildStitchArgs(
        spans: computeStitchSpans(
          segments: [
            seg(116800, 6700, path: 'a.wav', lead: 3580),
            seg(119500, 7000, path: 'b.wav', lead: 3550),
          ],
          lineStartsMs: const [120380, 123050],
        ),
        outputPath: 'o.wav',
      );
      final f = a[a.indexOf('-filter_complex') + 1];
      // 뒤 조각: 곡 123.050 - 조각시작 119.500 = 파일 3.550부터
      expect(f, contains('atrim=start=3.550'));
    });

    test('각 조각을 곡 타임라인 위치로 민다', () {
      final a = args();
      final f = a[a.indexOf('-filter_complex') + 1];
      expect(f, contains('adelay=120000:all=1'));
      expect(f, contains('adelay=123000:all=1'));
    });

    test('이음새마다 페이드가 걸린다', () {
      final a = args();
      final f = a[a.indexOf('-filter_complex') + 1];
      expect(f, contains('afade=t=in:st=0:d=0.030'));
      expect(f, contains('afade=t=out:'));
    });

    test('조각 수가 늘어도 음량이 줄지 않는다', () {
      final a = args();
      final f = a[a.indexOf('-filter_complex') + 1];
      expect(f, contains('amix=inputs=2:normalize=0'));
    });

    test('구간이 짧으면 크로스페이드를 줄인다', () {
      // 50ms 구간에 30ms 페이드를 앞뒤로 걸면 구간을 덮어쓴다.
      final a = buildStitchArgs(
        spans: computeStitchSpans(
          segments: [
            seg(0, 50, path: 'a.wav'),
            seg(50, 500, path: 'b.wav'),
          ],
        ),
        outputPath: 'o.wav',
      );
      final f = a[a.indexOf('-filter_complex') + 1];
      expect(f, contains('afade=t=in:st=0:d=0.012'));
    });

    test('무손실 모노 48kHz로 쓴다', () {
      final a = args();
      expect(a[a.indexOf('-c:a') + 1], 'pcm_s16le');
      expect(a[a.indexOf('-ar') + 1], '48000');
      expect(a[a.indexOf('-ac') + 1], '1');
    });
  });
}

/// silencedetect를 흉내 내는 러너 — 경로별로 정해 둔 줄을 흘리고 끝낸다.
/// run()은 locate(where·-version)에 성공 응답을 준다.
class _ScanFakeRunner implements ProcessRunner {
  _ScanFakeRunner(this.outputs);

  /// 파일 경로 → 그 파일을 쟀을 때 흘릴 줄.
  final Map<String, List<String>> outputs;

  /// 띄운 스캔의 인자 목록(띄운 순서대로).
  final List<List<String>> scans = [];

  @override
  JobHandle start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) {
    scans.add(arguments);
    final path = arguments[arguments.indexOf('-i') + 1];
    final controller = StreamController<String>();
    (outputs[path] ?? const <String>[]).forEach(controller.add);
    final closed = controller.close();
    return JobHandle(
      lines: controller.stream,
      // 실제 러너처럼 줄이 다 흐른 뒤에 종료 코드를 준다.
      exitCode: closed.then((_) => 0),
      cancel: () {},
    );
  }

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async => const ProcessOutput(exitCode: 0, stdout: 'ffmpeg', stderr: '');
}
