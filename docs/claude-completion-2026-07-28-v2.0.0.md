# 완료 보고서 — v2.0.0 AI 보컬 분리 + SAW 연동 + 누락 보완

작성일: 2026-07-28
작성자: Claude Code
기준: v1.9.1(`aef358c`) → `2.0.0+1`

## A. SVIL 분리 서버 (SAW `separator_system`, 포트 8771)

- **demucs(htdemucs) + GPU** — py313에 이미 torch 2.10 cu128이 있어 demucs만 설치했다
- STT 서브시스템과 같은 패턴: `server.py` / `start.bat` / FastAPI, 동시 1작업(잠금)으로 GPU 보호
- **실동작 검증**: 합성 음원 분리 → GPU(RTX 5060 Ti)로 12.6초, no_vocals/vocals 경로 정상 반환
- SAW 전 계층 등록: `service_defaults`(포트·헬스경로·MCP base), `config.py`, `local_server_service`(시작 배치), `config.json`(+example), `endpoints.js`

## B. SAW 웹UI (요청: "웹UI는 SAW에 넣자")

- **음악 → 보컬 분리** 페이지: 드래그 업로드 → 분리 → 반주/보컬 받기, 서버 상태 카드(모델·장치·상태), 작업 이력
- STT 페이지 패턴 그대로: `pages/separator.html` + `js/modules/separator.js` + `js/api/separator-api.js`
- **메인(홈) 대시보드 카드 등록**: `service-registry.js`에 '보컬 분리 (demucs)' — 홈에서 서버 상태 확인·시작 가능
- 서빙 확인 완료(3000 응답), JS 문법 검증 통과

## C. MCP 도구 (요청: "mcp도 추가")

`svil_mcp.py`에 **`svil_separate_vocals`** 추가 — `audio_path`를 주면 분리 서버에 보내고 반주/보컬 로컬 경로를 반환. 서버가 꺼져 있으면 자동 기동 시도(STT와 동일 패턴). `TOOL_SERVICE`·`GPU_SERVICES`·`SHUTDOWN_SERVICE_IDS`에도 등록. 문법 검증 통과.

**주의: MCP·트레이가 새 도구를 보려면 SAW 서버/트레이 재시작이 필요합니다.**

## D. 앱 연동 (SingPromfter v2.0.0)

- 가져오기 반주 방식에 **"AI 보컬 분리 (demucs)"** 추가 — 다운로드 후 분리 서버로 보내 반주만 등록
- **홈 대시보드 서버 상태 표시줄**: 분리 서버 온라인/작업 중/꺼짐을 텍스트로, 60초 폴링 + 수동 새로고침
- AI 분리 모드 선택 시 가져오기 화면에도 서버 상태 표시

## E. 누락 보완 (요청: "누락된 부분도 같이")

| 항목 | 원출처 | 구현 |
|---|---|---|
| 유튜브 **최초 1회 동의 대화상자** | 저작권 방침(트랙 A) | 첫 가져오기 때 용도제한·책임소재 확인, prefs 저장 |
| **믹스다운** (녹음+반주 합치기) | v1.7 계획 | 녹음 시작 시점 재생 위치를 정렬점으로 저장 → ffmpeg adelay+amix. "반주와 합치기"/"합친 곡 듣기" 버튼 |
| **수동 .lrc 가져오기** | v1.5 계획 | LRCLIB에 없는 곡용 — .lrc 파일 선택 → 등록 → 싱크 모드 전환 |
| **yt-dlp 버전 표시 + 업데이트 버튼** | v1.4 리스크 대응 | 가져오기 화면에 버전(mono) + `yt-dlp -U` 실행 |
| **피치 캐시 정리** | v1.6 계획 | 라이브러리 정리에 변환 캐시 삭제 포함 |

## 검증

- `flutter analyze`: **No issues found** / `flutter test`: **211개 전체 통과** (+4)
- `flutter build windows --release` 성공
- 분리 서버: 실제 분리 E2E 성공(위 A) / SAW 백엔드·MCP 파이썬 문법 검증 통과

## 소장님 확인 필요

1. **SAW 재시작** — 백엔드(서버 시작 버튼·대시보드 카드)와 MCP 도구는 재시작 후 반영됩니다. 웹 페이지 자체는 새로고침만으로 보입니다.
2. 분리 서버는 현재 제가 띄워 둔 상태예요. SAW 홈 대시보드나 `separator_system/start.bat`으로 다시 켤 수 있어요.
3. 실제 곡으로: 가져오기에서 "AI 보컬 분리" 선택 → 반주 품질 확인
4. 녹음 → "반주와 합치기" → 정렬이 맞는지 (밀리면 곡을 처음부터 재생하며 녹음해 보세요)

## 남은 항목 (의도적 보류)

- whisper 가사 자동 정렬(v1.5 스트레치) — LRCLIB 미적중 곡이 실제로 불편해지면 착수
- v1.9 계획의 다중 선택·태그 — 사용 패턴을 보고 결정
- 공개 배포판 저작권 재검토(트랙 B)
