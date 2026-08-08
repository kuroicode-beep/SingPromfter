# 작업지시문 — Phase 4: 작곡 UI + AI 게이트 (v3.0.0)

- 작성일: 2026-08-08 · 담당: Claude Code · 정본 스펙: docs/스펙 §6 · 선행: Phase 3 완료

## 목표

작곡 탭 UI 전체와 로컬AI/클라우드AI 게이트(기본 OFF·안내 팝업·비활성 처리)를 완성한다.

## 작업 항목

1. **탭 추가** — `lib/models/app_destination.dart`: `compose`(recordings와 jobs 사이), 라벨 '작곡', `Icons.music_note_outlined`. `song_list_screen_view._buildDestinationBody` case + `song_list_screen_content`에 composePanel prop.
2. **`lib/widgets/compose_panel.dart` 신규**
   - 상단: 제목 '작곡' + 상태 칩('작곡 서버: 온라인/꺼짐' · 'BGM 서버: …' — 텍스트 병기).
   - 생성 폼 카드: 제목(비우면 "AI 작곡 yyyy-MM-dd HH:mm") / 모드 칩 BGM·보컬곡 / 스타일 프롬프트 멀티라인(힌트: 한국어로 적으면 AI가 다듬어 줍니다) / 보컬곡 전용: 가사 멀티라인·보컬 타입 칩(여성/남성/듀엣/합창)·장르 태그·BPM / 길이 칩 — BGM: 30초·1분·2분·3분·5분, 보컬곡: 3분·4분·5분·7분·10분 / 고급 ExpansionTile(seed·프리셋(BGM, 8766 /presets)·model_size(BGM)) / 버튼 [AI 다듬기]·[생성 시작].
   - AI 다듬기: 결과를 편집 가능한 미리보기 TextField에 채움(자동 덮어쓰기 금지). 실패 시 스낵바(`ollama pull <model>` 안내)+원문 진행 가능.
   - 진행 스트립: 보컬곡=서버 detail 실시간+경과 mm:ss, BGM=경과+불확정 바, 취소 버튼(+"서버 작업은 계속될 수 있습니다").
   - 생성 목록: 행당 제목·모드·길이·seed·일시, 버튼 듣기/정지(기존 _takePlayer)·이름 바꾸기·곡으로 등록·파일로 내보내기(saveFile)·삭제(확인). batchId 그룹 표시. 등록됨 배지.
3. **곡으로 등록** — `AppController.registerCompositionAsSong`: SongDraft(trackPaths:{1: path}, artist 'AI 작곡') → SongLibraryService.addSong(lyrics: c.lyrics) → registeredSongId 기록 → 레벨 선분석 unawaited.
4. **AI 게이트**
   - `prompter_settings`: `localAiEnabled`·`cloudAiEnabled`(기본 false).
   - settings_panel 'AI 기능' 섹션: 스위치 2개. OFF→ON 시 안내 팝업(AlertDialog): 구성요소 목록+현재 온라인 상태 — ①분리 8771 `separator_system\start.bat` ②작곡 8774 `compose_system\start.bat` + ACE 엔진 8001 `C:\ai-acestep\start_api_server.bat`(또는 SAW 트레이) ③BGM 8766 `bgm_system\start.bat` ④Ollama 11434 + `gemma4:12b`. [켜기]/[취소], 취소 시 OFF 유지. 클라우드AI 팝업: "현재 클라우드 AI 기능 없음 — 향후 확장용" (DeepSeek 다듬기 확정 시 문구 교체).
   - settings_panel '작곡' 섹션: Ollama 모델명 TextField + `모델 확인` 버튼(listModels 결과 ✓/안내).
   - 비활성: `app_top_nav_bar`에 `Set<AppDestination> disabled` — 흐림(0.4)+클릭 시 스낵바 "설정에서 로컬AI를 켜면 사용할 수 있습니다". add_song_dialog/add_track_dialog의 aiSeparate 옵션 비활성+사유 텍스트(기본 reduceVocal 폴백). 상태 칩 숨김·8771/8774/8766 폴링 중단.
   - AppController 가드: enqueueImport(aiSeparate)·enqueueCompose·separateTake에서 localAiEnabled 검사 → `local_ai_disabled`.

## 테스트

- prompter_settings roundtrip(새 필드) 확장. UI는 수동 시나리오.

## 완료 기준

- 로컬AI OFF: 작곡 탭 흐림+스낵바·AI 분리 비활성. ON 팝업 확인 후: BGM 30초 생성→재생→곡 등록→홈 재생 E2E. 보컬곡: 엔진 꺼짐=즉시 안내, 켜면 실제 생성·상태 표시. analyze/test 통과.
