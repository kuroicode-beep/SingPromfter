# SingPromfter 아키텍처

작성일: 2026-06-28  
업데이트: 2026-07-04  
기준 버전: `1.0.1+1`

## 01. 개요

SingPromfter는 Flutter 클라이언트 단독 앱이다. 별도 서버나 인증 계층 없이 로컬 파일 시스템과 SharedPreferences에 데이터를 저장한다. Sprint 3 이후 메인 화면은 서비스, 코디네이터, 다이얼로그, 패널 위젯으로 분리되어 유지보수 가능한 구조를 갖는다.

## 02. 구성도

```mermaid
flowchart TD
  User["사용자"] --> App["SingPromfter Flutter App"]
  App --> Main["SongListScreen"]
  Main --> Prompter["PrompterScreen"]
  Main --> Services["Services / Coordinator"]
  Services --> Repo["SongRepository"]
  Repo --> Prefs["SharedPreferences"]
  Repo --> Docs["Application Documents Directory"]
  Docs --> Txt["data/txt/*.txt"]
  Docs --> Mp3["data/mp3/*_mrN.mp3"]
  Services --> Backup["BackupService / Zip Archive"]
  Services --> Batch["BatchRegistrationService"]
  Services --> Audio["PrompterAudioService"]
  Audio --> Player["audioplayers AudioPlayer"]
  Player --> DeviceFile["DeviceFileSource"]
  App --> Theme["AppTheme.dark"]
  Flutter["Flutter Toolchain"] --> Builds["Windows Release Build"]
```

## 03. 프론트엔드

- 프레임워크: Flutter
- 디자인: Material 3 다크 테마
- 루트 위젯: `SingPromfterApp`
- 메인 화면: `SongListScreen`
- 프롬프터 화면: `PrompterScreen`
- 상태 관리: 외부 상태관리 라이브러리 없이 `StatefulWidget` 상태와 서비스 계층으로 구성

주요 UI 상태:

- 곡 목록
- 예약 큐
- 선택 곡
- 선택 반주 슬롯
- 재생 상태
- 현재 재생 위치/길이
- 프롬프터 설정
- 오디오 준비 상태
- 검색/즐겨찾기 필터 상태
- 삭제 실행 취소 대기 상태

## 04. 백엔드 / API

- 원격 백엔드 없음
- HTTP API 없음
- 외부 인증 없음
- 앱 내부 repository가 영속성 계층 역할을 담당

## 05. 데이터 저장소

### SharedPreferences

곡 목록, 설정, 예약 큐, 마지막 선택 곡 ID를 JSON 문자열로 저장한다.

### Application Documents Directory

`path_provider`로 앱 문서 디렉터리를 찾고, 그 아래 `data/txt`, `data/mp3` 디렉터리를 생성한다.

### 레거시 호환

기존 구조의 `lyrics` 및 `mr` 디렉터리를 읽고 삭제 대상으로도 고려한다. `Song.fromJson`은 기존 `mrFileName` 필드를 `BackingTrack(slot: 1)`으로 변환한다.

### 백업

`BackupService`는 곡 메타데이터, 가사 파일, 반주 파일을 zip으로 내보내고 가져온다. 가져오기 시 동일 제목은 자동 이름 변경으로 충돌을 피한다.

## 06. 오디오 재생

- 라이브러리: `audioplayers`
- 재생 파일: repository가 찾아준 로컬 mp3 경로
- 반주별 시작/종료 지점과 재생 속도 설정을 적용한다.
- 상태 스트림을 구독해 UI 재생 상태와 진행률을 갱신한다.
- 곡 완료 이벤트는 예약 큐 처리 트리거로 사용한다.
- 반주가 없거나 파일을 찾지 못하면 사용자에게 SnackBar 안내를 표시한다.

## 07. 배포 / 운영

- Flutter 멀티플랫폼 프로젝트 구조를 유지하되, 현재 검증/배포 기준은 Windows다.
- 현재 확인된 빌드 대상: Windows
- Windows 빌드 명령:

```powershell
flutter build windows
```

- 산출물:

```text
build/windows/x64/runner/Release/singpromfter_app.exe
```

## 08. 보안 / 접근성

보안 특성:

- 네트워크 전송이 없어 개인정보 외부 전송면이 작다.
- 사용자가 선택한 로컬 가사/반주 파일을 앱 문서 디렉터리에 복사한다.
- 파일 삭제는 곡 삭제와 연결된 로컬 파일에 한정된다.

접근성 특성:

- 검정 배경과 흰색 텍스트의 고대비 프롬프터
- 노란 강조색 버튼
- 큰 글자 크기 레벨
- 넓은 줄 간격
- 굵게 표시
- 저시력/원거리 프리셋
- 48dp 터치 타겟, Semantics 라벨, 보조 +/- 버튼
- 키보드 단축키: Space, F5, Escape

## 09. 주요 리스크와 개선 방향

- 실제 파일 선택 다이얼로그, mp3 재생, 백업/복원은 수동 회귀 테스트가 필요하다.
- Windows 외 플랫폼은 로컬 파일 복사/재생 동작 검증이 부족하다.
- `audioplayers`와 `file_picker` 메이저 업데이트는 API 변경 영향이 커 별도 브랜치 검증이 필요하다.
- 파일명 기반 저장은 제목 변경 시 복사/삭제 처리가 필요해 회귀 테스트가 중요하다.
- GitHub Actions CI로 정적 분석, 테스트, Windows 빌드를 자동 검증한다.

