---
title: "완료 보고서 - SingPromfter Sprint 8 기능 개선"
created: "2026-07-04"
updated: "2026-07-04"
owner: "InBlue"
author: "Cursor"
status: "active"
type: "report"
project: "SingPromfter"
tags:
  - SingPromfter
  - Sprint8
  - features
visibility: "private"
---

# 완료 보고서 - SingPromfter Sprint 8 기능 개선 (Cursor, 2026.07.04)

## 1. 작업 요약

- 목표: handoff Sprint 8 — 가수 필드, 줄 하이라이트, 예약/시작, 큐 NOW, 진행률 바
- 결과: 완료 (`v1.1.0+1`)
- 원본 작업지시문: `docs/handoff/작업지시문_20260704_기능개선-디자인리뉴얼_ClaudeCode.md`

## 2. 변경 파일 목록

| 구분 | 파일 |
|---|---|
| S8-1 가수 | `lib/models/song.dart`, `lib/models/song_draft.dart`, 등록/수정 다이얼로그, `lib/services/song_filter_service.dart` |
| S8-2 하이라이트 | `lib/models/prompter_display_mode.dart`, `lib/models/prompter_settings.dart`, `lib/widgets/prompter_lyrics_view.dart`, `lib/services/prompter_auto_scroll_service.dart`, `lib/screens/prompter_screen.dart` |
| S8-3 버튼 | `lib/widgets/song_tile.dart`, `lib/screens/song_list_screen.dart` |
| S8-4 큐 | `lib/widgets/queue_panel.dart`, `lib/services/queue_logic.dart`, `lib/services/song_queue_service.dart`, `lib/widgets/song_search_panel.dart` |
| S8-5 진행률 | `lib/widgets/prompter_progress_bar.dart`, `lib/widgets/prompter_panel.dart`, `lib/screens/prompter_screen.dart` |
| 테스트 | `test/models/song_model_test.dart`, `test/services/song_filter_service_test.dart`, `test/services/queue_logic_test.dart`, `test/widgets/prompter_lyrics_view_test.dart` |
| 버전/문서 | `pubspec.yaml`, `docs/개선계획/00-전체-로드맵.md` |

## 3. 구현 결과

### S8-1 가수(artist) 필드
- `Song.artist` 옵션 필드, 구버전 JSON/백업 호환 (`fromJson` 기본값 `''`)
- 등록/수정 다이얼로그, 검색(제목+가수+초성), 검색 화면 표시

### S8-2 줄 하이라이트 모드
- `PrompterDisplayMode.full | highlight` 설정 저장
- 현재/이전/다음 3줄 컨텍스트, primary 글로우
- 자동 스크롤 **타이머 기준** 줄 이동 (오디오 싱크 아님 — UI 문구·주석 명시)
- 전체화면·미리보기 패널 공통 `PrompterLyricsView`

### S8-3 [예약]/[시작] 버튼
- `song_tile` 우측 상시 노출 (tertiary / primaryContainer, 50dp)
- **시작** = 곡 로드 → 재생(가능 시) → 전체화면 프롬pter

### S8-4 예약 큐 시각
- 순번 01, 02…, 재생 중 **NOW** 배지 + 틴트 + 좌측 인디케이터
- 검색 화면 **검색 결과 전체 예약** (확인 다이얼로그)

### S8-5 진행률 바
- `PrompterProgressBar` — primary 6px, `m:ss / m:ss` 16px
- 홈 프롬pter 패널·전체화면 프롬pter 하단, 시크 연동

## 4. 검증 결과

| 명령 | 결과 |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | 27/27 통과 |
| `flutter build windows` | Release exe 빌드 성공 |

## 5. Git 커밋·배포

- Sprint 6~8 변경 로컬 미커밋 — 사용자 요청 시 커밋·푸시
- 태그 `v1.1.0`: 미생성 (선택)

## 6. 핸드오프

- **Codex:** Sprint 6~8 통합 독립 검증
- **InBlue:** 줄 하이라이트·NOW 배지·전체 예약·가수 검색 수동 확인
- 디자인 리뉴얼 handoff Sprint 6~8 **전체 완료** → `v1.1.0` 정식 릴리스 후보
