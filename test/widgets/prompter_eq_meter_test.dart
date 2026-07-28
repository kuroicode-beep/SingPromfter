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
}
