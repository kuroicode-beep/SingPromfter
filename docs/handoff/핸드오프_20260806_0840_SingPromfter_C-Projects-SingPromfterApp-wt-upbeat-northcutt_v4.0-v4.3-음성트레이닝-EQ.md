> 작업 폴더 전체 경로: `C:\Projects\SingPromfterApp\.claude\worktrees\upbeat-northcutt-5f116e` (제목 100자 제한 때문에 폴더명을 줄였습니다)

## 대상

- 프로젝트: SingPromfter
- 작업 폴더: C:\Projects\SingPromfterApp\.claude\worktrees\upbeat-northcutt-5f116e
- 세션 시각: 2026-08-06 08:40 (KST)

## 세션 요약

직전 핸드오프(v3.20~v3.27, 2026-08-04) 이후 증분. 사용자 요청 대량 업데이트를 v4.0.0 단일 릴리스로 계획 승인받아 구현하고, 이어진 피드백 6건을 v4.1.0~v4.3.0으로 반영했다. 핵심: 트레이닝 전 구간 음성 안내(내장 TTS), 상단 메뉴 9개 분리, 유튜브 차트 확장+미리듣기, MR4 자동 검색, 도움말 탭(TTS 낭독), 우주 배경 5단계(B 순환), EQ 노래방 스타일 풀와이드 개편. 전부 실기 배포·캡처 검증.

## 완료된 작업 (릴리스별)

| 버전 | 커밋 | 내용 |
|---|---|---|
| v4.0.0 | 61f6553 | 음성 안내 대개편(아래 상세) |
| v4.1.0 | f2f286f | EQ 연출 강화 + 우주 배경 신설(B 토글) |
| v4.1.1 | ae41a0d | 우주 배경 보강 + 움직임 줄이기 무시(사용자 지정) |
| v4.1.2 | 80acd9b | 우주 배경 부각(심우주 워시·별 230) |
| v4.2.0 | df0f170 | 우주 배경 5단계 패턴 + B 순환 + 스낵 안내 |
| v4.2.1 | 38c0b25 | 알림 표시시간 2배(2.6→5.2초) |
| v4.3.0 | 063b2f6 | EQ 풀와이드 개편(곡선·비트 글로우·파티클) |
| docs | 1ecbfdd | 완료보고서 |

### v4.0.0 상세

- **트레이닝 따라하기 세션**: `TrainingSessionController`(lib/controllers/) 상태기계 — 시작 안내→(코스 주차 브리핑)→스텝 안내→자동 진행→자동 체크(DailyGoalService.markStepDone, 기존 ≥30초 곡 자동체크와 멱등 수렴). 호흡=박자 큐(`BreathingPattern`, routine_step_spec.dart 병렬 테이블), 스케일=남/녀 음역 피아노 5음 런(설정 trainingVoiceRange, 남 C3~C4/여 +5st, run_48~65.wav 재사용). 제어: Space=일시정지/재개·Home=섹션 재시작(PrompterKeyboardScope overrideHandler — 트레이닝 탭에선 다른 기본 매핑 차단)·건너뛰기·종료. 러너 카드는 인패널(training_session_card.dart) — 곡 스텝 중 탭 이동 가능.
- **TTS 에셋 파이프라인**: 정본 `lib/constants/voice_clips.dart`(클립 76개, 단축키 낭독은 app_shortcuts.dart에서 파생) ↔ `tool/gen_audio/generate_tts.dart`(8765 female_calm, 멱등, --force). 피아노는 `generate_piano.dart`(배음 합성, 서버 불필요). WAV는 커밋됨 — **빌드·런타임에 TTS 서버 불필요**. 재생은 `GuideAudioService`(AssetSource, 음성/피아노 전용 AudioPlayer 2개, GuideAudio 인터페이스로 테스트 주입).
- **메뉴 9개**: AppDestination 재구성(home/search/youtube/favorites/training/recordings/jobs/help/settings). SearchHubPanel 삭제. 유튜브 탭 첫 진입 lazy 차트는 `_changeDestination`이 담당.
- **유튜브**: mostPopularTop100(KR 한글 휴리스틱 필터·US, 페이지네이션 최대 4), decadeChart(연대×장르 search 프리셋 — [불러오기] 명시 버튼+조합 캐시만, 100유닛/회), 미리듣기=url_launcher 새 창. 차트 칩 4종+순위 표시.
- **MR4 자동 검색**: AddTrackDialog에 `노래방 반주 자동 검색` → sealed AddTrackChoice → `_startKaraokeAutoSearch`(유튜브 탭 전환+"제목 가수 노래방" 검색+대상 배너) → [가져오기]가 `showKaraokeKey`(키만 선택) → 원곡 4번 슬롯 직행(저작권 게이트 유지, 성공 시 타깃 해제+홈 복귀).
- **도움말 탭**: help_panel.dart — 단축키 표(정본 lib/constants/app_shortcuts.dart, 설정 탭과 공유) + 행별/전체 TTS 낭독(탭 이탈 시 정지).
- **단축키**: `+`/`-` 볼륨, `PgUp`/`PgDn` 10초(seekStepMedium) — 홈·무대 공용.

### v4.1~v4.3 상세

- **우주 배경**(`lib/widgets/prompter_space_background.dart`): 설정 `spaceBackgroundLevel`(0~5, v4.1 bool에서 자동 이관) + **B 순환**(1→…→5→끄기, 단계명 스낵 — 홈은 song_list_screen, 무대는 prompter_screen `_cycleSpaceBackground` 로컬 소유+위로 통지). 패턴: ①성야 ②오로라(컬럼 가산 커튼, 2배폭 겹침으로 이음선 제거) ③회전 나선은하(3팔 240입자, 정적 프리컴퓨트+회전) ④유성우(4줄기 시드 분리) ⑤스톰(성운 맥동+폭발 링+쌍별똥별). 시스템 '움직임 줄이기' 비연동(사용자 지정 — B로 직접 제어). 33ms 스로틀, repaint notifier, 무대 테스트는 `spaceBackgroundLevel: 0`(영구 Ticker가 pumpAndSettle을 막음).
- **EQ**(`lib/widgets/prompter_eq_meter.dart`): 무대·홈 풀와이드(`PrompterStageMetrics.meterWidthRatio 1.0`, 홈은 72px). Catmull-Rom 스펙트럼 곡선+가산 면, 비트 글로우(평균 급등>0.045 점화·지수 감쇠), 비트 파티클(급상승 스폰, 상한 90, clipRect로 가사 침범 방지), 스윕·스파크·피크 잔광·앰버 핫팁. blur 프레임당 1회 규칙 유지(막대+곡선을 Path 하나로).
- **알림**: SnackMessage 기본 5.2초.

### 검증·배포·기록

- analyze 0건 · 테스트 **813건** · CI(analyze/test/**build-windows까지**) 전부 green
- dist 배포: `C:\Projects\SingPromfterApp\dist\SingPromfter\singpromfter_app.exe` (v4.3.0 실행 중)
- 실기 캡처: 제어 API(8772) /api/view+/api/screenshot — 전 탭, 우주 배경 2/3/5단계(설정 파일 스왑 방식), EQ는 /api/playback/play 재생 중 캡처
- 완료보고서: `docs/reports/완료보고서_20260805_v4.0.0-v4.3.0_음성트레이닝-메뉴개편-우주배경-EQ_ClaudeCode.md`
- Outline 위키 섹션 11: https://outline.svil.kr/doc/singpromfter-TaJiToeqIy

## 진행 중 / 미완료 작업

- **사용자 실청 검증(전부 미완)**: ① 트레이닝 따라하기 1회(음성 음질·호흡 리듬감·피아노 음역) ② 도움말 전체 듣기 ③ MR4 자동 검색 1건 ④ EQ·우주 배경 실감(후렴 구간, B 순환)
- 국내 TOP100 곡 수 적음(mostPopular 카테고리 한계+한글 필터, 캡처 시 6곡) — 체감 후 필터 조정 여지
- PR #2 머지 결정 대기(80+ 커밋, 스쿼시 권장)
- (이월) 사랑말 정답 가사 정렬(id 19edbaf6-4bbc-425b-9c0e-0a8cc3b9cdc2), 랜딩 히어로 피드백, 배치 중 크래시 1회 관찰 유지

## 주요 결정사항 / 규칙 (증분)

- TTS는 **개발 시 사전 생성·앱 내장**이 기본(스킬 svil-tts-settings의 "앱은 HTTP 직접" 규칙은 동적 문구일 때만). 문구 수정 시: 해당 wav 삭제 → generate_tts.dart 재실행. GPU 경합 주의 — ComfyUI 큐가 돌면 8770이 502로 죽는다(큐 소진 후 생성).
- 우주 배경은 시스템 '움직임 줄이기'를 따르지 않는다 — B 단축키가 유일 제어(2026-08-05 사용자 지정).
- 알림 오버레이 기본 5.2초(2026-08-05 사용자 지정).
- 트레이닝 탭 단축키는 overrideHandler 패턴 — 세션 중 Space/Home만 세션 제어, 나머지 기본 매핑은 skipRemainingHandlers로 차단.
- EQ·배경 연출 추가 시 blur는 프레임당 1회, 파티클류는 상한+clipRect.

## 참고 정보

- 저장소: https://github.com/kuroicode-beep/SingPromfter · PR #2: https://github.com/kuroicode-beep/SingPromfter/pull/2
- 제어 API: 127.0.0.1:8772 — /api/view·/api/screenshot·/api/playback/*
- TTS 생성 체인: svil_start_service tts(8765 프록시)+qwen3tts(8770) — 현재 꺼짐(VRAM 반환)
- 설정: %APPDATA%\com.svil\singpromfter_app\shared_preferences.json (spaceBackgroundLevel 등)
- 데이터: C:\Users\kuroi\OneDrive\문서\data (songs.json BOM 없는 UTF-8)

## 다음 세션 시작 시 할 일

1. 사용자 실청 검증 4건(위) → 피드백 반영(농도·양·속도 수치 조절)
2. 국내 TOP100 필터·곡수 피드백 반영
3. PR #2 머지 전략 결정(⚠ 사용자 결정)
4. (이월) 사랑말 정답 가사 정렬, 녹음 코치·듀엣 실사용 검증
