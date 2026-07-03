---
title: "완료 보고서 - SingPromfter Sprint 3 아키텍처 리팩토링 (Cursor, 2026.07.04)"
created: "2026-07-04"
updated: "2026-07-04"
owner: "InBlue"
author: "Cursor"
status: "active"
type: "report"
project: "SingPromfter"
tags:
  - SingPromfter
  - Sprint3
  - refactoring
visibility: "internal"
---

# 완료 보고서 - SingPromfter Sprint 3 아키텍처 리팩토링 (Cursor, 2026.07.04)

## 1. 작업 요약

- 목표: Sprint 3 아키텍처 리팩토링(B1~B5)을 적용해 Sprint 4/5 기능 확장 전 유지보수 가능한 구조로 정리
- 결과: 완료
- 릴리스 버전: `v0.7.0` (`pubspec.yaml` 기준 `0.7.0+1`)

## 2. 변경 파일 목록

| 구분 | 파일 |
|---|---|
| 화면 리팩토링 | `lib/screens/song_list_screen.dart`, `lib/widgets/song_list_screen_content.dart`, `lib/widgets/song_list_screen_view.dart`, `lib/widgets/song_list_panel.dart`, `lib/widgets/prompter_panel.dart`, `lib/widgets/prompter_bottom_bar.dart` |
| 다이얼로그 분리 | `lib/dialogs/song_create_dialog.dart`, `lib/dialogs/song_edit_dialog.dart`, `lib/dialogs/song_delete_dialog.dart`, `lib/dialogs/custom_font_size_dialog.dart` |
| 서비스/코디네이터 | `lib/coordinators/song_action_coordinator.dart`, `lib/services/prompter_audio_service.dart`, `lib/services/prompter_auto_scroll_service.dart`, `lib/services/prompter_settings_service.dart`, `lib/services/song_library_service.dart`, `lib/services/song_list_bootstrap_service.dart`, `lib/services/song_list_shortcut_service.dart`, `lib/services/song_queue_service.dart` |
| 저장소/모델 | `lib/repository/song_repository.dart`, `lib/repository/song_meta_store.dart`, `lib/models/song.dart`, `lib/models/song_draft.dart`, `lib/models/prompter_settings.dart`, `lib/theme/prompter_levels.dart` |
| 문서/버전 | `pubspec.yaml`, `README.md`, `docs/기능명세서.md`, `docs/개선계획/00-전체-로드맵.md` |

## 3. 구현 결과

- B1: `SongListScreen` God Widget 분리 완료. 최종 `lib/screens/song_list_screen.dart` 400줄.
- B2: 글자 크기/줄 간격/자동 스크롤 변환 로직을 `PrompterLevels`로 공통화.
- B3: 곡 메타데이터 저장을 `SongMetaStore` 기반 JSON 파일로 분리하고 기존 `SharedPreferences` 데이터 마이그레이션 경로 유지.
- B4: Web 전용 분기와 안내 문구를 제거하고 Windows 데스크톱 검증 기준으로 정리.
- B5: `copyMr`, `getMrPath`, `mrFileName` 레거시 래퍼 제거.

## 4. 검증 결과

| 명령 | 결과 |
|---|---|
| `flutter analyze` | 통과, No issues found |
| `flutter build windows` | 통과, `build/windows/x64/runner/Release/singpromfter_app.exe` 생성 |
| `python -c "from pathlib import Path; ... song_list_screen.dart ..."` | `400`줄 확인 |

## 5. Git 커밋·배포 여부

- Git 커밋: 미실행
- 배포: 미실행

## 6. 핸드오프 메모

- 다음 Sprint 4 착수 가능.
- Codex 검증 시 중점 확인 권장:
  - 곡 추가/수정/삭제 후 선택 곡과 예약 큐 상태 유지
  - 반주 없는 곡 자동 스크롤 및 자동 스킵 동작
  - JSON 메타 저장소 마이그레이션 후 기존 곡 목록 보존
  - `SongListScreen` 분리 후 콜백 연결 누락 여부
