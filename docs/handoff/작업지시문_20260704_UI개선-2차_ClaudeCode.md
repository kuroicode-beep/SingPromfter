---
title: "작업지시문 - UI 개선 2차"
created: "2026-07-04"
updated: "2026-07-04"
owner: "InBlue"
author: "ClaudeCode"
status: "active"
type: "spec"
project: "SingPromfter"
tags:
  - ui
  - sprint
visibility: "internal"
---

# 작업지시문 — UI 개선 2차 (SingPromfter v1.1.0 → v1.1.1)

기준 커밋: `bbf7998` (v1.1.0)

## 수용 기준 (공통)

**어떤 창 폭에서도 UI 요소·버튼 라벨 잘림 0건**

- 버튼 라벨은 `Expanded`로 압축하지 않는다. `Wrap` 또는 고정 `minimumSize` 사용.
- 터치 타겟 최소 50dp (`AppConstants.minTouchTarget`).

---

## T1 — 상단 탭 전환

- 좌측 레일(240px) 제거
- 상단 바 한 줄: 로고 + 탭(홈/곡 검색/즐겨찾기/설정) + [곡 등록]
- 가로 240px 확보

구현: `lib/widgets/app_top_nav_bar.dart`, `song_list_screen_view.dart`

---

## T2 — 카드 버튼 정리

- **[선택] 버튼 삭제** (카드 탭과 중복)
- **[수정]/[삭제]**: 선택된 카드에서만 표시
- **항상 표시**: [예약]/[시작]
- `Expanded` 압축 구조 제거 → `Wrap` + `minimumSize`

구현: `lib/widgets/song_tile.dart`

---

## T3 — 하단 컨트롤 바 재구성

- 가로 스크롤(`SingleChildScrollView`) 제거
- **재생 바(항상 표시)**: 정지/재생/처음부터/다음/전체화면 + 진행률 + 볼륨·배속
- **표시 설정(접이식)**: 크기·줄간격·속도·프리셋·폰트·굵게·표시 모드

구현: `lib/widgets/prompter_bottom_bar.dart`

---

## T4 — 가사·큐 영역

- 가사 하단 패딩 보강 (잘림 방지)
- 빈 예약 큐(320px) → 접이식 사이드바 (52px 접힘)

구현: `prompter_panel.dart`, `collapsible_queue_sidebar.dart`

---

## T5 — 잔손질

1. 좁은 창 탭 `프롬pter` → `프롬프터`
2. Copyright 문구 → 설정 화면
3. `minTouchTarget` 48 → 50
4. [곡 시작] 비활성 시 "곡 선택 필요" 표시
5. 곡 없음 안내: "상단의 곡 등록으로…"
6. `prompter_panel` 중복 진행률 바 제거

---

## 완료 시

- `pubspec.yaml` → `1.1.1+1`
- `flutter analyze` / `flutter test` / `flutter build windows`
- 태그 `v1.1.1` 권장
