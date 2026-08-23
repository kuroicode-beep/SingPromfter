# 안드로이드 빌드·배포 메모 (2026-08-23, Claude Code)

## 지금 되는 것

AI 없는 프롬프터 코어가 안드로이드에서 돈다. 에뮬레이터(Medium_Phone_API_36.1, Android 16)에서
릴리즈 APK 기동 → 백업 zip 반입 → 곡 목록 → 프롬프터 가사 표시까지 실측 확인했다.

**남는 탭**: 홈 · 검색 · 즐겨찾기 · 트레이닝 · 도움말 · 설정
**빠지는 탭**: 유튜브 · 녹음 · 작곡 · 가져오기 이력

## 왜 빠지나 — 플랫폼 능력 게이트

정책은 `lib/utils/platform_capabilities.dart` 한 곳에서 결정한다. 설정으로 켤 수 있는 것을
다루는 `AiGate`와 달리, 이쪽은 **켤 방법이 없는 것**을 다루므로 '(꺼짐)' 라벨도 달지 않고 감춘다.

| 능력 | 모바일 | 이유 |
|---|---|---|
| `hasExternalTools` | ✗ | 앱이 ffmpeg·yt-dlp를 실행할 수 없다(샌드박스) |
| `hasLocalAi` | ✗ | SAW 서버는 PC에 있다. 폰의 127.0.0.1은 폰 자신 |
| `hasDeviceRecording` | ✗ | 녹음이 ffmpeg DirectShow(Windows 전용)에 묶여 있다 |
| `hasControlServer` | ✗ | 백그라운드 수명 미보장 + PC에서 폰 루프백에 도달 불가 |
| `hasFreeFileExport` | ✗ | Scoped Storage — 임의 경로에 못 쓴다 |

`PrompterSettings.localAiActive`가 `hasLocalAi`를 곱하므로, **PC 백업을 옮겨 와 AI 설정이
켜진 채로 들어와도 모바일에서는 죽어 있다.**

## 빌드

```bash
flutter build apk --release
```

산출물: `build/app/outputs/flutter-apk/app-release.apk` (약 102MB)

### 🔴 릴리즈 서명 — 사용자가 직접 만들어야 한다

지금은 `android/key.properties`가 없어 **debug 키로 서명**된다. 개발·사내 배포는 되지만
스토어에는 올릴 수 없다. 키스토어 비밀번호는 사용자 비밀이라 여기서 만들어 두지 않았다.

```
keytool -genkey -v -keystore %USERPROFILE%\singpromfter-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias singpromfter
```

그 다음 `android/key.properties`를 만든다(이 파일은 .gitignore 대상):

```
storePassword=<입력한 비밀번호>
keyPassword=<입력한 비밀번호>
keyAlias=singpromfter
storeFile=C:/Users/<사용자>/singpromfter-release.jks
```

`build.gradle.kts`가 파일이 있으면 자동으로 release 서명을 쓰고, 없으면 debug로 폴백한다.

## 함정 기록

- **INTERNET 권한**: Flutter 템플릿은 debug/profile 매니페스트에만 넣어 둔다. 릴리즈
  매니페스트에 없으면 **개발 중엔 멀쩡하고 릴리즈 APK에서만 모든 네트워크가 죽는다.**
  릴리즈 빌드로 실기기 확인이 필요한 이유다. `aapt dump permissions <apk>`로 산출물에서
  직접 확인할 것.
- **Gradle 데몬 파일 잠금**: 빌드가 `AccessDeniedException` / `Unable to delete directory`로
  반복 실패하면 데몬이 핸들을 쥔 것이다. `JAVA_HOME` 지정 후 `android\gradlew.bat --stop` →
  `build/app` 삭제 → 재빌드. (이 세션에서 2회 발생, 같은 처방으로 해결)
- **gradle 래퍼**: Flutter 템플릿 .gitignore가 `gradlew`·`gradle-wrapper.jar`를 제외한다.
  CI·새 클론에서 안드로이드 빌드가 되려면 추적해야 한다. `gradlew`는 리눅스에서 실행되므로
  `.gitattributes`로 LF를 못박았다(CRLF면 bad interpreter로 죽는다).
- **adb push 경로**: Git Bash에서 `/sdcard/...`가 Windows 경로로 변환된다. PowerShell로
  호출하거나 `MSYS_NO_PATHCONV=1`을 쓴다.
- **PowerShell 리다이렉트로 스크린샷 저장 금지**: `adb exec-out screencap -p > x.png`를
  PowerShell에서 하면 BOM·인코딩이 섞여 PNG가 깨진다. Bash로 저장할 것.

## PC 로컬 기준 동기화 (v5.7.0 — 구현 완료)

PC의 데이터가 정본이고 폰이 같은 와이파이로 받아간다. 클라우드는 없고 방향은 단방향이다.

**켜는 법**: PC → 설정 > 데이터·도구 > [폰으로 곡 보내기] 토글. 켜면 주소와 6자리
페어링 코드가 나온다. 폰 → 설정 > 데이터 > [PC에서 곡 받기]에 그 둘을 입력.

| 항목 | 구현 |
|---|---|
| 서버 | 제어 API(8772)에 `/api/sync/manifest`·`/api/sync/file` 추가. 새 서버를 세우지 않는다 |
| 바인딩 | 기본 루프백. 동기화를 켤 때만 `anyIPv4`. 토글 즉시 재바인딩 |
| 원격 제한 | 루프백이 아닌 연결은 `/api/sync/*` 외 전부 **403**. 곡 삭제·재생 조작이 LAN에 열리지 않는다 |
| 인증 | `X-Sync-Token` 헤더 = 페어링 코드. 서버를 켤 때마다 새로 만든다 |
| 델타 | 반주 파일 크기 비교. 같으면 받지 않는다. mtime은 플랫폼마다 정밀도가 달라 판정에 안 쓴다 |
| 가사 | txt·lrc는 매니페스트에 본문을 실어 보낸다(수 KB라 왕복이 더 비싸다) |

### 실측 검증 (에뮬레이터 + PC)

| 확인 | 결과 |
|---|---|
| LAN에서 `/api/sync/manifest` (토큰 O) | 200 |
| LAN에서 `/api/state`·`/api/songs` | **403** |
| 잘못된 토큰 | **401** |
| 1회차 동기화 | 곡 13개 · 반주 38개 받음 |
| 2회차 (변경 없음) | **반주 0개** — 델타 정상 |
| 폰에서 재생 | 04:16 로드, 위치 진행, 싱크 가사 표시 |

### 🔴 실측으로 잡은 버그 — 경로 방어의 오탐

파일명에 `..`가 들어 있으면 무조건 막았더니 **`아마도 그건.. - 최용준...mp3` 같은
말줄임표 제목의 반주가 전부 404**로 실패했다(3건). 막아야 하는 건 경로 구분자와
상위 디렉터리 참조 자체지 점 두 개가 아니다. 진짜 방어선은 "등록된 반주 파일명과
정확히 일치"라 이 완화로 약해지지 않는다.

### 실기기에서 쓰려면 (사용자 작업)

에뮬레이터는 `10.0.2.2`(호스트 별칭)로 붙었다. **실기기는 PC의 LAN IP로 붙어야 하는데,
Windows 방화벽이 8772 인바운드를 막고 있으면 연결되지 않는다.** 방화벽 규칙 추가는
시스템 보안 설정이라 손대지 않았다 — 필요하면 직접 허용해 주셔야 한다.

## 🔴 ffmpeg_kit_flutter_new 시도 결과 — 보류 (2026-08-23 실측)

"구현체 하나로 6개 서비스가 살아난다"는 계산은 맞지만, **패키지를 넣는 순간 Windows
빌드가 깨진다.**

```
LINK : fatal error LNK1104: '...fmpeg-kitinvcodec-62.dll' 파일을 열 수 없습니다.
```

`ffmpeg_kit_flutter_new 4.6.2`는 Windows 플러그인을 함께 붙이면서 빌드 시점에 ffmpeg
번들을 내려받는다. 실제로 **DLL 99개가 받아졌는데 `avcodec-62.dll` 하나만 빠져 있었다**
(번들 결함이거나 백신 격리로 추정 — avcodec은 오탐 단골이다).

**모바일 전용 이득을 위해 주 플랫폼(Windows) 빌드를 위태롭게 할 수는 없어서 되돌렸다.**
패키지 제거 후 Windows 릴리즈 빌드 정상 복구를 확인했다.

다시 시도한다면 검토할 것:
- `FFMPEGKIT_LOCAL_DIR` / `FFMPEGKIT_PACKAGE` CMake 옵션으로 다른 변형(min-gpl 등) 고정
- Windows에서는 플러그인을 아예 배제하는 구성(플레이버 분리 또는 래퍼 패키지)
- 백신 예외 설정 후 재시도 — 원인이 격리라면 이것만으로 해결된다

즉 **막힌 건 ffmpeg 이식 자체가 아니라 이 패키지의 Windows 동거**다. 안드로이드 단독
빌드만 보면 문제가 없을 가능성이 높다.

## 다음 단계

1. `record` 패키지로 녹음 복귀 (Windows에서 포기했던 CMake 제약이 안드로이드엔 없다)
2. `ffmpeg_kit_flutter`로 믹스·키 변주·조성 감지 복귀 — `ProcessRunner`가 추상 클래스라
   구현체 하나로 6개 서비스가 한꺼번에 살아난다
3. 폰 → PC 역방향(즐겨찾기·연습기록) 검토. 지금은 단방향 고정이라 폰의 변경은 다음
   동기화에서 덮인다
