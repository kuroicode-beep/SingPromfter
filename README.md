# SingPromfter

저시력 사용자를 위한 노래 프롬프터 Flutter 앱입니다.

## 주요 기능 (v1.0.0)

- 곡 1개 레코드에 가사(txt) + 반주(mp3) 1~3개 연결
- 반주 슬롯 선택 재생 (정지/처음/시크)
- 예약 큐 추가, 순서 확인, 드래그 핸들 재정렬, 자동 다음 곡 재생
- 곡 검색, 즐겨찾기, 전체/즐겨찾기 필터
- 백업 내보내기/가져오기, 일괄 등록
- 삭제 실행 취소, 반주 라벨 변경, 반주 시작/끝 지점 설정
- 프롬프터 조절: 7단계 글자 크기, 사용자 정의 pt, 줄 간격, 속도, 볼륨
- 반주 재생 속도 조절(0.5x~1.5x)
- 프롬프트 아래 글꼴 선택 + 굵게 체크
- 접근성 프리셋: 표준 / 저시력 추천 / 원거리 무대
- 저시력 보조 조작: +/- 버튼, 48dp 터치 타겟, 스크린 리더 라벨, 강화된 색 대비
- 전체화면 프롬프터(가사 중심 표시)
- 설정/곡/큐 로컬 저장 및 재실행 복원
- `SongListScreen` 분리 구조: 다이얼로그, 큐, 오디오, 설정, 화면 패널 모듈화
- 자동 품질 검증: 모델/순수 로직/위젯 테스트, 강화된 정적 분석, GitHub Actions CI

## 빌드

```bash
flutter pub get
flutter analyze
flutter test
flutter build windows
```

산출물:

- `build/windows/x64/runner/Release/singpromfter_app.exe`

## CI

GitHub Actions에서 `flutter analyze`, `flutter test --coverage`, `flutter build windows --release`를 자동 실행한다.

## 개발 환경

- Flutter
- audioplayers
- shared_preferences
- file_picker
