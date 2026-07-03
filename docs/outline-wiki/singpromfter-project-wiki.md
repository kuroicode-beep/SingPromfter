# SingPromfter 프로젝트 위키

SingPromfter는 저시력 사용자를 위한 Flutter 기반 노래 프롬프터 앱이다. 가사 txt 파일과 반주 mp3 파일을 로컬에 등록하고, 큰 글씨의 가사 표시, 반주 재생, 예약 큐, 전체화면 프롬프터를 제공한다.

## 01. 빠른 링크

- [SingPromfter PRD](/doc/singpromfter-prd-Lan8jXQ2Hy)
- [SingPromfter 구현 스펙](/doc/singpromfter-larGnxJLFG)
- [SingPromfter 아키텍처](/doc/singpromfter-X8CVauJPHd)

## 02. 현재 기준

- 기준일: 2026-06-28
- 앱 버전: `1.0.0+1`
- README 기능 기준: `v0.3.1`
- 저장소: `C:\Projects\SingPromfterApp`
- 로컬 문서 위치: `docs/outline-wiki/`
- 검증 상태: `flutter analyze`, `flutter test`, `flutter build windows` 통과
- Windows 산출물: `build/windows/x64/runner/Release/singpromfter_app.exe`

## 03. 문서 구조

### PRD

제품 목적, 대상 사용자, 핵심 기능 범위, 비범위, 성공 기준, 리스크를 정리한다.

### 구현 스펙

Flutter 진입점, 화면 구성, 데이터 모델, 저장소, 오디오 재생, 예약 큐, 프롬프터 제어, 접근성 설정, 검증 기준을 코드 기준으로 정리한다.

### 아키텍처

앱 레이어, 저장소, 로컬 파일 저장, SharedPreferences, 오디오 플레이어, 플랫폼 빌드 구조를 시스템 관점에서 정리한다.

## 04. 참고 로컬 문서

- `README.md`
- `docs/기능명세서.md`
- `docs/기능상세리스트.md`
- `docs/SingPrompt_기획개발스펙.txt`
