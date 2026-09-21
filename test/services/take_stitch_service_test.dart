// file: test/services/take_stitch_service_test.dart
//
// 조각 이어붙이기의 좌표 계산과 ffmpeg 인자. 귀로 맞추는 일이 아니라
// 계산이어야 하므로, 이음새가 어디로 가는지를 숫자로 고정해 둔다.
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/services/take_stitch_service.dart';

StitchSegment seg(
  int posMs,
  int durMs, {
  String path = 'v.wav',
  int lead = 0,
}) => StitchSegment(
  vocalPath: path,
  songPositionMs: posMs,
  durationMs: durMs,
  contentOffsetMs: lead,
);

void main() {
  group('parseFirstSoundMs — 리드인 무음 재기', () {
    test('맨 앞이 무음이면 소리가 나는 지점을 돌려준다', () {
      const out = '''
[silencedetect @ 0000] silence_start: 0
[silencedetect @ 0000] silence_end: 3.58 | silence_duration: 3.58
''';
      expect(parseFirstSoundMs(out), 3580);
    });

    test('맨 앞부터 소리가 있으면 리드인이 없다', () {
      const out = '[silencedetect @ 0000] silence_start: 4.2';
      expect(parseFirstSoundMs(out), 0);
    });

    test('무음 구간 자체가 없으면 0', () {
      expect(parseFirstSoundMs('아무것도 없음'), 0);
    });

    test('중간 무음만 있으면 리드인으로 보지 않는다', () {
      const out = '''
[silencedetect @ 0000] silence_start: 2.5
[silencedetect @ 0000] silence_end: 3.1 | silence_duration: 0.6
''';
      expect(parseFirstSoundMs(out), 0);
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
