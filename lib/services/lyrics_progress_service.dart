// file: lib/services/lyrics_progress_service.dart
//
// 재생 위치로부터 하이라이트할 가사 줄 번호를 계산한다.
//
// 기존에는 90ms 타이머가 무조건 한 줄씩 넘겨(≈11줄/초) 속도 슬라이더가
// 무시됐고, 같은 로직이 메인 패널과 전체화면에 중복 구현돼 서로 어긋났다.
// 위치 기반 순수 함수로 바꿔 두 문제를 구조적으로 없앤다.

/// 줄 번호와 그 줄 안에서의 진행률.
///
/// 예전에는 소수부를 [num.floor]로 버렸다. 그 소수부가 곧 "줄 안 어디쯤"이라
/// 싱크 가사가 없는 곡의 진행 표시에 그대로 쓸 수 있다.
class LineProgress {
  final int index;

  /// 0..1. 줄이 하나뿐이거나 진행이 멈춘 경우 0.
  final double fraction;

  const LineProgress(this.index, this.fraction);
}

/// 가사 줄 진행 계산.
class LyricsProgressService {
  LyricsProgressService._();

  /// 반주가 없어 길이를 모를 때 초당 넘어가는 줄 수. 약 6초에 한 줄.
  static const double fallbackLinesPerSecond = 0.166;

  /// 현재 하이라이트할 줄 번호(0-based)를 구한다.
  ///
  /// - [duration]을 알면 곡 전체에 줄을 고르게 배분한다.
  /// - [duration]을 모르면(가사 전용 곡) 경과 시간으로 진행한다.
  ///
  /// v2.8.0에서 speedLevel(가사 스크롤 속도 배수)을 없앴다. 속도는 이제 음악
  /// 템포 하나뿐이고, 가사는 언제나 곡 길이에 비례해 고르게 넘어간다.
  static int estimatedLineIndex({
    required Duration position,
    required Duration duration,
    required int lineCount,
  }) => estimatedLineProgress(
    position: position,
    duration: duration,
    lineCount: lineCount,
  ).index;

  /// [estimatedLineIndex]와 같은 계산이되, 줄 안 진행률까지 함께 준다.
  ///
  /// 마지막 줄에 닿아 인덱스가 클램프되면 진행률도 1.0으로 고정한다 —
  /// 그러지 않으면 곡이 끝날 때까지 소수부가 계속 커져 되돌아간다.
  static LineProgress estimatedLineProgress({
    required Duration position,
    required Duration duration,
    required int lineCount,
  }) {
    if (lineCount <= 1) return const LineProgress(0, 0);
    if (position <= Duration.zero) return const LineProgress(0, 0);

    final double rawIndex;
    if (duration > Duration.zero) {
      final ratio = position.inMicroseconds / duration.inMicroseconds;
      rawIndex = ratio * lineCount;
    } else {
      final seconds = position.inMicroseconds / Duration.microsecondsPerSecond;
      rawIndex = seconds * fallbackLinesPerSecond;
    }

    final floor = rawIndex.floor();
    if (floor >= lineCount - 1) return LineProgress(lineCount - 1, 1);
    if (floor < 0) return const LineProgress(0, 0);
    return LineProgress(floor, (rawIndex - floor).clamp(0.0, 1.0));
  }

  /// [estimatedLineIndex]의 역함수 — 그 줄이 시작되는 재생 위치.
  ///
  /// 싱크 가사가 없는 곡에서 줄을 클릭하거나 휠로 넘겼을 때 쓴다.
  /// 계산이 불가능하면(길이 모름·줄 1개) null을 준다.
  static Duration? positionForLineIndex({
    required int index,
    required Duration duration,
    required int lineCount,
  }) {
    if (lineCount <= 1) return null;
    if (duration <= Duration.zero) return null;
    if (index <= 0) return Duration.zero;

    final clamped = index.clamp(0, lineCount - 1);
    final ratio = clamped / lineCount;
    if (ratio >= 1) return duration;
    // floor 경계에서 한 줄 앞으로 밀리지 않도록 1ms 안쪽으로 들어간다.
    final micros = (duration.inMicroseconds * ratio).ceil() + 1000;
    return Duration(microseconds: micros.clamp(0, duration.inMicroseconds));
  }
}
