# 안드로이드 빌드·배포 메모 (2026-08-18, Claude Code)

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

## 다음 단계

1. **PC 로컬 기준 동기화** — 제어 API(8772)에 동기화 라우트 추가, 설정에서 켤 때만 LAN
   바인딩, 페어링 토큰, 델타 전송. 계획서 3-4 참조.
2. `record` 패키지로 녹음 복귀 (Windows에서 포기했던 CMake 제약이 안드로이드엔 없다)
3. `ffmpeg_kit_flutter`로 믹스·키 변주·조성 감지 복귀 — `ProcessRunner`가 추상 클래스라
   구현체 하나로 6개 서비스가 한꺼번에 살아난다
