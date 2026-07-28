// file: lib/utils/wheel_step_accumulator.dart
//
// 마우스 휠 델타를 "몇 칸 움직였는가"로 바꾼다. (순수 클래스 — 테스트 대상)
//
// 트랙패드는 한 번 밀 때 아주 작은 델타를 여러 번 보낸다. 그대로 쓰면
// 가사가 한 번에 수십 줄씩 넘어가므로, 임계값만큼 모였을 때만 한 칸 센다.
// 남은 델타는 버리지 않고 다음 이벤트로 이월한다.
class WheelStepAccumulator {
  /// 한 칸으로 셀 누적 델타(논리 픽셀).
  /// 마우스 휠 한 칸이 보통 100~120이라 그 언저리로 잡아 "한 칸 = 한 줄"이 된다.
  static const double defaultThreshold = 100;

  final double threshold;
  double _accumulated = 0;

  WheelStepAccumulator({this.threshold = defaultThreshold});

  /// 델타를 넣고 이번에 움직일 칸 수를 받는다. 모자라면 0.
  int consume(double delta) {
    if (delta == 0) return 0;
    _accumulated += delta;
    final steps = (_accumulated / threshold).truncate();
    if (steps == 0) return 0;

    if (delta.abs() >= threshold) {
      // 이벤트 하나가 임계값을 넘겼으면 마우스 휠을 딸깍 굴린 것으로 본다.
      // 잔여를 이월하면 몇 칸마다 한 줄씩 더 밀리므로 여기서 버린다.
      _accumulated = 0;
    } else {
      // 트랙패드처럼 잘게 쪼갠 델타는 이월해야 한 칸이 완성된다.
      _accumulated -= steps * threshold;
    }
    return steps;
  }

  void reset() => _accumulated = 0;
}
