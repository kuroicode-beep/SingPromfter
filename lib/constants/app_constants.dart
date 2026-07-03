// file: lib/constants/app_constants.dart
//
// 앱 전역에서 공유하는 의미 있는 수치 상수.
class AppConstants {
  AppConstants._();

  static const double wideLayoutBreakpoint = 980;
  static const Duration autoScrollInterval = Duration(milliseconds: 90);
  static const double scrollDeltaMultiplier = 1.4;
  static const int maxBackingTrackSlots = 3;
  static const List<int> backingTrackSlots = [1, 2, 3];
  static const double minTouchTarget = 48;
}
