// file: lib/constants/app_constants.dart
//
// 앱 전역에서 공유하는 의미 있는 수치 상수.
class AppConstants {
  /// 가사 선행/지연 오프셋의 한계(ms).
  ///
  /// v2.7.0까지 ±3초 → ±10초로 열었지만, 노래방(4번)처럼 **아예 다른
  /// 녹음**은 인트로 차가 10초를 훌쩍 넘는다 — 실사용에서 −10초에 포화된
  /// 채 "아무리 눌러도 안 먹는" 사고가 났다(v3.7.1). ±60초로 연다.
  /// 한계에 닿으면 조용히 무시하지 않고 '한계값'이라고 알린다.
  static const int maxLyricsOffsetMs = 60000;

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
