> 작업 폴더 전체 경로: `C:\Projects\SingPromfterApp\.claude\worktrees\upbeat-northcutt-5f116e`

## 대상
- 프로젝트: SingPromfter
- 작업 폴더: C:\Projects\SingPromfterApp\.claude\worktrees\upbeat-northcutt-5f116e
- 세션 시각: 2026-07-31 20:45 (KST)

## 세션 요약
직전 핸드오프(20260730_1815, v3.1.0) 이후 증분 — 16릴리스(v3.2.0 `1e9a073` → v3.17.0 `c5729b0`), 전부 실기 배포. "단축키가 안 먹는다" 실사용 보고에서 시작해 포커스 버그 3종·클램프 포화·피드백 부재를 파냈고, 사용자가 설계한 싱크 편집 키 일습을 얹었다. 곡 추가는 LRCLIB→받아쓰기 자동 폴백으로 완결, 로컬 서버는 앱이 수명 관리.

## 완료된 작업

### 곡 수정 창 (v3.2~3.3)
- 트랙별 재생 키 스테퍼 — 저장 버튼 없이 실시간 적용(400ms 디바운스·닫힘 플러시), 실효 조성 칩
- 구운 키 수정 박스 제거→고정 뱃지, 라벨·시작/끝은 '세부 설정' 접이식, 빈 슬롯 '없음+추가' 한 줄

### 단축키 안정화 (v3.4~3.6.1) — "먹었다 안먹었다"의 원인 3종
1. 다이얼로그·팝업 닫힘 후 **포커스 고아화** → FocusManager 리스너 자가복구(라우트 가드 포함)
2. **isTextInputFocused가 항상 false**(현 Flutter는 EditableText 내부 Focus에 노드가 붙음) → 조상 EditableTextState 탐색. 입력창 밖 클릭·ESC로 해제
3. **0.2초 싱크 이동은 눈에 안 보임** → 방향+누적값 스낵
- 물리 키(스캔코드) 판정 추가, 설정에 '단축키 진단'(이벤트 표시+key_diag.log)

### 싱크 편집 체계 (v3.7~3.13, 키맵 사용자 설계)
- 클램프 ±10초→**±60초** + 한계 도달 '한계값' 표시(실측: 노래방 트랙 −10초 포화가 "조용한 무시"로 이어짐)
- `←/→` 0.2초 · `Ctrl+←/→` 1초 · `Shift+←/→` 30초 시크 · `↑/↓` 줄 · `Shift+↑/↓` 볼륨
- `Alt+←/→` 부분 보정: **다음 줄부터** 아래만 LRC 타임스탬프 이동. 연속입력 배치 적용(500ms), 순서 보존 클램프(위 줄+10ms) — "가사가 춤을 춤" 수정
- `]` 싱크 대기(lyricsHold): 멈췄다 다시 누르면 기다린 시간을 오프셋으로 흡수
- `[`/T 리셋 · `D` 현재 줄 삭제 · `F` 실행취소(곡별 20단계, 메모리) · `G` .bak 복구(확인창) · `L` 잠금(Song.syncLocked, 곡 저장)
- 백업 정책: 파괴적 편집 전 .bak 자동, **새 가사 부착 시 옛 .bak·실행취소 무효화**

### 표시 (v3.14~3.15)
- 싱크 잠금 배지(우상단)·녹음 중 배지(우하단) — 메인·무대 공통. playback.syncLockedView/recordingView 거울 노티파이어 패턴

### 곡 추가 파이프라인 (v3.16)
- LRCLIB 실패 시 자동 **generateSttLyrics 폴백**(원곡 음원, metadata.duration 환청 가드)
- **ensureSttOnline**: STT(8769) 자동 기동 — pref `stt_start_command`, 기본 `C:\Projects\svil-ai-work\stt_system\start.bat`
- 비율 없는 단계는 홈 진행 스트립이 미정(흐르는) 진행바로(clearRatio 규약)

### 서버 수명 관리 (v3.17)
- `_startManagedServer`: cmd /c <bat>를 stdio 파이프 모드로 — **콘솔창 없음**
- `stopManagedServers`: taskkill /T /F 트리 종료 — dispose + AppLifecycleListener.onExitRequested(창 X). 외부에서 켠 서버는 불간섭

### 데이터 작업
- 「너를 사랑하고도」 LRC 손상(실험 중 오프셋 −10초 포화+타이밍 뒤섞임+D 오삭제) → **STT 재전사 3회로 복구, 최종 44줄**. 슬롯4 노래방 오프셋은 사용자가 [·]로 재조정 예정
- 「숙녀에게」(변진섭) 가사 수동 부착 — LRCLIB 없음 → STT 29줄 (id 7955851a)

## 검증
- analyze 0건 · 테스트 **752건**(+29: 다이얼로그 5·스코프 14·배지 2·lrc 8)
- 실기 v3.17.0 dist 배포·실행 중. 릴리스마다 배포→사용자 실청 피드백 루프

## 진행 중 / 미완료
- 「숙녀에게」 싱크 실청 미검증(받아쓰기 직후) — 확인 후 L 잠금
- 「너를 사랑하고도」 곡 끝 환청 줄 D 정리 진행 중(03:59·04:13 부근)
- 이월: 녹음 코치 실사용 검증, 박자 음표별 신축(DurationTier), PR #2 머지(46커밋), 남자키·선물·봄이와도 실청
- (주의) STT server.py를 PATH 파이썬으로 직접 켜면 faster_whisper 없어 500 — start.bat은 Python313 고정이라 앱 자동 기동은 안전

## 주요 결정사항 / 규칙 (증분)
- 싱크 편집 최종 키맵: `←/→` 0.2초 · `Ctrl` 1초 · `Alt` 부분(다음 줄부터) · `]` 대기 · `[`/T 리셋 · `D` 삭제 · `F` 실행취소 · `G` 복구(확인창) · `L` 잠금. **한 줄 간격 방식(v3.7)은 폐지**
- 가사를 고치는 모든 동작은 저장 직전 상태를 실행취소 스택에 쌓는다. L 잠금은 모든 싱크 조절 입구의 공용 가드(_syncLockBlocked)
- 부분 보정 기준 줄은 upcomingLineIndex(아직 시작 안 한 줄) — 간주에서 방금 부른 줄을 밀지 않는다
- 오프셋 한계에 닿으면 조용히 무시하지 않고 알린다(모든 클램프 공통 교훈)
- 앱이 띄우는 로컬 서버는 콘솔창 없이 + 앱 종료 시 동반 종료. 외부 기동분은 불간섭
- 배지 패턴: 상태 정본→playback의 표시용 ValueNotifier 거울→ValueListenableBuilder(플럼빙 없이 메인·무대 공유)

## 참고 정보
- PR #2: https://github.com/kuroicode-beep/SingPromfter/pull/2 (46커밋, 전부 push됨)
- 위키 섹션 09: https://outline.svil.kr/doc/singpromfter-TaJiToeqIy
- 완료보고서: docs/reports/완료보고서_20260731_v3.2-v3.17_싱크편집과안정화_ClaudeCode.md
- 서버: 분리 8771·STT 8769·pitch 8773 현재 전부 꺼짐(앱이 필요 시 자동 기동) · 제어 API 8772(앱)
- 데이터: C:\Users\kuroi\OneDrive\문서\data (songs.json·lrc/·mp3/)

## 다음 세션 시작 시 할 일
1. 「숙녀에게」 싱크 실청 → 필요시 ←/→·Ctrl·] 조정 → L 잠금
2. 「너를 사랑하고도」 곡 끝 환청 줄 D 정리 마무리 → L 잠금
3. 녹음 코치 실사용 검증(실녹음 1건 → 음정 체크 → AI 보정)
4. PR #2 머지 여부 결정(46커밋)
5. (제안) 빌드→dist 배포→재실행 루틴 스킬화
