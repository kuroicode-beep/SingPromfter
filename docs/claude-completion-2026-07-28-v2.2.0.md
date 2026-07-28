# 완료보고서 — v2.2.0 파일 직접 등록 경로 완전 제거

- 작성일: 2026-07-28
- 작업자: Claude Code
- 브랜치: `claude/upbeat-northcutt-5f116e`

## 배경

v2.1.0에서 곡 추가의 **주 경로**를 유튜브 링크로 교체했으나, 기존 파일 직접 등록 경로가 보조 선택지로 함께 남아 있었다. 소장님 판단은 "안 쓸 것 같으니 완전히 걷어내자"였고, 이에 따라 파일 기반 등록 코드를 **전부 삭제**했다.

결과: 곡을 목록에 넣는 방법은 **링크 하나뿐**이다. 진입점이 하나이므로 대화상자 분기, 보조 경로 안내 문구, 그에 딸린 서비스·코디네이터 계층이 모두 사라졌다.

## 제거한 것

| 대상 | 위치 |
|---|---|
| `AddSongChoice` sealed 계층 + `AddSongFromFiles` | `lib/dialogs/add_song_dialog.dart` → 반환 타입이 `AddSongFromUrl?` 단일로 단순화 |
| "파일로 직접 추가" 버튼 + 안내 문구 | 같은 파일 |
| `_addSongFromFiles()` | `lib/screens/song_list_screen.dart` |
| `SongActionCoordinator.addSong()` | `lib/coordinators/song_action_coordinator.dart` |
| `SongCreateDialog` (파일 전체) | `lib/dialogs/song_create_dialog.dart` **삭제** |
| `BatchRegistrationService` (파일 전체) | `lib/services/batch_registration_service.dart` **삭제** |
| 일괄 등록 흐름 `_batchRegister` / `_confirmBatchMatches` | `lib/screens/song_list_screen.dart` |
| 설정 화면 "일괄 등록" 타일 + `onBatchRegister` 배선 | `settings_panel.dart`, `song_list_screen_content.dart` |
| `SongLibraryService.readPickedLyrics` + `PickedLyricsResult` + 사설 디코더 | `lib/services/song_library_service.dart` |

**일괄 등록(폴더 기반 txt/mp3 매칭)도 함께 제거**했다. 파일 기반 수동 등록의 배치판이라 단일 경로만 없애면 반쪽만 남기 때문이다.

## 남긴 것 (의도적)

- `SongDraft`, `SongLibraryService.addSong` / `editSong` / `deleteSong` — **가져오기 파이프라인이 그대로 사용**한다. 링크로 받은 곡도 결국 같은 저장 경로를 탄다.
- `SongEditDialog` — 이미 등록된 곡의 가사 교체·반주 추가는 여전히 파일 선택을 쓴다. 이건 "등록"이 아니라 "수정"이라 남긴다.
- `file_picker` 의존성 — 수정 대화상자·백업 가져오기에서 계속 쓴다.

## 검증

| 항목 | 결과 |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | **217 passed** |
| `flutter build windows --release` | 성공 (26.9s) |

테스트는 `test/widgets/add_song_dialog_test.dart`를 갱신했다. `AddSongFromFiles` 관련 케이스를 삭제하고, 대신 **"파일로 직접 추가"가 화면에 없음**(`findsNothing`)을 회귀로 고정했다. 보컬 분리 서버 오프라인 안내 케이스도 추가했다.

## 문서

- `README.md` 전면 갱신 — v1.1.0-beta.1 시절 기능 목록이 그대로 남아 있어 v2.2.0 기준으로 다시 썼다. 링크 가져오기는 **용도 제한·책임 소재 문구를 함께** 기재하고 홍보 표현은 쓰지 않았다(저작권 2트랙 방침의 트랙 B 유지).
- `AppVersion.current` → `2.2.0`, 히스토리 항목 추가
- `pubspec.yaml` → `2.2.0+1`

## 수동 확인이 필요한 항목

코드 레벨 검증은 끝났으나, 실행 확인은 소장님 쪽에서 한 번 봐 주시면 좋다.

1. 곡 추가 버튼 → 링크 입력 대화상자만 뜨는지 (다른 선택지 없음)
2. 설정 화면에 "일괄 등록" 타일이 사라졌는지
3. 기존에 파일로 등록해 둔 곡들이 그대로 재생되는지 (데이터는 건드리지 않았음)
