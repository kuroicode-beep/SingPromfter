// file: lib/constants/app_constants.dart
//
// 앱 전역에서 공유하는 의미 있는 수치 상수.
class AppConstants {
  AppConstants._();

  static const double wideLayoutBreakpoint = 980;
  static const double navRailExpandedWidth = 240;
  static const double navRailCollapsedWidth = 72;
  static const double homeSongListWidth = 360;
  static const double homeQueueWidth = 320;
  static const Duration autoScrollInterval = Duration(milliseconds: 90);
  static const double scrollDeltaMultiplier = 1.4;

  /// 자동 스크롤 속도 1단계당 초당 이동 픽셀.
  /// 기존 타이머(90ms마다 speed*1.4px)와 같은 체감 속도를 프레임 기준으로 옮긴 값.
  static const double autoScrollPixelsPerSecond =
      scrollDeltaMultiplier * 1000 / 90;
  static const int maxBackingTrackSlots = 3;
  static const List<int> backingTrackSlots = [1, 2, 3];
  static const double minTouchTarget = 50;
}
