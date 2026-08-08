# 핸드오프 — SingPromfter v3.0.0 "AI 스튜디오" 완료

- 일시: 2026-08-08 21:00 KST · 작업자: Claude Code (Opus 5)
- 프로젝트: SingPromfter · 작업 폴더: `C:\Projects\SingPromfterApp` (워크트리 upbeat-northcutt-5f116e에서 작업 후 master 병합·정리 완료)
- 상태: **v3.0.0 릴리스 완료** — master 병합(9007492), GitHub Release 발행, 홈페이지 갱신

## 이번 세션에서 한 일

v2.8.3 → **v3.0.0 메이저 업데이트** 전체(Phase 0~9)를 한 세션에서 완료.

1. **문서 스위트**: PRD·기술 스펙·아키텍처·로드맵·Phase별 작업지시서 6부 (`docs/`), Outline 위키 갱신
2. **녹음 3트랙**: 보컬(마이크)·반주(실재생 파일 구간 잘라내기 — 키/템포 변형본 반영)·믹스 각각 저장, 폴더 내보내기. 변형본 녹음이 원키 반주와 믹스되던 잠재 버그 해결. recordings.json v2(additive)
3. **믹싱 스튜디오**: 테이크별 밸런스(mixGains)·리버브 3종(aecho)·노이즈 제거(afftdn)·AI 테이크 보컬 분리(8771)·재믹스(임시 파일→교체)
4. **녹음 설정**: 입력 장치 선택·입력 볼륨(캡처 시점 게인, 0~200%)·마이크 테스트 레벨 미터
5. **작곡 탭**: 보컬곡=SAW 작곡 게이트웨이 8774(**ACE-Step 1.5 터보**, 잡 폴링으로 VRAM 순번·진행 실표시, 3~10분) / BGM=8766(MusicGen, 30초~5분, 프리셋) · Ollama(**gemma4:12b**) 프롬프트 다듬기(실패 시 원문 진행)·가사 구조 태깅 · seed 변주 3개 · 노래방 세트(분리 MR+균등 LRC+DSP 정렬) · 기존 곡 반주 부착 · compositions.json v1 신설
6. **AI 게이트**: 로컬AI/클라우드AI 스위치 기본 OFF, 켜기 안내 팝업, OFF 시 작곡 탭·AI 분리 비활성(보이되 클릭 불가)+API/MCP 403 local_ai_disabled. 클라우드AI는 예약 토글(현재 기능 없음)
7. **MCP/API**: /api/compose·/api/recordings 라우트 + sp_compose 계열 7종 (`tool/mcp/singprompter_mcp.py`)
8. **QA**: analyze 0건 · 테스트 618개 통과 · 릴리스 빌드+실행 스모크(제어 API state=3.0.0)+배포 zip 단독 실행 검증
9. **릴리스**: 홈페이지(gh-pages) v3.0 카드 5개 언어 반영·발행(라이브 확인) · `SingPromfter_v3.0.0_win64.zip`(28.8MB) · [GitHub Release v3.0.0](https://github.com/kuroicode-beep/SingPromfter/releases/tag/v3.0.0) · PR #3 CI 통과 후 master 병합 · 워크트리/브랜치 정리 · 바탕화면 바로가기 생성 · Vault docs 동기화

## 핵심 기술 결정 (다음 세션 참고)

- 반주 "녹음" = 루프백 캡처가 아니라 **재생하던 파일에서 ffmpeg -ss/-t 구간 잘라내기** (녹음 종료 직후 즉시 — 변형본 캐시 삭제 대비 자립화)
- 보컬곡 백엔드 = **8774 compose 게이트웨이** (8766의 acestep/ComfyUI 체인은 사용 안 함 — 잡 기반·VRAM lease·산출물 보존이 상위 호환). SAW 측 MCP(svil_generate_song)는 기존 것 그대로
- 8766 BGM은 생성 직후 이전 산출물을 지우므로 응답 즉시 `/output` HTTP로 확보
- AI 게이트 검사는 AppController 단일 지점(enqueueImport aiSeparate·enqueueCompose·separateTake) → UI·API·MCP 삼면 동일 차단
- 설정은 PrompterSettings 단일 쓰기 경로 유지 (+recordingDeviceName·recordingGain·localAiEnabled·cloudAiEnabled·ollamaModel)

## 남은 것 / 다음 후보

- **수동 청취 검증** (소장님): 완료보고서의 체크리스트 — 키조절 녹음 믹스 키 일치, 리버브/노이즈 청취, 작곡 E2E(SAW 서버 기동 필요: separator 8771·compose 8774+ACE 8001·bgm 8766·Ollama gemma4:12b)
- Ollama 11434 인스턴스가 모델 0개로 응답 중이었음 — gemma4:12b가 다른 인스턴스에 있다면 설정에서 모델명 확인(`설정→작곡→모델 확인` 버튼)
- 다음 버전 후보: 실시간 이펙트 모니터링(WASAPI), whisper 정밀 LRC, 클라우드 LLM 다듬기(DeepSeek·SAW 경유), 믹스 마스터링(loudnorm)

## 참조

- 완료보고서: `docs/reports/완료보고서_20260808_v3.0.0_AI스튜디오_ClaudeCode.md`
- 스펙/아키텍처: `docs/스펙_20260808_v3.0.0_AI스튜디오_ClaudeCode.md` · `docs/architecture/아키텍처_20260808_v3.0.0_ClaudeCode.md`
- Outline: "SingPromfter 아키텍처"(v3.0.0 갱신) · "SingPromfter v3.0.0 AI 스튜디오 — PRD·로드맵"
- 홈페이지: https://singpromfter.svil.dev (v3.0 카드 반영)
- 커밋: fcb6e0c(문서) → 4개 기능 커밋 → 9c94d92(버전) → 9007492(merge)
