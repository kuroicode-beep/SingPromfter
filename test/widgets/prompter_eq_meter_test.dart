import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/widgets/prompter_eq_meter.dart';

// EQ 미터의 스무딩·피크홀드 순수 규칙.
void main() {
  group('smoothLevel', () {
    test('어택은 즉시 따라간다', () {
      expect(smoothLevel(0.2, 0.9), 0.9);
    });

    test('릴리즈는 점진적으로 내려간다', () {
      final next = smoothLevel(1.0, 0.0);
      expect(next, lessThan(1.0));
      expect(next, greaterThan(0.0));
    });

    test('릴리즈가 목표 아래로 내려가지 않는다', () {
      var level = 1.0;
      for (var i = 0; i < 1000; i++) {
        level = smoothLevel(level, 0.3);
      }
      expect(level, closeTo(0.3, 0.02));
      expect(level, greaterThanOrEqualTo(0.3));
    });
  });

  group('holdPeak', () {
    test('새 값이 크면 즉시 갱신한다', () {
      expect(holdPeak(0.4, 0.8), 0.8);
    });

    test('느리게 낙하한다', () {
      final next = holdPeak(0.8, 0.1);
      expect(next, lessThan(0.8));
      expect(next, greaterThan(0.7));
    });

    test('현재 막대 아래로는 떨어지지 않는다', () {
      var peak = 1.0;
      for (var i = 0; i < 1000; i++) {
        peak = holdPeak(peak, 0.5);
      }
      expect(peak, greaterThanOrEqualTo(0.5));
      expect(peak, closeTo(0.5, 0.02));
    });
  });

  // 간격이 막대를 잡아먹지 않아야 밴드를 늘린 보람이 있다.
  group('eqBarMetrics', () {
    test('밴드가 늘어도 막대가 간격보다 두껍다', () {
      for (final count in [6, 12, 24, 32, 48]) {
        final m = eqBarMetrics(520, count);
        expect(m.barWidth, greaterThan(m.gap), reason: '$count밴드');
      }
    });

    test('막대+간격이 주어진 폭을 넘지 않는다', () {
      for (final width in [160.0, 420.0, 520.0]) {
        for (final count in [6, 24, 48]) {
          final m = eqBarMetrics(width, count);
          final total = m.barWidth * count + m.gap * (count - 1);
          expect(total, lessThanOrEqualTo(width + 0.001),
              reason: '$width/$count밴드');
        }
      }
    });

    test('좁은 화면에서도 막대가 최소 1px은 된다', () {
      expect(eqBarMetrics(160, 48).barWidth, greaterThanOrEqualTo(1.0));
    });

    test('6밴드일 때는 예전과 비슷한 굵기를 유지한다', () {
      final m = eqBarMetrics(520, 6);
      expect(m.barWidth, greaterThan(70));
    });

    test('밴드가 없거나 폭이 0이면 0', () {
      expect(eqBarMetrics(520, 0).barWidth, 0);
      expect(eqBarMetrics(0, 24).barWidth, 0);
    });

    test('밴드가 하나면 폭 전체를 쓴다', () {
      final m = eqBarMetrics(520, 1);
      expect(m.barWidth, 520);
      expect(m.gap, 0);
    });
  });
}
