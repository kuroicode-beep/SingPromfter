# 작업지시문 — Phase 3: 작곡 인프라 (v3.0.0)

- 작성일: 2026-08-08 · 담당: Claude Code · 정본 스펙: docs/스펙 §1.2·§2·§4

## 목표

작곡 기능의 헤드리스 전부: 클라이언트 3종(8774·8766·Ollama), Composition 모델·저장소, 작곡 잡 큐, AppController 배선.

## 작업 항목

1. **`lib/services/song_compose_client.dart`** (보컬곡, 8774 잡 기반 — VocalSeparationClient 스타일)
   - `status()`(GET /status, 3초) · `engineStatus()`(GET /api/song/engine, 3초) · `submit()`(POST /api/song/generate) · `pollStatus(jobId)`(GET /api/song/status/{id}) · `downloadOutput(remotePath, localPath)`(GET /output 스트림).
   - 순수 함수 `buildSongBody({prompt, lyrics, durationSec(180~600 클램프), vocalType, genre, bpm, seed, format:'mp3', lang:'ko'})`.
2. **`lib/services/bgm_compose_client.dart`** (BGM, 8766 블로킹)
   - `status()`·`presets()`·`generate()`(타임아웃 20분)·`downloadOutput()`.
   - 순수 함수 `buildGenerateBody({prompt, preset, durationSec(10~300 클램프), modelSize, seed, convertMp3:true, backend:'musicgen'})`.
3. **`lib/services/ollama_client.dart`**
   - `listModels()`(GET /api/tags, 3초) · `polishStylePrompt(korean, {model})`(POST /api/chat stream:false, 120초) · `tagLyrics(lyrics, {model})`(구조 태그 삽입).
   - 실패 분류: offline / model_missing / error. 요청 body 빌더는 순수 함수.
4. **`lib/models/composition.dart`**: Composition + `ComposeMode {bgm, vocal}`(라벨 'BGM'/'보컬곡') — 스펙 §1.2 필드 전부, toJson/fromJson/copyWith.
5. **`lib/services/compose_library_service.dart`**: `ComposeStore`(data/compose, compositions.json v1, RecordingStore 미러 — 동일 버전 가드) + load/add/update/remove(오디오 동반 삭제)/pathFor.
6. **`lib/controllers/compose_job_controller.dart`**: `ComposeJob{id, request, status, statusDetail, startedAt, resultCompositionId}` + `ComposeJobStatus`(queued/running/done/failed/cancelled — 한국어 라벨) + `ComposeJobQueueLogic`(import 미러) + `ComposeJobController`(동시성 1, 러너 주입, cancel/retry/clearFinished).
7. **AppController 배선** — `lib/controllers/app_controller.dart`
   - 소유: songCompose·bgmCompose·ollama·composeLibrary·composeJobs(+dispose). bootstrap에 composeLibrary.load().
   - `_runComposeJob(job)`: 모드 분기 — vocal: status→engineStatus 프리플라이트→submit→5초 폴링(detail/elapsed를 statusDetail로)→done 시 downloadOutput→Composition add / bgm: status 프리플라이트→generate→즉시 downloadOutput→add. 취소 시 폴링 중단(보컬)·응답 무시(BGM).
   - `enqueueCompose(...)` outcome: ok(jobId) / compose_server_offline / engine_offline / bgm_server_offline / local_ai_disabled(Phase 4에서 활성).
   - `refreshToolAvailability`에 8774·8766 status 편승(추가 타이머 없음) — Phase 4 전까지는 무조건 폴링, Phase 4에서 로컬AI ON 조건 추가.
   - 설정 `ollamaModel`(기본 'gemma4:12b') — prompter_settings에 추가.

## 테스트

- composition_test(roundtrip) · compose_job_queue_test(nextRunnable/replace/clearFinished) · song_compose_client_test(buildSongBody 클램프·vocal 매핑) · bgm_compose_client_test(buildGenerateBody) · ollama_client_test(body·파서·모델 판정).

## 완료 기준

- 단위 테스트 전체 통과 · (서버 기동 시) dart 코드 경유 BGM 1건 생성·다운로드 수동 확인 가능 상태.

## 주의

- 8766 산출물은 응답 즉시 다운로드(다음 생성 때 삭제됨). 8774는 보존되지만 동일하게 즉시 확보.
- Ollama 실패는 작곡을 막지 않는다(다듬기 생략 경로 유지).
