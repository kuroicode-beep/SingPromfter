> 작업 폴더 전체 경로: `C:\Projects\SingPromfterApp\.claude\worktrees\upbeat-northcutt-5f116e` (제목 100자 제한 때문에 폴더명을 줄였습니다)

## 대상

- 프로젝트: SingPromfter
- 작업 폴더: C:\Projects\SingPromfterApp\.claude\worktrees\upbeat-northcutt-5f116e
- 세션 시각: 2026-08-04 08:00 (KST)

## 세션 요약

직전 핸드오프(v3.19.2, 2026-08-01) 이후 증분. 사용자 요청을 따라 v3.20.0~v3.27.0 열 개 릴리스(트레이닝 4주 코스, 폴더/예약큐 3슬롯, MR 내보내기, 듀엣 합성, 보더리스 풀스크린, 제어 API view/screenshot)를 배포하고, 랜딩 페이지를 gh-pages로 공개했으며 Ghost 소개 포스트를 발행했다. 곡 데이터로는 「사랑말(최인경)」을 추가하고 가사 누락을 재생성으로 복구했다.

## 완료된 작업

### 릴리스 (전부 실기 배포, analyze 0건 · 테스트 779건)

- `186dcf5` v3.20.0 — 트레이닝 4주 코스(주차 테마·요일 달성 점·회차 순환)+달성률 카드+루틴 카드형(딕션·10분 데일리, 웹 리서치 기반), 녹음 플레이어(시크바), 알림을 중앙 대형 오버레이 토스트로(삭제 실행취소 포함)
- `68cef59` v3.21.0 — 곡 목록 1단계 폴더(Song.folder, 수정 다이얼로그 지정+기존 폴더 칩, 트리 기본 닫힘, 검색 중 평탄화, PATCH /api/songs folder)
- `018c22a` v3.22.0 — 재생바 [MR 내보내기](제목_라벨.mp3, 중복 번호)
- `b7542f0` v3.23.0 — 새 폴더 버튼·폴더 ▲▼ 순서·펼침 영속(settings.folderOrder/expandedFolders) + 예약 큐 3슬롯 탭(repo가 활성 슬롯 기억, 기존 큐=큐1) + 내보내기 폴더 설정(exportFolder)
- `c5a1734`/`8d048b0` v3.24.0/1 — 곡 드래그→폴더 드랍 이동(⠿ 손잡이) + 곡 위 드랍으로 순서 변경(displayIds 좌표계, applyVisibleReorder 규약 재사용, 폴더 이동과 순서 저장 순차 처리)
- `7fa06cb` v3.25.0 — 녹음 입력장치 설정(설정>녹음, recordingDevice 영속, 부팅 시 장치 우선 지정 후 목록 로드) + 듀엣 합성(DuetMixDialog, buildDuetMixArgs: 반주+보컬2 amix=3/duration=first, 무반주면 2/longest, 테스트 2건, 결과는 새 테이크)
- `b2b67a8` v3.26.0 — 보더리스 풀스크린(window_manager ^0.5.2) + F11 전역 토글(HardwareKeyboard 핸들러)
- `7100136` v3.26.1 — Shift+Enter 줄바꿈(NewlineShortcutScope — 데스크톱 기본 매핑 부재 보완, 한 줄 입력 제외, 테스트 3건)
- `2a32be0` v3.27.0 — 제어 API POST /api/view {name}(탭·stage·back, AppController.onNavigate) + POST /api/screenshot {path}(RepaintBoundary 캡처, appCaptureBoundaryKey)
- `b391e0e` — 랜딩 히어로에 Stitch 일러스트 배경(site/assets/hero.jpg 84KB, 오버레이 0.82~0.97)

### 대외 공개

- 랜딩(gh-pages, svil-landing-page 스킬 규격): https://kuroicode-beep.github.io/SingPromfter/ — 저시력 취지 전면, 최소 사양(AI 포함), 설치법(공개 clone), 토스 QR 후원, SVIL 표준 푸터, 5개 언어. features.html에 실스크린샷 5장(제어 API로 촬영). 라이브·에셋 200 확인.
- Ghost 포스트(published): https://ghost-production-0ec2.up.railway.app/jeosiryeogeul-wihan-noraebang-peurompeuteo-singpromfterreul-sogaehabnida/ — 12섹션·이미지 6장(실스크린샷 5)
- 저장소 PUBLIC 확인: https://github.com/kuroicode-beep/SingPromfter

### 곡 데이터

- 「사랑말 / 최인경」(id 19edbaf6-4bbc-425b-9c0e-0a8cc3b9cdc2) 추가 — 유선 폴더, 3슬롯, 조성 F
- 가사 누락 복구(08-04): DeepSeek 검증이 라이브 소절 과필터 → useVocalStem=true·useDeepSeek=false로 재생성, 21줄→24줄(00:00~03:08 전 구간). 이전본은 세션 스크래치패드 sarangmal_v2.lrc

### 기록

- 완료보고서: docs/reports/report_20260804_v3.20-v3.27_트레이닝코스-폴더큐-듀엣-랜딩_클로드코드.md
- Outline 위키 섹션 10 추가: https://outline.svil.kr/doc/singpromfter-TaJiToeqIy
- 메모리: encoding-pitfalls(PS1 BOM·commit 따옴표·JSON BOM·Set-Content ANSI·REST 한글 body 등 7케이스)

## 진행 중 / 미완료 작업

- 사랑말 오인식 단어 잔존(꼬이/조개무습 등) — 사용자가 정답 가사 텍스트를 주면 정렬 옵션으로 교정
- Stitch 히어로 오버레이 농도 피드백 대기
- PR #2 머지 여부(60+ 커밋 누적), 녹음 코치 실사용 검증, 배치 중 원인불명 앱 크래시 1회 관찰 항목 유지

## 주요 결정사항 / 규칙 (증분)

- 라이브 음원 가사 재생성은 DeepSeek 검증을 끌 수 있어야 한다(소절 과필터). regenerate API의 useDeepSeek=false 경로 실증.
- OS 화면 캡처·입력 시뮬레이션 스크립트는 Defender AMSI가 차단 — 앱 자체 기능(API)으로 해결하는 것이 정석. /api/view·/api/screenshot이 그 결과물.
- 알림은 하단 스낵바 금지 — SnackMessage가 중앙 대형 오버레이 토스트(전역 유일 경로).
- 예약 큐 저장은 repo가 활성 슬롯을 기억(queue getter/setter는 활성 슬롯 별칭) — 기존 서비스 코드는 슬롯 무지 상태로 동작.
- 커밋 메시지에 큰따옴표 금지(PS 5.1 인자 분해), .ps1은 ASCII 전용 또는 UTF-8 BOM.

## 참고 정보

- 저장소: https://github.com/kuroicode-beep/SingPromfter (PUBLIC, master / 작업 브랜치 claude/upbeat-northcutt-5f116e)
- 배포본: C:\Projects\SingPromfterApp\dist\SingPromfter\singpromfter_app.exe (v3.27.0 실행 중)
- 랜딩 배포: 프로젝트 루트 publish_site.ps1 (site/ → gh-pages)
- 데이터: C:\Users\kuroi\OneDrive\문서\data (songs.json은 BOM 없는 UTF-8 유지)
- 제어 API: 127.0.0.1:8772 — 신규 /api/view, /api/screenshot 포함

## 다음 세션 시작 시 할 일

1. 사랑말 정답 가사 받으면 정렬 실행(가사 다시 생성 > 정답 가사)
2. 랜딩 히어로 오버레이 농도·문구 사용자 피드백 반영
3. PR #2 머지 전략 결정(스쿼시 권장 규모)
4. (이월) 녹음 코치 실사용 검증, 듀엣 합성 실녹음 검증
