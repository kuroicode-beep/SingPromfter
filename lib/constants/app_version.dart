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

  static const String current = '2.7.0';

  static const List<AppVersionEntry> history = [
    AppVersionEntry(
      '2.7.0',
      '2026-07-29',
      '무대 조작 마무리 — 휠 모드 분리·현재 줄 강조·Home/End·Alt+휠 키 조절·조성 자동 감지',
    ),
    AppVersionEntry(
      '2.6.0',
      '2026-07-29',
      '무대 개편 — 줄 클릭 이동·휠 줄넘김·Ctrl+휠 크기·싱크 수정·EQ 확대·반주 4슬롯',
    ),
    AppVersionEntry(
      '2.5.0',
      '2026-07-28',
      'UI 밀도 개편 — 본문 13pt·고밀도 곡 목록·상단 여백 축소',
    ),
    AppVersionEntry(
      '2.4.0',
      '2026-07-28',
      'AI 제어(MCP) — 곡 추가·키·큐·재생을 프롬프트로 조작 (로컬 API 8772)',
    ),
    AppVersionEntry(
      '2.3.0',
      '2026-07-28',
      '가져오기 개선(제목 정제·재시도·가사 길이 가드) + 전체화면 EQ 미터',
    ),
    AppVersionEntry(
      '2.2.0',
      '2026-07-28',
      '파일 직접 등록 경로 제거 — 곡 추가는 유튜브 링크 하나로 통일',
    ),
    AppVersionEntry(
      '2.1.0',
      '2026-07-28',
      '곡 추가 주 경로를 링크 기반으로 교체 — 링크 하나로 반주·가사까지 자동 준비',
    ),
    AppVersionEntry(
      '2.0.0',
      '2026-07-28',
      'AI 보컬 분리(SVIL 서버)·서버 상태 표시·믹스다운·수동 lrc 등 보완',
    ),
    AppVersionEntry(
      '1.9.1',
      '2026-07-28',
      '전체 검수 — 스키마 보호·백업 연습기록·목표곡 자동체크 등 9건 수정',
    ),
    AppVersionEntry(
      '1.9.0',
      '2026-07-28',
      '목록 정렬(제목·최근·많이/덜 부른 순), 라이브러리 정리 도구',
    ),
    AppVersionEntry(
      '1.8.0',
      '2026-07-28',
      '트레이닝 센터 — 일일 보컬 루틴 체크·연속 달성일·연습 통계',
    ),
    AppVersionEntry(
      '1.7.0',
      '2026-07-28',
      '녹음 기능과 녹음 보관함(코멘트·별점·보관)',
    ),
    AppVersionEntry(
      '1.6.0',
      '2026-07-28',
      '키(피치) 조절 — 원곡 대비 ±6반음, 템포 유지 오프라인 변환',
    ),
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
