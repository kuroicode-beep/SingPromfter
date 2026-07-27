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

  static const String current = '1.5.0';

  static const List<AppVersionEntry> history = [
    AppVersionEntry(
      '1.5.0',
      '2026-07-28',
      '싱크 가사 가져오기(LRCLIB)·타임스탬프 표시·가사 선행 시점 조절',
    ),
    AppVersionEntry(
      '1.4.0',
      '2026-07-28',
      '유튜브 링크로 곡 가져오기(반주 처리 방식 선택·작업 진행률)',
    ),
    AppVersionEntry(
      '1.3.0',
      '2026-07-28',
      '재생 코어 정리(전체화면 위치·가사 속도 반영), 목록 검색, 연습 기록 시작',
    ),
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
