# SingPromfter

저시력 사용자를 위한 노래 프롬프터 Flutter 앱입니다.

## 주요 기능 (v0.3.1)

- 곡 1개 레코드에 가사(txt) + 반주(mp3) 1~3개 연결
- 반주 슬롯 선택 재생 (정지/처음/시크)
- 예약 큐 추가, 순서 확인, 드래그 재정렬, 자동 다음 곡 재생
- 프롬프터 조절: 글자 크기, 줄 간격, 속도, 볼륨
- 프롬프트 아래 글꼴 선택 + 굵게(blod) 체크
- 접근성 프리셋: 표준 / 저시력 추천 / 원거리 무대
- 전체화면 프롬프터(가사 중심 표시)
- 설정/곡/큐 로컬 저장 및 재실행 복원

## 빌드

```bash
flutter pub get
flutter build windows
```

산출물:

- `build/windows/x64/runner/Release/singpromfter_app.exe`

## 개발 환경

- Flutter
- just_audio
- shared_preferences
- file_picker
