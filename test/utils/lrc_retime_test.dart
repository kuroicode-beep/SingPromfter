import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/services/lyrics_align_service.dart';
import 'package:singpromfter_app/utils/lrc_retime.dart';

// LRC 재타이밍(t' = scale·t + offset)과 드리프트 회귀.
//
// 배경: 속도가 다른 판본의 LRC는 어긋남이 직선으로 커진다
// (실측 「넌 언제나」: +640ms → +3740ms). 오프셋 하나로는 못 맞추지만
// scale·offset 두 값으로는 전 구간을 맞출 수 있다.
void main() {
  group('retimeLrcContent', () {
    test('타임스탬프를 선형으로 다시 쓴다', () {
      const raw = '[00:10.00]첫 줄\n[01:00.00]둘째 줄';
      final out = retimeLrcContent(raw, scale: 1.02, offsetMs: 500);
      // 10000×1.02+500 = 10700 / 60000×1.02+500 = 61700
      expect(out, contains('[00:10.70]첫 줄'));
      expect(out, contains('[01:01.70]둘째 줄'));
    });

    test('가사 텍스트와 메타 태그는 건드리지 않는다', () {
      const raw = '[ti:노래]\n[00:10.00]첫 줄';
      final out = retimeLrcContent(raw, scale: 1.0, offsetMs: 0);
      expect(out, contains('[ti:노래]'));
      expect(out, contains('첫 줄'));
    });

    test('[offset:] 태그는 계산에 반영한 뒤 제거한다 — 이중 적용 방지', () {
      const raw = '[offset:1000]\n[00:10.00]첫 줄';
      final out = retimeLrcContent(raw, scale: 1.0, offsetMs: 0);
      // 표시 시각 11초가 타임스탬프에 구워진다.
      expect(out, contains('[00:11.00]첫 줄'));
      expect(out, isNot(contains('offset')));
    });

    test('음수가 되는 시각은 0으로 막는다', () {
      const raw = '[00:01.00]첫 줄';
      final out = retimeLrcContent(raw, scale: 1.0, offsetMs: -5000);
      expect(out, contains('[00:00.00]첫 줄'));
    });

    test('한 줄에 여러 타임스탬프가 있어도 전부 바꾼다', () {
      const raw = '[00:10.00][00:50.00]후렴';
      final out = retimeLrcContent(raw, scale: 1.0, offsetMs: 1000);
      expect(out, contains('[00:11.00][00:51.00]후렴'));
    });
  });

  group('fitLinearDrift', () {
    test('직선 표본에서 scale·offset을 되찾는다', () {
      // y = 1.025x + 400 (실측과 같은 자릿수)
      final samples = [
        for (final x in [20000, 60000, 100000, 140000])
          (x: x, y: (1.025 * x + 400).round()),
      ];
      final fit = fitLinearDrift(samples);
      expect(fit, isNotNull);
      expect(fit!.scale, closeTo(1.025, 0.001));
      expect(fit.offsetMs, closeTo(400, 50));
      expect(fit.r2, greaterThan(0.999));
    });

    test('직선이 아니면 r2가 낮다', () {
      final fit = fitLinearDrift([
        (x: 10000, y: 12000),
        (x: 20000, y: 15000),
        (x: 30000, y: 60000),
        (x: 40000, y: 30000),
      ]);
      expect(fit, isNotNull);
      expect(fit!.r2, lessThan(0.95));
    });

    test('표본 2개 미만이거나 x가 안 퍼져 있으면 null', () {
      expect(fitLinearDrift([(x: 1, y: 1)]), isNull);
      expect(fitLinearDrift([(x: 5, y: 1), (x: 5, y: 9)]), isNull);
    });
  });
}
