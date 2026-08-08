# 작업지시문 — Phase 6: MCP/제어 API 확장 (v3.0.0)

- 작성일: 2026-08-08 · 담당: Claude Code · 선행: Phase 5 완료

## 목표

작곡·녹음을 제어 API(:8772)와 singprompter MCP(sp_*)로 노출한다. SAW 측 MCP(svil_generate_song)는 이미 존재 — SAW 쪽 작업 없음.

## 작업 항목

1. **`lib/services/control_server.dart` 라우트** (record-pattern switch에 추가, 로컬AI OFF면 403 `local_ai_disabled`)
   - `POST /api/compose` — 생성 시작(body: mode·title·prompt·lyrics·vocalType·genre·bpm·durationSec·seed) → {jobId}
   - `GET /api/compose` — 생성 목록 · `GET /api/compose/jobs` — 잡 목록
   - `POST /api/compose/jobs/<id>/cancel` · `DELETE /api/compose/<id>`(confirm 정책) · `POST /api/compose/<id>/register`
   - `GET /api/recordings` — 테이크 목록(메타만) · `POST /api/recordings/<id>/mix` — 재믹스 트리거
2. **`tool/mcp/singprompter_mcp.py`**: `sp_compose`·`sp_compositions`·`sp_compose_cancel`·`sp_compose_register`·`sp_recordings`·`sp_take_mix` — TOOLS 스키마 추가, 파괴적 도구는 `confirm=true` 요구(기존 규칙).
3. **테스트**: `test/services/control_router_test.dart` 확장 — 라우트 왕복·403 게이트·confirm 검증.

## 완료 기준

- 라우터 테스트 통과 · 앱 기동 상태에서 sp_compose로 BGM 1건 생성 왕복 확인 · 기존 sp_* 회귀 없음.
