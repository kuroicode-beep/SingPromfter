---
title: "완료 보고서 - UI 개선 2차 (SingPromfter v1.1.1)"
created: "2026-07-04"
updated: "2026-07-04"
owner: "InBlue"
author: "Cursor"
status: "active"
type: "report"
project: "SingPromfter"
tags:
  - ui
  - v1.1.1
visibility: "internal"
---

# 완료 보고서 - UI 개선 2차 (Cursor, 2026.07.04)

## 작업 요약

| 항목 | 결과 |
|------|------|
| 목표 | v1.1.0 UI 잘림·레이아웃 문제 해결 (T1~T5) |
| 결과 | **완료** — `1.1.1+1` |

원본 지시문: `docs/handoff/작업지시문_20260704_UI개선-2차_ClaudeCode.md`

## 변경 파일

| 파일 | 변경 내용 |
|------|-----------|
| `lib/widgets/app_top_nav_bar.dart` | T1 상단 탭 네비 (신규) |
| `lib/widgets/song_list_screen_view.dart` | 레일 제거, 상단바·접이식 큐 연동 |
| `lib/widgets/song_list_screen_content.dart` | `queueIsEmpty` 전달 |
| `lib/widgets/song_tile.dart` | T2 버튼 Wrap, 선택 시만 수정/삭제 |
| `lib/widgets/prompter_bottom_bar.dart` | T3 2계층(재생+접이식 표시설정) |
| `lib/widgets/prompter_panel.dart` | 중복 진행바 제거, 가사 하단 패딩 |
| `lib/widgets/prompter_progress_bar.dart` | `formatPrompterDuration` 분리 |
| `lib/widgets/collapsible_queue_sidebar.dart` | T4 빈 큐 접이식 (신규) |
| `lib/widgets/home_now_playing_bar.dart` | T5 비활성 "곡 선택 필요" |
| `lib/widgets/settings_panel.dart` | Copyright·프롬프터 오타 수정 |
| `lib/widgets/song_list_panel.dart` | Footer 제거, 안내 문구 수정 |
| `lib/widgets/compact_btn.dart` | 50dp 터치 타겟 |
| `lib/constants/app_constants.dart` | `minTouchTarget` 50 |
| `pubspec.yaml` | `1.1.1+1` |
| `docs/handoff/작업지시문_20260704_UI개선-2차_ClaudeCode.md` | 지시문 추가 |

## 구현 결과

- [x] T1 — 좌측 레일 → 상단 탭 바 (240px 확보)
- [x] T2 — 카드 [예약]/[시작] 상시, [수정]/[삭제] 선택 시만
- [x] T3 — 하단 바 가로 스크롤 제거, 접이식 표시 설정
- [x] T4 — 가사 패딩·빈 큐 접이식 사이드바
- [x] T5 — 탭 오타, Copyright 이동, minTouchTarget 50, 곡 시작 비활성 텍스트

## 검증 결과

| 명령 | 결과 |
|------|------|
| `flutter analyze` | No issues found |
| `flutter test` | 27/27 통과 |
| `flutter build windows --release` | 성공 |

## Git·배포

- 커밋: `5135614` — `fix: UI 개선 2차 — 상단 탭·카드 버튼·하단 바 재구성 (v1.1.1)`
- 푸시: `origin/master`, 태그 `v1.1.1` 푸시 완료
- 배포: `dist/SingPromfter-v1.1.1/singpromfter_app.exe`
- 바탕화면 바로가기: `SingPromfter.lnk` → v1.1.1 경로로 갱신

## 핸드오프

- Codex 독립 검증 (잘림 0건, 좁은/넓은 창 수동 확인)
- `app_nav_rail.dart`는 미참조 상태 — 후속 정리 가능
