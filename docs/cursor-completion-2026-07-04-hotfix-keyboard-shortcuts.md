---
title: "완료 보고서 - 키보드 단축키 핫픽스 (v1.1.2)"
created: "2026-07-04"
updated: "2026-07-04"
owner: "InBlue"
author: "Cursor"
status: "active"
type: "report"
project: "SingPromfter"
tags:
  - hotfix
  - keyboard
visibility: "internal"
---

# 완료 보고서 - 키보드 단축키 핫픽스 (Cursor, 2026.07.04)

## 작업 요약

| 항목 | 결과 |
|------|------|
| 목표 | 화살표 키로 볼륨·프롬프터 속도 조절 |
| 결과 | **완료** — `1.1.2+1` |

## 단축키

| 키 | 동작 | 스텝 |
|----|------|------|
| ↑ / ↓ | 볼륨 | ±0.1 (0~1) |
| ← / → | 프롬프터 속도 | ±0.5 (0~10) |

메인 화면·전체화면 프롬프터 공통. 텍스트 입력 중에는 비활성.

## 변경 파일

- `lib/services/song_list_shortcut_service.dart`
- `lib/screens/song_list_screen.dart`
- `lib/screens/prompter_screen.dart`
- `lib/navigation/prompter_navigation.dart`
- `test/services/song_list_shortcut_service_test.dart`
- `pubspec.yaml`

## 검증

- `flutter analyze` — 이슈 없음
- `flutter test` — 32/32 통과
- `flutter build windows --release` — 성공

## 브랜치

- `claude/upbeat-northcutt-5f116e`: master 대비 고유 커밋 없음 → 머지 불필요
