// file: lib/constants/app_version.dart
//
// 앱 버전과 업데이트 히스토리(최신순). 기능 추가 시마다 갱신한다.
class AppVersionEntry {
  final String version;
  final String date;
  final String summary;

  const AppVersionEntry(this.version, this.date, this.summary);
}

class AppVersion {
  AppVersion._();

  static const String current = '1.2.1';

  static const List<AppVersionEntry> history = [
    AppVersionEntry(
      '1.2.1',
      '2026-07-14',
      '설정에 앱 글꼴 선택·글자 크기 3단계 추가, 버전 정보 표기',
    ),
    AppVersionEntry(
      '1.2.0',
      '2026-07-14',
      'SVIL 디자인 표준 전환 (블루 accent·교보손글씨2019·볼드 제거)',
    ),
    AppVersionEntry('1.1.3', '2026-07-04', '키보드 단축키 Focus/Shortcuts 재구현'),
    AppVersionEntry('1.1.0', '2026-07-04', 'UI 리뉴얼: 상단 탭·곡 검색·예약 큐 개편'),
    AppVersionEntry('1.0.0', '2026-07-04', '정식 릴리스 (Sprint 1~5 완료)'),
  ];
}
