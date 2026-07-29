import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/utils/wheel_step_accumulator.dart';

// 휠 한 칸 = 한 줄이어야 한다. 플랫폼마다 노치 델타가 달라(윈도우 ~53,
// 다른 곳 100~120) 고정 임계값을 쓰면 환경에 따라 몇 줄씩 건너뛴다.
void main() {
  group('마우스 휠 — 델타 크기와 무관하게 한 칸', () {
    test('윈도우 노치(53)도 한 칸', () {
      final acc = WheelStepAccumulator();
      expect(acc.consume(53), 1);
      expect(acc.consume(53), 1);
      expect(acc.consume(53), 1);
    });

    test('다른 플랫폼 노치(120)도 똑같이 한 칸', () {
      final acc = WheelStepAccumulator();
      expect(acc.consume(120), 1);
      expect(acc.consume(120), 1);
    });

    test('아주 큰 델타도 한 칸 — 여러 줄 건너뛰지 않는다', () {
      final acc = WheelStepAccumulator();
      expect(acc.consume(400), 1);
    });

    test('위로 굴리면 음수', () {
      final acc = WheelStepAccumulator();
      expect(acc.consume(-53), -1);
      expect(acc.consume(-120), -1);
    });

    test('마우스 노치는 잔여를 남기지 않는다', () {
      final acc = WheelStepAccumulator();
      acc.consume(20); // 트랙패드 누적 20
      expect(acc.consume(53), 1); // 노치 → 누적 초기화
      expect(acc.consume(20), 0); // 남은 게 없으니 아직 0
      expect(acc.consume(20), 1); // 40 모여야 한 칸
    });

    test('노치 경계(40)는 마우스로 본다', () {
      final acc = WheelStepAccumulator();
      expect(acc.consume(40), 1);
      expect(acc.consume(39), 0); // 경계 미만은 트랙패드로 누적
    });
  });

  group('트랙패드 — 잘게 오는 델타는 모아서', () {
    test('임계값에 못 미치면 0', () {
      final acc = WheelStepAccumulator();
      expect(acc.consume(10), 0);
      expect(acc.consume(5), 0);
    });

    test('모이면 한 칸, 나머지는 이월', () {
      final acc = WheelStepAccumulator();
      expect(acc.consume(15), 0);
      expect(acc.consume(15), 0);
      expect(acc.consume(15), 1); // 45 → 1칸, 5 이월
      expect(acc.consume(15), 0); // 20
      expect(acc.consume(15), 0); // 35
      expect(acc.consume(10), 1); // 45
    });

    test('방향을 바꾸면 상쇄된다', () {
      final acc = WheelStepAccumulator();
      expect(acc.consume(15), 0);
      expect(acc.consume(-15), 0);
      expect(acc.consume(-15), 0);
    });
  });

  test('0 델타는 아무 일도 하지 않는다', () {
    final acc = WheelStepAccumulator();
    expect(acc.consume(0), 0);
  });

  test('reset은 누적을 버린다 — 모드 전환 시 잔여가 새지 않게', () {
    final acc = WheelStepAccumulator();
    expect(acc.consume(35), 0); // 누적만 됨
    acc.reset();
    expect(acc.consume(35), 0, reason: '버려졌으니 아직 한 칸이 안 된다');
  });
}
