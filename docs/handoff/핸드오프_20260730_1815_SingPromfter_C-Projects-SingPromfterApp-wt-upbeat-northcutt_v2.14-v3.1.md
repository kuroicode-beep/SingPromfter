## 대상
- 프로젝트: SingPromfter
- 작업 폴더: C:\Projects\SingPromfterApp\.claude\worktrees\upbeat-northcutt-5f116e
- 세션 시각: 2026-07-30 18:15 (KST)

## 세션 요약
직전 핸드오프(20260730_0832, v2.13.0) 이후 증분 — 11릴리스. 큰 덩어리 셋: v3.0.0 녹음 코치(음정·박자 채점+AI 보정, 새 로컬 서버), UX 개편(곡 목록 드래그 재정렬·드로어 재배치·전체 테두리 선택), 단축키 체계 확립(자판 무관 판정·PrompterActions 단일화). 전부 실기 배포.

## 완료된 작업

### 커밋 (PR #2, `dd3b0cc`→`a98bddb` 11건 + svil-ai-work `2079fb0`)
- `dd3b0cc` v2.13.1 단축키 탭 게이트(홈·즐겨찾기·무대만)
- `7f2fd95` v2.14.0 곡 목록 드래그 재정렬 — SongSortMode.manual, applyVisibleReorder(필터 중에도), songSortMode 설정 저장
- `2701ded` v2.14.1 선택 곡 전체 테두리
- `3a14e18` v2.15.0 [받아쓰기 AI](SttLyricsClient→8769) + 인라인 가사 수정(길게 누르기, replaceLrcLineText 시각순 규약)
- `e53b165` v2.16.0 예약 큐 상단 고정·토글(queueSidebarOpen 기본 열림) + 재생바 드로어(playbackBarOpen 기본 숨김)
- `0563ad3` v2.17.0 T=리셋·`.`늦춤·`/`앞당김·E=편집(ESC 저장, LineEditRequest seq 규약)
- `e081a98` v2.17.1 일시정지 즉시 재계산(applyLyricsOffset) + Shift 잔상 `>`·`?` 수용
- `8de8d0c` v3.0.0 녹음 코치 — 아래 상세
- `b7113ab` v3.0.1 문장부호 3겹 판정(논리키+Shift잔상+실제 문자)+예비 `[`·`]` · 맨휠 제거·O/P · 설정 단축키 안내
- `32cbdf0` v3.0.2 무대=메인 동기화(Space·R·E·싱크 줄) + **PrompterActions**(prompter_keyboard_scope.dart) 단일화
- `a98bddb` v3.1.0 드로어 숨김=실공간 반환(손잡이 한 줄 <90px, 무대 stableStage 보정 제거 +216px)

### v3.0.0 녹음 코치
- 새 서버 `C:\Projects\svil-ai-work\pitch_system`(8773, start.bat): torchcrepe(GPU) f0 비교 분석 + parselmouth PSOLA 보정. 합성 검증 +50센트/+100ms → ±3센트/0ms(점수 56→98)
- 앱: 녹음 목록 [음정 체크](PitchReportDialog)·[AI 보정](목소리만/반주와 믹싱). 보정본=새 테이크(correctedFrom, 'AI 보정본' 배지). PitchCoachClient(lib/services/pitch_coach_client.dart)
- 기준 보컬 = 분리 서버 vocalsPath(AppController.vocalStemForSong), 전조 = takeTranspose(구운 키+사용자 키)
- STT 서버(8769) 확장: with_segments=1·vad=0 — 기존 클라이언트 무영향

### 검증·배포
- analyze 0건 · 테스트 723건 · dist 배포 v3.1.0 실기 확인
- 완료보고서: docs/reports/완료보고서_20260730_v2.14-v3.1_녹음코치와UX개편_ClaudeCode.md
- 위키 섹션 08: https://outline.svil.kr/doc/singpromfter-TaJiToeqIy

## 진행 중 / 미완료 작업
- **녹음 코치 실사용 미검증** — 실녹음으로 [음정 체크]·[AI 보정] 귀 검증 필요(합성 검증만 완료). pitch 서버(8773) 켜져 있음
- 박자 보정은 전체 오프셋만(음표별 신축 후속)
- 이월: 남자키 −5/−7 실청, 「선물」·「봄이 와도」 싱크 실청
- PR #2 머지 여부(30커밋)

## 주요 결정사항 / 규칙 (증분)
- **PrompterActions**: 홈·무대 공용 동작 묶음 — 새 단축키/동작은 actions 필드+스코프 처리기 한 곳. 두 화면 개별 배선 금지
- 단축키 최종: Space·F5·ESC·R·T·E·O/P·`.[`·`/]`(꾹=연속)·←→·Home/End·↑↓·Ctrl/Alt/Shift+휠. **맨휠 없음**(Alt 상태 새는 이벤트 무시용). 설정 탭에 안내 표
- 문장부호 단축키는 실제 입력 문자까지 3겹 판정(한글 자판 OEM 매핑 대응)
- 오프셋 변경은 즉시 줄 재계산 — 위치 틱 의존 금지
- 곡 순서=songs.json 나열 순서 정본, 드로어 닫힘=실공간 반환
- 사용자 전역 규칙: **테스트용 터미널·앱 창은 사용 끝나면 닫기**(메모리 close-test-windows.md 저장됨)
- "오픈AI 엔진" 요청은 로컬 오픈 AI 엔진(torchcrepe/PSOLA)으로 해석 — OPENAI_API_KEY 부재

## 참고 정보
- PR #2: https://github.com/kuroicode-beep/SingPromfter/pull/2
- 서버: pitch_system 8773(켜짐) · stt_system 8769(꺼짐) · 분리 8771(꺼짐) · 제어 API 8772(앱)
- svil-ai-work 저장소에 pitch_system/stt 변경 커밋됨(`2079fb0`) — backend/services/oneshot_service.py 수정본은 내 것 아님(미커밋 유지)

## 다음 세션 시작 시 할 일
1. 실제 녹음 1건으로 [음정 체크] → [AI 보정](믹싱까지) 전 과정 검증
2. 박자 음표별 신축 보정 검토(pitch_system DurationTier)
3. PR #2 머지 여부 결정
4. 이월 실청 항목들(남자키·선물·봄이와도)
