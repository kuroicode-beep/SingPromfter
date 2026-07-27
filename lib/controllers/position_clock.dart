// file: lib/controllers/position_clock.dart
//
// 재생 위치 보간기. Windows 네이티브 위치 이벤트는 약 4Hz(250ms)라
// 가사 싱크에 쓰기엔 거칠어, 이벤트 사이를 경과시간으로 메운다.
import 'dart:math' as math;

/// 네이티브 위치 이벤트 사이를 보간해 부드러운 재생 위치를 만든다.
///
/// 경과시간 소스를 주입받으므로 실제 시간 없이 단위 테스트할 수 있다.
class PositionClock {
  /// 이 값을 넘게 어긋나면 보정 대신 즉시 스냅한다(탐색·곡 전환으로 간주).
  static const Duration snapThreshold = Duration(milliseconds: 250);

  /// 작은 오차를 한 번에 흡수하지 않고 이 비율만큼만 당겨 티를 줄인다.
  static const double blendFactor = 0.25;

  final Stopwatch _stopwatch;
  final Duration Function()? _elapsedSource;

  Duration _anchor = Duration.zero;
  Duration _anchorElapsed = Duration.zero;
  double _rate = 1;
  bool _running = false;

  PositionClock({Duration Function()? elapsedSource, Stopwatch? stopwatch})
    : _elapsedSource = elapsedSource,
      _stopwatch = stopwatch ?? Stopwatch();

  bool get isRunning => _running;

  double get rate => _rate;

  Duration get _elapsed =>
      _elapsedSource?.call() ?? _stopwatch.elapsed;

  /// 보간된 현재 위치. 음수로 내려가지 않는다.
  Duration get value {
    if (!_running) return _anchor;
    final delta = _elapsed - _anchorElapsed;
    final scaled = Duration(
      microseconds: (delta.inMicroseconds * _rate).round(),
    );
    final result = _anchor + scaled;
    return result < Duration.zero ? Duration.zero : result;
  }

  /// 정확한 위치로 강제 설정한다. 탐색·재생 준비·정지 시 사용한다.
  void anchor(Duration exact) {
    _anchor = exact < Duration.zero ? Duration.zero : exact;
    _anchorElapsed = _elapsed;
  }

  /// 네이티브 위치 이벤트를 반영한다.
  ///
  /// 차이가 [snapThreshold]를 넘으면 즉시 맞추고,
  /// 그보다 작으면 [blendFactor]만큼만 당겨 사용자가 튐을 느끼지 않게 한다.
  void resync(Duration native) {
    if (!_running) {
      anchor(native);
      return;
    }

    final current = value;
    final diff = native - current;
    if (diff.abs() >= snapThreshold) {
      anchor(native);
      return;
    }

    final blended = Duration(
      microseconds: (diff.inMicroseconds * blendFactor).round(),
    );
    anchor(current + blended);
  }

  /// 배속을 반영한다. 호출하지 않으면 보간이 선형으로 어긋난다.
  void setRate(double rate) {
    if (rate <= 0) return;
    // 지금까지의 진행분을 확정한 뒤 새 배속을 적용한다.
    anchor(value);
    _rate = rate;
  }

  void start() {
    if (_running) return;
    _running = true;
    if (_elapsedSource == null && !_stopwatch.isRunning) {
      _stopwatch.start();
    }
    _anchorElapsed = _elapsed;
  }

  /// 진행을 멈추되 현재 위치는 유지한다.
  void pause() {
    if (!_running) return;
    _anchor = value;
    _running = false;
    _anchorElapsed = _elapsed;
  }

  /// 위치를 0으로 되돌리고 정지한다.
  void reset() {
    _anchor = Duration.zero;
    _anchorElapsed = _elapsed;
    _running = false;
  }

  /// 전체 길이를 알고 있을 때 위치를 범위 안으로 제한한다.
  Duration clampTo(Duration duration) {
    if (duration <= Duration.zero) return value;
    final current = value;
    return current > duration ? duration : current;
  }
}

/// 진행률(0~1)을 구한다. 길이를 모르면 0을 반환한다.
double progressRatio(Duration position, Duration duration) {
  if (duration <= Duration.zero) return 0;
  final ratio = position.inMicroseconds / duration.inMicroseconds;
  return math.min(1, math.max(0, ratio));
}
