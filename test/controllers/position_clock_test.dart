import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/controllers/position_clock.dart';

void main() {
  // 실제 시간에 의존하지 않도록 경과시간 소스를 주입한다.
  late Duration fakeElapsed;
  PositionClock build() =>
      PositionClock(elapsedSource: () => fakeElapsed);

  setUp(() => fakeElapsed = Duration.zero);

  test('정지 상태에서는 경과시간이 흘러도 위치가 고정된다', () {
    final clock = build();
    clock.anchor(const Duration(seconds: 5));

    fakeElapsed += const Duration(seconds: 3);

    expect(clock.value, const Duration(seconds: 5));
  });

  test('start 후에는 경과시간만큼 위치가 보간된다', () {
    final clock = build()..anchor(const Duration(seconds: 10));
    clock.start();

    fakeElapsed += const Duration(milliseconds: 400);

    expect(clock.value, const Duration(milliseconds: 10400));
  });

  test('배속을 반영해 보간한다', () {
    final clock = build()..anchor(Duration.zero);
    clock.start();
    clock.setRate(2);

    fakeElapsed += const Duration(seconds: 1);

    expect(clock.value, const Duration(seconds: 2));
  });

  test('setRate는 그때까지의 진행분을 확정한 뒤 새 배속을 적용한다', () {
    final clock = build()..anchor(Duration.zero);
    clock.start();

    fakeElapsed += const Duration(seconds: 2); // 1배속으로 2초
    clock.setRate(2);
    fakeElapsed += const Duration(seconds: 1); // 2배속으로 1초 → +2초

    expect(clock.value, const Duration(seconds: 4));
  });

  test('작은 오차는 즉시 맞추지 않고 일부만 당긴다', () {
    final clock = build()..anchor(Duration.zero);
    clock.start();

    fakeElapsed += const Duration(milliseconds: 1000);
    // 현재 1000ms인데 네이티브가 1100ms를 알려옴 → 차이 100ms(임계값 미만)
    clock.resync(const Duration(milliseconds: 1100));

    // 25%만 반영 → 1025ms
    expect(clock.value, const Duration(milliseconds: 1025));
  });

  test('임계값(250ms) 이상 어긋나면 즉시 스냅한다', () {
    final clock = build()..anchor(Duration.zero);
    clock.start();

    fakeElapsed += const Duration(milliseconds: 1000);
    clock.resync(const Duration(milliseconds: 5000)); // 탐색으로 간주

    expect(clock.value, const Duration(milliseconds: 5000));
  });

  test('정지 중 resync는 그대로 앵커링한다', () {
    final clock = build();
    clock.resync(const Duration(seconds: 7));

    expect(clock.value, const Duration(seconds: 7));
    expect(clock.isRunning, isFalse);
  });

  test('pause는 현재 위치를 유지하고 이후 진행을 멈춘다', () {
    final clock = build()..anchor(Duration.zero);
    clock.start();

    fakeElapsed += const Duration(seconds: 3);
    clock.pause();
    fakeElapsed += const Duration(seconds: 10);

    expect(clock.value, const Duration(seconds: 3));
    expect(clock.isRunning, isFalse);
  });

  test('pause 후 start하면 멈춘 지점부터 이어간다', () {
    final clock = build()..anchor(Duration.zero);
    clock.start();
    fakeElapsed += const Duration(seconds: 3);
    clock.pause();

    fakeElapsed += const Duration(seconds: 10); // 멈춰 있는 동안
    clock.start();
    fakeElapsed += const Duration(seconds: 2);

    expect(clock.value, const Duration(seconds: 5));
  });

  test('reset은 0으로 되돌리고 정지한다', () {
    final clock = build()..anchor(const Duration(seconds: 9));
    clock.start();
    clock.reset();

    expect(clock.value, Duration.zero);
    expect(clock.isRunning, isFalse);
  });

  test('음수 위치는 0으로 막는다', () {
    final clock = build()..anchor(const Duration(seconds: -5));
    expect(clock.value, Duration.zero);
  });

  test('setRate에 0 이하를 주면 무시한다', () {
    final clock = build();
    clock.setRate(0);
    clock.setRate(-1);
    expect(clock.rate, 1);
  });

  test('progressRatio는 0~1로 제한한다', () {
    expect(
      progressRatio(const Duration(seconds: 30), const Duration(seconds: 60)),
      0.5,
    );
    expect(
      progressRatio(const Duration(seconds: 90), const Duration(seconds: 60)),
      1,
    );
    expect(progressRatio(const Duration(seconds: 30), Duration.zero), 0);
  });
}
