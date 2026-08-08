# 작업지시문 — Phase 1: 녹음 코어 (v3.0.0)

- 작성일: 2026-08-08 · 담당: Claude Code · 정본 스펙: docs/스펙_20260808_v3.0.0_AI스튜디오_ClaudeCode.md §1.1·§1.3·§3

## 목표

녹음 시 보컬(마이크)·반주(재생)를 분리 확보하고, 보컬/반주/믹스 3파일 저장·내보내기와 설정(입력 장치·볼륨·마이크 테스트)을 완성한다.

## 작업 항목 (순서대로)

1. **재생 경로 캡처**
   - `lib/services/prompter_audio_service.dart`: `AudioPrepareResult`에 `String? path` 추가, `prepareSelection`이 최종 재생 경로를 담아 반환.
   - `lib/controllers/playback_controller.dart`: `PlaybackSnapshot`에 `activeAudioPath` 추가(+copyWith/clear), `prepareAudioForSelection`에서 세팅.
2. **모델·스토어 v2**
   - `lib/models/recording_take.dart`: `sourceAudioPath`·`tempoScale`·`accompanimentFileName`·`mixBalance`·`reverbPreset`·`noiseReduction`·`separatedFileName` 추가 (Phase 2 필드 선반영 — 스키마 범프 1회).
   - `lib/services/recording_library_service.dart`: `schemaVersion=2`, `remove()`가 acc/mix/sep 파일 동반 삭제(기존 mixedFileName 누수 수정).
3. **반주 컷·믹스 개편** — `lib/services/take_mix_service.dart`
   - `buildAccompanimentCutArgs({sourcePath, outputPath, startMs, durationMs})` 순수 함수(스펙 §3.2) + `cutAccompaniment()`(실패 시 반쪽 파일 삭제).
   - 믹스: acc 있으면 `alignMs:0`으로 acc+보컬, 없으면 기존 폴백.
4. **설정 필드** — `lib/models/prompter_settings.dart`: `recordingDeviceName`·`recordingGain` (+roundtrip).
5. **캡처 게인·프로브** — `lib/controllers/recording_controller.dart`
   - `buildRecordArgs(gain:)`: gain≠1.0이면 af 맨 앞 `volume=` (astats 앞).
   - `buildLevelProbeArgs` + `startLevelProbe/stopLevelProbe` (출력 `-f null -`, 기존 RMS 파서 재사용, 녹음 중 시작 금지).
   - `start()`: 저장 장치가 목록에 없으면 첫 장치 폴백.
6. **화면 배선** — `lib/screens/song_list_screen.dart`
   - 녹음 시작 시 `activeAudioPath`·`tempoScale` 스냅샷, 종료 시 take 기록 → 즉시 컷 실행(실패해도 테이크 유지).
   - 설정에서 장치/게인 주입.
7. **설정 UI** — `lib/widgets/settings_panel.dart` '녹음' 섹션: 장치 드롭다운+새로고침 / 볼륨 슬라이더(0~200%, % 상시 표시) / 마이크 테스트 토글+레벨 바+상태 텍스트.
8. **녹음 탭 UI** — `lib/widgets/recordings_panel.dart`: `반주 듣기`·`반주 만들기`(재시도)·`파일로 내보내기`(getDirectoryPath → `{제목}_{yyyyMMdd_HHmm}_보컬.wav/_반주.m4a/_믹스.m4a`, 믹스 없으면 먼저 생성). `sanitizeFileName` 유틸 신설. prop-drilling은 기존 패턴(song_list_screen → content → panel).

## 테스트

- recording_rules_test 확장(gain 순서·프로브 args), take_mix_service_test 확장(컷 초 변환·alignMs 0), recording_take_schema_test 신규(v1→기본값·v2 roundtrip), prompter_settings roundtrip, sanitizeFileName.

## 완료 기준

- 키조절 반주로 녹음 → 보컬/반주/믹스 각각 청취 시 키 일치 · 내보내기 3파일 생성 · 설정 유지 · analyze/test 통과.

## 주의

- 컷은 녹음 종료 직후 즉시(변형본 캐시 삭제 대비). 실패 시 테이크는 남기고 재시도 버튼 제공.
- 단일 쓰기 경로(AppController.updateSettings) 밖에서 설정을 저장하지 말 것.
