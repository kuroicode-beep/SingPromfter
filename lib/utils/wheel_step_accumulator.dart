// file: lib/utils/wheel_step_accumulator.dart
//
// 마우스 휠 델타를 "몇 칸 움직였는가"로 바꾼다. (순수 클래스 — 테스트 대상)
//
// 플랫폼마다 휠 한 칸의 델타가 다르다(윈도우 임베더는 약 53, 다른 곳은 100~120).
// 고정 임계값을 쓰면 어떤 환경에서는 한 칸에 세 줄이 넘어가고 어떤 환경에서는
// 두 번 굴려야 한 줄이 넘어간다. 그래서 크기가 아니라 **이벤트 성격**으로 나눈다.
//
//   한 이벤트가 mouseNotchMin 이상  → 마우스를 딸깍 굴린 것 = 정확히 한 칸
//   그보다 작은 델타                → 트랙패드. trackpadThreshold까지 모아 한 칸
class WheelStepAccumulator {
  /// 이 이상이면 마우스 휠 한 칸으로 본다.
  /// 윈도우 노치가 약 53이라 그보다 낮게, 트랙패드의 한 번 밀기보다는 높게 잡는다.
  static const double mouseNotchMin = 40;

  /// 트랙패드처럼 잘게 오는 델타를 이만큼 모으면 한 칸.
  static const double trackpadThreshold = 40;

  final double notchMin;
  final double threshold;
  double _accumulated = 0;

  WheelStepAccumulator({
    this.notchMin = mouseNotchMin,
    this.threshold = trackpadThreshold,
  });

  /// 델타를 넣고 이번에 움직일 칸 수를 받는다. 모자라면 0.
  int consume(double delta) {
    if (delta == 0) return 0;

    if (delta.abs() >= notchMin) {
      // 마우스 한 칸 = 한 줄. 델타 크기가 얼마든 한 칸으로 고정해
      // 플랫폼에 따라 몇 줄씩 건너뛰는 일을 없앤다.
      // 빠르게 굴리면 이벤트 자체가 여러 번 오므로 여러 칸이 된다.
      _accumulated = 0;
      return delta > 0 ? 1 : -1;
    }

    _accumulated += delta;
    final steps = (_accumulated / threshold).truncate();
    if (steps == 0) return 0;
    _accumulated -= steps * threshold;
    return steps;
  }

  /// 누적을 버린다. 모드(일반/Ctrl/Alt)가 바뀔 때 반드시 불러
  /// 이전 모드의 잔여 델타가 새 모드에서 한 칸을 만들지 않게 한다.
  void reset() => _accumulated = 0;
}
