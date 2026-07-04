# SingPromfter 프로젝트 위키

SingPromfter는 저시력 사용자를 위한 Flutter 기반 노래 프롬프터 앱이다. 가사 txt 파일과 반주 mp3 파일을 로컬에 등록하고, 큰 글씨의 가사 표시, 반주 재생, 예약 큐, 전체화면 프롬프터를 제공한다.

## 01. 빠른 링크

- [SingPromfter PRD](/doc/singpromfter-prd-Lan8jXQ2Hy)
- [SingPromfter 구현 스펙](/doc/singpromfter-larGnxJLFG)
- [SingPromfter 아키텍처](/doc/singpromfter-X8CVauJPHd)
- [SingPromfter 개발 히스토리](/doc/singpromfter-WBkkrJ8tA1)
- [SingPromfter 완료보고 인덱스](/doc/singpromfter-WAdB8SpavJ)

## 02. 현재 기준

- 기준일: 2026-07-04
- 앱 버전: `1.1.3+1`
- 버전명: `v1.1.3`
- Git 태그: `v1.1.3` (최신)
- 저장소: `https://github.com/kuroicode-beep/SingPromfter`
- 로컬 경로: `C:\Projects\SingPromfterApp`
- 로컬 문서 위치: `docs/outline-wiki/`
- 검증 상태: `flutter analyze` 통과, `flutter test` 32개, `flutter build windows` 통과
- Windows 산출물: `dist/SingPromfter-v1.1.3/singpromfter_app.exe`

## 03. 최근 릴리스 요약

| 버전 | 핵심 변경 |
|---|---|
| `v1.1.3` | 키보드 단축키 `PrompterKeyboardScope` 재구현 (화살표 볼륨/속도) |
| `v1.1.2` | 화살표 키 단축키 최초 추가 |
| `v1.1.1` | UI 개선 2차 — 상단 탭, 카드 버튼, 하단 바 재구성, 접이식 큐 |
| `v1.1.0` | Sprint 6~8 디자인 리뉴얼, 가수 필드, 줄 하이라이트, 예약/시작 |
| `v1.0.0` | Sprint 5 품질 보증 완료, CI 구축 |

## 04. 문서 구조

### PRD

제품 목적, 대상 사용자, 핵심 기능 범위, 비범위, 성공 기준, 리스크를 정리한다.

### 구현 스펙

Flutter 진입점, 화면 구성, 데이터 모델, 저장소, 오디오 재생, 예약 큐, 프롬프터 제어, 접근성 설정, 검증 기준을 코드 기준으로 정리한다.

### 아키텍처

앱 레이어, 저장소, 로컬 파일 저장, SharedPreferences, 오디오 플레이어, 플랫폼 빌드 구조를 시스템 관점에서 정리한다.

### 개발 히스토리

Sprint 1~8 및 v1.1.x 패치 릴리스 이력을 정리한다.

### 완료보고 인덱스

Cursor 완료보고서와 검증 결과 문서를 한 곳에서 찾을 수 있게 정리한다.

## 05. 참고 로컬 문서

- `README.md`
- `docs/기능명세서.md`
- `docs/기능상세리스트.md`
- `docs/개선계획/00-전체-로드맵.md`
- `docs/handoff/작업지시문_20260704_기능개선-디자인리뉴얼_ClaudeCode.md`
- `docs/handoff/작업지시문_20260704_UI개선-2차_ClaudeCode.md`
