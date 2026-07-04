# SingPromfter 구현 스펙

작성일: 2026-06-28  
업데이트: 2026-07-04  
기준 버전: `1.0.1+1`

## 01. 버전 관리

- Flutter 앱 패키지명: `singpromfter_app`
- 앱 버전: `pubspec.yaml`의 `1.0.1+1`
- README 기능 표기: `v1.0.1`
- 주요 의존성: `audioplayers`, `file_picker`, `shared_preferences`, `path_provider`, `uuid`, `archive`
- Windows 빌드 명령: `flutter build windows`

## 02. 라우팅 / 진입점

- 진입점: `lib/main.dart`
- 앱 루트: `SingPromfterApp`
- 기본 화면: `SongListScreen`
- 전체화면 프롬프터: `PrompterScreen`
- 앱 시작 시 가로/세로 방향을 모두 허용하고 시스템 UI 색상을 다크 테마에 맞춘다.

## 03. 세션과 인증

- 별도 사용자 계정, 인증, 세션 관리가 없다.
- 모든 데이터는 로컬 저장소와 앱 문서 디렉터리에 저장한다.
- 앱 상태 복원은 SharedPreferences 키로 처리한다.

## 04. 데이터 모델

### Song

- `id`: UUID 문자열
- `title`: 곡 제목
- `lyricsPath`: 가사 파일 경로 또는 파일명
- `lyricsText`: 가사 본문 캐시
- `backingTracks`: `BackingTrack` 리스트
- `createdAt`, `updatedAt`: 생성/수정 시각
- `isFavorite`: 즐겨찾기 여부
- 레거시 `mrFileName`은 슬롯 1 반주로 변환한다.

### BackingTrack

- `slot`: 1~3 슬롯 번호
- `fileName`: 저장된 mp3 파일명
- `label`: 표시 라벨
- `startMs`, `endMs`: 선택 재생 시작/종료 지점

### QueueItem

- `songId`: 예약 곡 ID
- `selectedTrackSlot`: 예약 시 선택된 반주 슬롯
- `queuedAt`: 예약 시각

### PrompterSettings

- `fontSizeLevel`: 1~7
- `lineHeightLevel`: 1~7
- `speedLevel`: 0~10
- `volume`: 0~1
- `playbackRate`: 0.5~1.5
- `lastSelectedTrackSlot`
- `fontFamily`
- `boldText`
- `customFontSizePt`
- `lastSelectedTrackSlotBySong`

## 05. 저장소 / 서비스

저장소 구현체는 `SongRepository` 단일 인스턴스이며, 화면 계층은 서비스와 코디네이터로 책임을 나눈다.

SharedPreferences 키:

- `singpromfter_songs`
- `singpromfter_settings`
- `singpromfter_queue`
- `singpromfter_last_song_id`

파일 저장 경로:

- 가사: `{Documents}/data/txt/{정제된제목}.txt`
- 반주: `{Documents}/data/mp3/{정제된제목}_mr{slot}.mp3`
- 레거시 가사: `{Documents}/lyrics/{id}.txt`
- 레거시 반주: `{Documents}/mr/{fileName}`

파일명 정제 규칙:

- Windows 금지 문자 `<>:"/\|?*`를 공백으로 치환
- 연속 공백 축약
- 후행 점과 공백 제거
- 빈 파일명은 `song`으로 대체

주요 서비스:

- `SongLibraryService`: 곡 추가/수정/삭제/복구, 즐겨찾기 처리
- `SongQueueService`: 예약 큐 저장 연동
- `QueueLogic`: 예약 큐 삭제/재정렬 순수 로직
- `PrompterAudioService`: 오디오 준비, 재생, 정지, 재생 속도, 시작 지점 적용
- `PrompterAutoScrollService`: 메인 화면 자동 스크롤
- `BackupService`: zip 백업 내보내기/가져오기
- `BatchRegistrationService`: 폴더 기반 txt/mp3 일괄 등록
- `SongActionCoordinator`: 곡 등록/수정/삭제 다이얼로그 흐름 조정

## 06. 오디오 / 백그라운드 작업

- 오디오 플레이어: `audioplayers.AudioPlayer`
- 재생 소스: `setSourceDeviceFile(path)`
- 재생 속도: `setPlaybackRate(rate)`
- 시작 지점: 반주별 `startMs` 적용
- 종료 지점: 반주별 `endMs` 도달 시 완료 처리
- 상태 구독:
  - `onPlayerStateChanged`
  - `onPositionChanged`
  - `onDurationChanged`
- 곡 완료 시 `PlayerState.completed`를 받아 예약 큐 다음 곡을 로드하고 자동 재생한다.
- 프롬프터 화면은 `wakelock_plus`가 아니라 `SystemUiMode.immersiveSticky` 중심으로 전체화면 표시를 제어한다.

## 07. 주요 화면 스펙

### SongListScreen

- 앱의 주 화면
- 넓은 화면: 좌측 곡 목록, 우측 가사/재생 패널
- 좁은 화면: 상단 곡 목록, 하단 가사/재생 패널
- 곡 타일 액션: 선택, 재생, 예약, 수정, 삭제, 즐겨찾기
- 목록 상단: 제목 검색, 한글 초성 검색, 전체/즐겨찾기 필터
- 선택된 곡에 반주가 있으면 슬롯 버튼 표시
- 하단 컨트롤: 재생, 정지, 처음부터, 시크, 볼륨, 재생 속도, 프롬프터 설정

### PrompterScreen

- 검정 배경, 흰색 가사, 중앙 정렬
- 상단 닫기/제목 영역
- 하단 컨트롤 바: 자동 스크롤, 크기, 줄간격, 속도, 위/아래 이동
- 화면 탭으로 컨트롤 표시/숨김
- `Escape`로 닫기

## 08. 접근성 / 테마

- 기본 테마: Material 3 다크 테마
- 핵심 색상:
  - 배경: `#0A0A0A`
  - 표면: `#111111`
  - 강조색: `#EAB308`
  - 본문: `#F5F5F5`
  - 보조 텍스트: `#9CA3AF`
- 글자 크기 매핑: 18, 22, 28, 36, 44, 56, 72pt
- 줄 간격 매핑: 1.35, 1.5, 1.7, 1.95, 2.2, 2.45, 2.75
- 프리셋:
  - 표준: 크기 3, 줄간격 3, 속도 2, 기본 글꼴, 굵게 끔
  - 저시력: 크기 4, 줄간격 4, 속도 3, Malgun Gothic, 굵게 켬
  - 원거리: 크기 5, 줄간격 5, 속도 2, Malgun Gothic, 굵게 켬

## 09. 검증

2026-07-04 기준 확인된 명령:

```powershell
flutter analyze
flutter test
flutter build windows
```

결과:

- 정적 분석: 통과
- 테스트: 통과, 20개
- Windows 빌드: 통과
- 산출물: `build/windows/x64/runner/Release/singpromfter_app.exe`

현재 자동화 테스트 범위:

- 파일명 정제 규칙 테스트
- 프롬프터 설정 저장/복원 테스트
- `Song`, `QueueItem` 직렬화 테스트
- `PrompterLevels` 단계 변환 테스트
- `QueueLogic` 삭제/재정렬 테스트
- `SongTile` 위젯 스모크 테스트

