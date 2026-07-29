// file: lib/constants/app_constants.dart
//
// 앱 전역에서 공유하는 의미 있는 수치 상수.
class AppConstants {
  /// 가사 선행/지연 오프셋의 한계(ms).
  ///
  /// v2.7.0까지는 ±3초였는데, LRCLIB이 인트로 길이가 다른 판본을 물어 오면
  /// 4초 넘게 어긋나는 일이 있다(실측: "넌 언제나" LRC가 보컬보다 3.96초 늦음).
  /// 그런 곡은 ±3초 안에서는 **아예 맞출 수가 없다**. 10초까지 열어 둔다.
  static const int maxLyricsOffsetMs = 10000;

  AppConstants._();

  static const double wideLayoutBreakpoint = 980;
  static const double navRailExpandedWidth = 240;
  static const double navRailCollapsedWidth = 72;
  static const double homeSongListWidth = 300;
  static const double homeQueueWidth = 240;
  /// 곡당 반주 슬롯 수. v2.6.0에서 4로 늘렸다 —
  /// 1=원곡 2=MR(AI 분리) 3=키조절 4=노래방(별도 링크).
  static const int maxBackingTrackSlots = 4;
  static const List<int> backingTrackSlots = [1, 2, 3, 4];
  /// 조작 요소 최소 높이.
  /// v2.5.0에서 정보 밀도를 위해 축소했다(사용자 요청). 무대 전체화면의
  /// 큰 조작부는 자체 크기를 쓰므로 이 값의 영향을 받지 않는다.
  /// 최소 터치·클릭 타깃(dp).
  ///
  /// SVIL 접근성 기준은 50 이상인데 v2.8.0까지 34였다. 저시력 사용자에게
  /// 34dp 버튼은 조준이 필요한 크기라 기준대로 올렸다.
  static const double minTouchTarget = 50;

  /// 목록 행처럼 더 촘촘해도 되는 곳.
  static const double denseTouchTarget = 28;
}
