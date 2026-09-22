## 대상
- 프로젝트: SingPromfter
- 작업 폴더: C:\Projects\SingPromfterApp (master 직접, 워크트리 없음)
- 세션 시각: 2026-09-23 01:15 (KST)
- 직전 핸드오프: 핸드오프_20260823_1600_…_v5.6.0-v5.7.0-AI토글과안드로이드동기화

## 세션 요약
「한두 줄씩 끊어 녹음해서 자연스럽게 합치고 싶다」는 실사용 요청에서 출발해 펀치인(조각) 녹음을 만들었고, 조각이 제 자리에 안 붙는 원인 **세 겹**(ffmpeg 레벨 줄 버퍼링 · dshow 장치 열기 0.45초 · Media Foundation의 VBR seek 근사)을 차례로 규명해 v5.12.0 → v5.17.0으로 릴리스했다. 중간에 접근성 브리지 크래시도 덤프 심볼화로 규명해 고쳤다.

## 완료된 작업

### 릴리스 (전부 빌드·배포·커밋·푸시·CI 통과)
- v5.12.0 조각 이어붙이기 + Ctrl+R(직전 취소, 6초 되돌리기)
- v5.13.0/v5.13.1 Alt+R 녹음 고정 + 조작판 [녹음 고정] 버튼
- v5.14.0 무음 녹음 사후 경고, 고정 버튼 표시 강화
- v5.15.0 녹음 **전** 입력 점검 — 무음이면 CenterAlert로 차단
- v5.15.1 `0d2c7c2` 접근성 브리지 크래시 수정
- v5.15.2 `3166c8a` 스페이스 시작 딜레이 원인 제거
- v5.16.0 `010ba9c` 녹음 고정 = 상시 캡처 세션
- v5.16.0 CI 수정 `174b32a` (Windows 전용 단정 분기)
- v5.17.0 `1a8ca2b` VBR 위치 보정본 · 녹음 지연 보정 · 살아 있는 마이크 자동 선택 · 데이터 원자 저장
- 완료보고서 `71c4b6d`

### 산출물 경로
- exe: `C:\Projects\SingPromfterApp\dist\SingPromfter\singpromfter_app.exe` (v5.17.0)
- 바로가기: `C:\Users\kuroi\OneDrive\Desktop\SingPromfter.lnk` (확인됨)
- 완료보고서: `docs/reports/완료보고서_20260922_v5.12.0-v5.17.0_녹음고정과좌표정확도_ClaudeCode.md`
- 설계서: `docs/architecture/설계_20260922_녹음고정_상시캡처세션_유미.md`
- Vault 동기화: `G:\내 드라이브\SVIL Vault\03_PRJ\SingPromfter\docs` (119 파일)
- 위키: `SingPromfter 프로젝트 위키` (id `1d685604-854a-4e19-bcdc-1ad5a3275d54`, `/doc/singpromfter-TaJiToeqIy`, rev 30)
- 작업로그: `작업로그_2026-09` (id `ce9a2bf9-39db-445f-a1fd-a0bf639b5526`) 09/22 항목 6줄

### 신규 파일 (v5.16.0~v5.17.0)
`lib/controllers/capture_session.dart` · `armed_capture_session.dart` · `armed_transport.dart` · `auto_input_selection.dart` / `lib/services/atomic_json_file.dart` · `playback_copy_service.dart` · `data_load_report.dart` / `lib/utils/playback_copy_plan.dart` · `audio_header_probe.dart` · `recording_latency.dart` / `test/real/` 4개(옵트인)

### 곁다리
- 「내 남자친구에게」 랩 파트 개사(사용자 원안) → LRC/txt 싱크 반영, 비트 정렬
- 랩 보컬 조립 v6 → `C:\Downloads\내남자친구에게_랩_보컬만_v6_20260922.mp3` (STT로 경계 검증)
- 녹음 목록 파일 없는 항목 22건 정리(백업 `recordings.json.bak-clean-20260922_021318`, 6건 유지). 옮긴 원본 34개는 `C:\Users\kuroi\OneDrive\문서\data\recordings_removed_20260922_0133`에 보존 — **삭제 여부 사용자 판단 대기**

### 검증
- analyze 0 · `flutter test` **1673 통과 / 16 skip / 실패 0** (세션 시작 시 약 981개)
- 실기(`SP_REAL_FFMPEG=1`, RØDE NT-USB Mini) 11 통과 — 세션 열기 556~646ms, 조각 길이 오차 ≤0.8ms, 슬라이스 7~15ms, 닫기 159ms, 잔류 파일·프로세스 0
- CI: analyze · test · build-windows · build-android 전부 성공
- 워크플로 3회(총 78 에이전트) — 감사·설계·심사 → 구현 → 4렌즈 리뷰 → 적대적 검증 → 수정 → 재관문. 확정 결함 30건(17+13) 처리

## 진행 중 / 미완료 작업
1. **곡 목록 메모리 스냅샷 덮어쓰기** — 파일 저장은 원자화됐지만 메모리 경로가 남음. `app_controller.dart:2325-2331`, `:2592-2598`, `song_action_coordinator.dart:21→46`, `song_list_screen`의 importBackup/restoreSong. AppController에 「현재 목록 기준」 단일 관문 필요(중간 규모).
2. **`LibraryAudit.compare`가 `.lrc.bak`을 고아로 분류** — 「고아 정리」를 돌리면 재타이밍 전 원본이 삭제된다. `song_sort_service.dart:190` 3줄 + 테스트 1건(아주 작음). **지금은 고아 정리를 돌리지 말 것.**
3. **화면 배선 실기 확인** — `song_list_screen.dart`의 고정 흐름은 SongListScreen 하네스가 없고 GUI 실행이 금지라 자동 테스트 불가. 순수 부품·서비스·위젯은 테스트로 고정, 화면은 analyze + 코드 판독만.
4. **랜딩페이지** — `site/index.html`·`site/features.html`이 v5.9.0 표기(마지막 배포 2026-08-30, gh-pages `4b21588`). 갱신 여부 사용자 판단 대기. 배포는 `publish_site.ps1`.
5. **AtomicRescue 한계** — 못 열고 시작한 세션에서 지운 곡이 되살아날 수 있음(유령 항목). 46곡 증발보다 가벼운 쪽을 택한 절충.

## 주요 결정사항 / 규칙

### 🔴 접근성 브리지 크래시 (v5.15.1에서 규명)
덤프 10건을 엔진 PDB로 심볼화하니 전부 `AXPlatformNodeWin::get_accState` / `get_accRole` / `get_accParent`였다. 한글 IME(MSAA/UIA)가 화면 요소를 조회하는데 그 요소가 곧바로 사라지면 해제된 노드를 읽다 죽는다.
→ **떴다 사라지는 UI는 시맨틱스 노드를 만들지 않는다(`ExcludeSemantics`). 상시 노드를 둔 채 라벨만 바꾼다.** 근거 주석: `lib/widgets/center_alert.dart` 머리말.

### 🔴 ffmpeg `ametadata ... file=-`는 `direct=1` 없으면 종료 때까지 버퍼링 (8.1.1)
`-progress` 줄은 정상으로 와서 착각하기 쉽다. 가짜 러너 테스트로는 영영 못 잡으므로 옵트인 실기 테스트(`test/real/`, `SP_REAL_FFMPEG=1`)로 고정했다. dshow 기본 버퍼 500ms도 끝 0~0.5초를 먹으므로 `-audio_buffer_size 50`.

### 🔴 dshow 장치 열기 440~531ms는 못 줄인다
버퍼 크기·프로브 옵션·콜드/웜 어느 것으로도 40ms 이상 개선 없음. 즉시 시작이 필요하면 미리 열어 둔 세션에서 잘라내는 구조여야 한다.

### 🔴 Media Foundation은 VBR MP3를 Xing TOC 근사로 seek
보고 위치와 실제 소리가 −116~+665ms, seek 지점마다 다르다(CBR은 상수: 320k −12ms, 192k +39ms). 유튜브 받은 파일(`yt-dlp --audio-quality 0` = VBR V0)이 전부 해당. → 원본 불변 + 위치 보정본(pcm_s16le WAV) 구조.

### 시간축 계약
`파일 시각 t == 곡 시각 songPositionMs + t` (t ≥ leadIn). `songPositionMs = (P0 − L − C) − lead`, L=15ms(재생 시작 지연), C=녹음 지연 보정. 부호는 `compensateSongPositionMs` **한 곳에만** 있다.

### 테스트 규칙
- 실제 비동기(프로세스 스트림·실파일 IO)를 기다리는 테스트는 `testWidgets` 금지 — 가짜 시계에서 안 끝나 10분 타임아웃. plain `test()`.
- flutter를 **동시에** 돌리면 `build\unit_test_assets` 잠금으로 `[E]` 없이 EXIT=1. 워크플로는 관문 에이전트만 flutter를 돌리고 리뷰는 읽기 전용.
- Windows 전용 파일 잠금 단정은 `Platform.isWindows`로 분기(리눅스 CI는 열린 파일도 지워진다).

## 참고 정보
- 실기 테스트: `SP_REAL_FFMPEG=1 flutter test test/real` (RØDE 연결 필요, 없으면 정직하게 실패)
- 세션 캡처 폴더: `getApplicationSupportDirectory()/capture_sessions` (OneDrive·%TEMP% 밖)
- 보정본 캐시: `%LOCALAPPDATA%\com.svil\singpromfter_app\playback` (1.5GB 상한, 백업·동기화 제외)
- 녹음 데이터: `C:\Users\kuroi\OneDrive\문서\data\recordings` + `recordings.json`
- 빌드·배포: `build_deploy.ps1` (버전 일치 검사 + 실행 중인 앱 강제 종료 — **앱이 켜져 있으면 먼저 확인**)
- 원격에 `claude/lyrics-lock-icon-position-0lvssc` 브랜치가 남아 있음(이번 세션 것 아님, 미정리)

## 다음 세션 시작 시 할 일
1. **사용자 실기 확인 수령** — 고정 스페이스 시작/정지 체감, 첫·끝 음절 보존, R·Ctrl+R·Alt+R 연타 안정성, 키 클릭음 잔존 여부(상수 3개: 시작 가드 −40/+60ms, 끝 트림 60ms), 설정 새 줄 가독성.
2. **랜딩페이지 결정 반영** — 갱신이면 `svil-landing-page` 스킬 + `publish_site.ps1`.
3. `.lrc.bak` 고아 오분류 수정(아주 작음) — 그 전까지 고아 정리 금지.
4. 기존 곡 보정본 일괄 굽기(작음) — 지금은 곡 열 때 하나씩.
5. 곡 목록 메모리 스냅샷 단일 관문(중간).
6. `recordings_removed_20260922_0133` 삭제 여부 확인.
