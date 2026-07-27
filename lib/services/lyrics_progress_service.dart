// file: lib/services/lyrics_progress_service.dart
//
// 재생 위치로부터 하이라이트할 가사 줄 번호를 계산한다.
//
// 기존에는 90ms 타이머가 무조건 한 줄씩 넘겨(≈11줄/초) 속도 슬라이더가
// 무시됐고, 같은 로직이 메인 패널과 전체화면에 중복 구현돼 서로 어긋났다.
// 위치 기반 순수 함수로 바꿔 두 문제를 구조적으로 없앤다.

/// 가사 줄 진행 계산.
class LyricsProgressService {
  LyricsProgressService._();

  /// 이 속도에서 반주 길이에 정확히 비례해 줄이 넘어간다.
  /// (PrompterSettings의 기본 speedLevel과 같은 값)
  static const double neutralSpeedLevel = 2;

  /// 반주가 없어 길이를 모를 때, 속도 1단계당 초당 넘어가는 줄 수.
  /// speedLevel 2 → 초당 0.166줄 ≈ 6초에 한 줄.
  static const double linesPerSecondPerLevel = 0.083;

  /// 현재 하이라이트할 줄 번호(0-based)를 구한다.
  ///
  /// - [duration]을 알면 곡 전체에 줄을 고르게 배분한다. 이때 [speedLevel]은
  ///   기준 속도 대비 배수로 작동해, 올리면 가사가 실제 노래보다 앞서 나간다.
  /// - [duration]을 모르면(가사 전용 곡) 경과 시간과 [speedLevel]로 진행한다.
  /// - [speedLevel]이 0이면 진행하지 않는다.
  static int estimatedLineIndex({
    required Duration position,
    required Duration duration,
    required int lineCount,
    required double speedLevel,
  }) {
    if (lineCount <= 1) return 0;
    if (speedLevel <= 0) return 0;
    if (position <= Duration.zero) return 0;

    final double rawIndex;
    if (duration > Duration.zero) {
      final ratio = position.inMicroseconds / duration.inMicroseconds;
      final speedFactor = speedLevel / neutralSpeedLevel;
      rawIndex = ratio * lineCount * speedFactor;
    } else {
      final seconds = position.inMicroseconds / Duration.microsecondsPerSecond;
      rawIndex = seconds * speedLevel * linesPerSecondPerLevel;
    }

    return rawIndex.floor().clamp(0, lineCount - 1);
  }

  /// 자동 스크롤(전체 모드)에서 한 틱에 이동할 픽셀 양.
  ///
  /// 타이머 클로저에 값으로 갇히지 않도록 매 틱 현재 속도로 다시 계산한다.
  static double scrollDelta({
    required double speedLevel,
    required double multiplier,
  }) {
    if (speedLevel <= 0) return 0;
    return speedLevel * multiplier;
  }
}
