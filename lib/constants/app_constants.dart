// file: lib/constants/app_constants.dart
//
// 앱 전역에서 공유하는 의미 있는 수치 상수.
class AppConstants {
  AppConstants._();

  static const double wideLayoutBreakpoint = 980;
  static const double navRailExpandedWidth = 240;
  static const double navRailCollapsedWidth = 72;
  static const double homeSongListWidth = 300;
  static const double homeQueueWidth = 240;
  static const Duration autoScrollInterval = Duration(milliseconds: 90);
  static const double scrollDeltaMultiplier = 1.4;

  /// 자동 스크롤 속도 1단계당 초당 이동 픽셀.
  /// 기존 타이머(90ms마다 speed*1.4px)와 같은 체감 속도를 프레임 기준으로 옮긴 값.
  static const double autoScrollPixelsPerSecond =
      scrollDeltaMultiplier * 1000 / 90;
  /// 곡당 반주 슬롯 수. v2.6.0에서 4로 늘렸다 —
  /// 1=원곡 2=MR(AI 분리) 3=키조절 4=노래방(별도 링크).
  static const int maxBackingTrackSlots = 4;
  static const List<int> backingTrackSlots = [1, 2, 3, 4];
  /// 조작 요소 최소 높이.
  /// v2.5.0에서 정보 밀도를 위해 축소했다(사용자 요청). 무대 전체화면의
  /// 큰 조작부는 자체 크기를 쓰므로 이 값의 영향을 받지 않는다.
  static const double minTouchTarget = 34;

  /// 목록 행처럼 더 촘촘해도 되는 곳.
  static const double denseTouchTarget = 28;
}
