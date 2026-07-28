import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/utils/wheel_step_accumulator.dart';

// 트랙패드의 미세 델타로 가사가 수십 줄씩 넘어가지 않게 하는 규칙.
// 마우스 휠은 "한 칸 = 한 줄"이어야 한다.
void main() {
  group('마우스 휠 (한 이벤트가 임계값을 넘김)', () {
    test('한 칸(120)은 정확히 한 줄', () {
      final acc = WheelStepAccumulator();
      expect(acc.consume(120), 1);
    });

    test('연속으로 굴려도 매번 한 줄 — 잔여가 쌓여 밀리지 않는다', () {
      final acc = WheelStepAccumulator();
      for (var i = 0; i < 10; i++) {
        expect(acc.consume(120), 1, reason: '$i번째 칸');
      }
    });

    test('위로 굴리면 음수', () {
      final acc = WheelStepAccumulator();
      expect(acc.consume(-120), -1);
      expect(acc.consume(-120), -1);
    });

    test('아주 크게 굴리면 여러 줄', () {
      final acc = WheelStepAccumulator();
      expect(acc.consume(350), 3);
    });
  });

  group('트랙패드 (잘게 쪼갠 델타)', () {
    test('임계값에 못 미치면 0', () {
      final acc = WheelStepAccumulator();
      expect(acc.consume(20), 0);
      expect(acc.consume(20), 0);
      expect(acc.consume(20), 0);
    });

    test('모이면 한 줄, 남은 만큼은 이월된다', () {
      final acc = WheelStepAccumulator();
      expect(acc.consume(60), 0);
      expect(acc.consume(60), 1); // 120 → 1줄, 20 이월
      expect(acc.consume(60), 0); // 80
      expect(acc.consume(30), 1); // 110 → 1줄
    });

    test('방향을 바꾸면 잔여분이 상쇄된다', () {
      final acc = WheelStepAccumulator();
      expect(acc.consume(80), 0);
      expect(acc.consume(-80), 0);
      expect(acc.consume(90), 0);
    });
  });

  test('0 델타는 아무 일도 하지 않는다', () {
    final acc = WheelStepAccumulator();
    acc.consume(90);
    expect(acc.consume(0), 0);
    expect(acc.consume(20), 1);
  });

  test('reset은 누적을 버린다', () {
    final acc = WheelStepAccumulator();
    acc.consume(90);
    acc.reset();
    expect(acc.consume(90), 0);
  });

  test('임계값을 바꿀 수 있다', () {
    final acc = WheelStepAccumulator(threshold: 200);
    expect(acc.consume(120), 0);
    expect(acc.consume(120), 1);
  });
}
