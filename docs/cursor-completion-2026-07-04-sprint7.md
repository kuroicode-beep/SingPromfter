---
title: "완료 보고서 - SingPromfter Sprint 7 레이아웃 리뉴얼"
created: "2026-07-04"
updated: "2026-07-04"
owner: "InBlue"
author: "Cursor"
status: "active"
type: "report"
project: "SingPromfter"
tags:
  - SingPromfter
  - Sprint7
  - layout
visibility: "private"
---

# 완료 보고서 - SingPromfter Sprint 7 레이아웃 리뉴얼 (Cursor, 2026.07.04)

## 1. 작업 요약

- 목표: handoff Sprint 7 — 네비 레일, 3열 홈, 곡 검색 화면
- 결과: 완료 (`v1.1.0-beta.2+1`)
- 원본 작업지시문: `docs/handoff/작업지시문_20260704_기능개선-디자인리뉴얼_ClaudeCode.md`

## 2. 변경 파일 목록

| 구분 | 파일 |
|---|---|
| 모델/서비스 | `lib/models/app_destination.dart`, `lib/services/song_filter_service.dart`, `lib/constants/app_constants.dart` |
| S7-1 네비 | `lib/widgets/app_nav_rail.dart`, `lib/widgets/settings_panel.dart` |
| S7-2 홈 | `lib/widgets/home_now_playing_bar.dart`, `lib/widgets/song_list_screen_view.dart`, `lib/widgets/prompter_panel.dart` |
| S7-3 검색 | `lib/widgets/song_search_panel.dart`, `lib/widgets/song_list_panel.dart` |
| 연결 | `lib/widgets/song_list_screen_content.dart`, `lib/screens/song_list_screen.dart` |
| 테스트 | `test/services/song_filter_service_test.dart`, `test/widgets/song_search_panel_test.dart` |
| 버전/문서 | `pubspec.yaml`, `docs/개선계획/00-전체-로드맵.md` |

## 3. 구현 결과

### S7-1 네비게이션 레일
- AppBar·FAB 제거 → 좌측 레일(240px / 좁은 창 72px)
- 홈·곡 검색·즐겨찾기·설정 + 하단 **곡 등록** 버튼
- 설정: 일괄 등록, 백업 내보내기/가져오기, 프롬pter 프리셋

### S7-2 3열 홈
- 와이드: `[레일] | [곡 목록 360px] | [프롬pter] | [예약 큐 320px]`
- 상단 `Now Playing` / `선택된 곡` 상태 바 + **[곡 시작]**
- 좁은 창: 탭(곡 목록 / 프롬pter / 예약 큐) 유지

### S7-3 곡 검색
- `SongFilterService`로 검색·필터 로직 공유
- 필터: 전체 / 즐겨찾기 / 반주 있음 / 최근 등록(30일)
- 결과 행 **[예약] [시작]** 버튼

## 4. 검증 결과

| 명령 | 결과 |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | 23/23 통과 |
| `flutter build windows` | Release exe 빌드 성공 |

## 5. Git 커밋·배포

- 로컬 변경 (Sprint 6 S6-2/3 + Sprint 7 포함, 미커밋)
- 태그 `v1.1.0-beta.2`: 미생성 (선택)

## 6. 핸드오프

- **다음:** Sprint 8 — 가수 필드, 가사 줄 하이라이트, 큐 NOW, 진행률 바 → `v1.1.0`
- **Codex:** Sprint 7 독립 검증
- **InBlue:** 와이드/좁은 창에서 레일·3열·검색 화면 수동 확인
