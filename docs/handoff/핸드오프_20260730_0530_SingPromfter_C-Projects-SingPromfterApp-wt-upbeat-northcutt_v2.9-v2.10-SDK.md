## 대상
- 프로젝트: SingPromfter
- 작업 폴더: C:\Projects\SingPromfterApp\.claude\worktrees\upbeat-northcutt-5f116e
- 세션 시각: 2026-07-30 05:30 (KST)

## 세션 요약
직전 핸드오프(20260729_1130) 이후 증분. 사용자 여정 전체 점검 계획(G0~G8)을 승인받아 v2.9.0으로 릴리스하고, 추가 요청 3건을 v2.10.0으로, 이어서 Flutter SDK 업그레이드까지 마쳤다. 새 곡 1건을 실사용으로 추가하며 빈틈 2건을 더 찾아 고쳤다. 모두 PR #2에 있고 CI 초록.

## 완료된 작업

### 커밋 (브랜치 `claude/upbeat-northcutt-5f116e`, PR #2)
- `5e90665` G0: 링크 하나 = 부를 수 있는 곡 — MCP/HTTP 기본 3슬롯 + 파이프라인 끝 싱크 자동 보정
- `e347c2e` G1: 가사 검색 근거 가드(duration ±7s + 가수 유사) — 「선물」 동명 곡 가사 사고 회귀 포함
- `1033797` G2: 제목 클리너에 가사 영상 계열 토큰((가사첨부)·[MV]·[4K] 등) 보강
- `ff4fbc9` G3: yt-dlp `--js-runtimes node:<절대경로>` 직접 전달 + 실패 안내 원인별 분기
- `208440a` G4: 노래 구간 기반 줄 배분(비-LRC) — 전주 대기·간주 정지·역함수, vocalseg 캐시
- `f44f5ed` G5: 드리프트 LRC 재타이밍(최소자승 scale+offset, R²≥0.95, .bak 백업)
- `ea4c3c9` G6: 분리 서버 자동 기동(파이프라인이 켜고 폴링, 홈 칩 눌러 켜기)
- `59232ad` G7: FakePlayback + 무대 위젯 테스트 4건 — 즉시 실버그 검출(드로어 24px 잘림, stageDrawerHeight 132→160)
- `051dbd2` release: v2.9.0
- `db93b97` ci: node 경로 테스트 플랫폼 무관화(리눅스 러너 .exe 없음)
- `5668a89` release: v2.10.0 — 곡 추가·곡 시작·서버 상태를 조작판으로 이동 / 라인시드 기본 글꼴(+글꼴 목록) / R 녹음 토글
- `58ff851` chore: Flutter 3.38.5→3.44.8 + axisAlignment→alignment, onReorder→onReorderItem(raw 변환은 QueueLogic.rawIndexForAdjusted 소유, 왕복 테스트)
- `1952d1a` fix: 괄호 밖 꼬리 홍보 문구(Official Video 등) 제거 — 실사용에서 발견

### 검증·배포
- analyze 이상 없음 · 테스트 **608건** · Windows 빌드 · `dist\SingPromfter` 배포(v2.10.0)
- PR #2: https://github.com/kuroicode-beep/SingPromfter/pull/2 — 전 커밋 CI(analyze/test/build-windows) 통과
- 실기 검증: 「넌 언제나」 재타이밍(재측정 오프셋 0), 「선물」 전주 대기·간주 정지 화면 확인, v2.10.0 3건 화면 확인, 링크 하나 bare-add 전 과정(분리 서버 자동 기동 포함) 성공

### 실사용 곡 추가 — 「봄이 와도 / 로이킴 (Roy Kim)」 (id 15dcbc35-6a12-45dc-bd27-2e3b2b94feef)
- 3슬롯(원곡 A♭ / MR A♭ / −2키 F♯) + 싱크 가사 29줄
- 가사는 LRCLIB에 영어 제목("When Spring Comes")으로만 등재 → 제목을 잠시 영어로 바꿔 fetch 후 복원하는 우회 사용
- 자동 싱크 맞춤은 "기준 지점 부족"으로 보수적 거부(노래가 이어지는 곡) — 실청 확인 권장

### 기존 곡 점검
- 「넌 언제나」: 정상. 슬롯3이 E로 들리는 건 구운 −2 + **저장된 사용자 키 −2**(pitchBySlot['3']=-2) — 데이터 오류 아님, 사용자 취향 값 여부만 확인 필요
- 「선물」: 정상(가사는 텍스트만 — LRCLIB에 없음). 삭제된 첫 등록의 고아 레벨 캐시 3건 정리함

## 진행 중 / 미완료 작업

### MCP 파이썬 레이어가 낡음 (다음 세션에서 자연 해소)
세션 시작 때 뜬 `singprompter` MCP 프로세스가 G0 이전 코드라 `mode:"asIs"`를 항상 붙여 보냄 → sp_add_song이 1슬롯만 만든다. 이번 세션은 HTTP 직접 호출(`POST /api/songs`에 url만)로 우회했다. **다음 Claude 세션부터는 새 tool/mcp/singprompter_mcp.py로 떠서 해소.** (.mcp.json이 메인 체크아웃을 가리키면 PR #2 머지도 필요)

### PR #2 머지 대기
13커밋 전부 CI 초록. 머지 후 worktree 정리 가능.

### 남은 개선 후보 (기록만)
- LRCLIB 영어 제목 폴백: 부제 괄호(예: 한글 제목 (English Title))의 영어 부분으로 재검색하면 「봄이 와도」류 우회가 자동화된다
- audioplayers 업그레이드 검토(coroutine silence 정의는 임시) — 별도 브랜치
- 「넌 언제나」 사용자 키 −2가 의도인지 확인

## 주요 결정사항 / 규칙 (증분)
- 곡 추가 기본 = 3슬롯+가사+싱크는 **앱 기본값**(v2.9.0) — 호출자는 링크만 넘긴다. mode/plan 명시 시 하위 호환
- 큐 재정렬 raw 인덱스 규약의 소유자는 QueueLogic — onReorderItem(보정 인덱스)은 `rawIndexForAdjusted`로 되돌려 태운다. API(sp_queue_reorder) 계약 불변
- flutter_test의 timersPending 검사는 addTearDown보다 먼저 돈다 — 위젯 테스트는 본문 안에서 트리 내리고 dispose
- 라인시드(LINESeedKR)가 앱 기본 글꼴. Regular 단일 웨이트 — 위계는 크기·색(볼드 합성 금지)
- 분리 서버 기동 명령은 pref `separator_start_command`(부팅 시 기본 경로 시드). 비우면 자동 기동 꺼짐

## 참고 정보
- 저장소: https://github.com/kuroicode-beep/SingPromfter (master = PR #1까지)
- PR #2: https://github.com/kuroicode-beep/SingPromfter/pull/2
- 로컬 Flutter: 3.44.8 (CI와 동일)
- 폰트 원본: LINESeedKR-Rg.ttf ← SVIL-Tarot/TXTSpace woff2에서 fontTools 변환, `assets/fonts/`
- yt-dlp 전역 설정(%APPDATA%\yt-dlp\config)은 이제 필수 아님(앱이 인자로 직접 전달) — 남아 있어도 무해
- 분리 서버: 현재 켜져 있음(자동 기동으로) — 안 쓰면 종료(VRAM)
- 완료보고서(v2.8.2까지): docs/reports/. v2.9~2.10 상세는 PR #2 본문과 커밋 메시지가 원본

## 다음 세션 시작 시 할 일
1. PR #2 머지 여부 결정 → 머지 시 MCP 레이어 불일치도 함께 해소
2. sp_add_song을 MCP로 한 번 호출해 3슬롯 기본이 MCP에서도 도는지 확인(새 세션이면 새 파이썬이 떠 있음)
3. 「봄이 와도」 실청으로 싱크 확인(자동 보정이 표본 부족으로 패스했음)
4. 「넌 언제나」 슬롯3 사용자 키 −2 의도 확인
5. (후보) LRCLIB 영어 부제 폴백 구현
