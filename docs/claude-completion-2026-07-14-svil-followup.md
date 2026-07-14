# 완료 보고서 — SVIL 후속 과제 (v1.2.1)

작성일: 2026-07-14
작성자: Claude Code
기준: v1.2.0(`888113d`) → `1.2.1+1`

## 처리한 후속 과제

### F1. 데드코드 제거
- 상단 탭 전환(v1.1.1) 이후 미사용이던 `lib/widgets/app_nav_rail.dart` 삭제.

### F2·F3. SVIL 설정 3표준 (부분) — 글꼴·글자 크기
- `lib/services/app_display_controller.dart`: 앱 전역 표시 설정(글꼴·글자 크기)을 `ValueNotifier`로 관리, SharedPreferences 영속화.
- **앱 글꼴 선택**: 실재 번들 3종(교보손글씨2019 / 맑은 고딕 / Segoe UI)만 노출 — SVIL "깨진 옵션 금지". 설정 항목은 각 글꼴로 미리보기.
- **글자 크기 3단계**: 작음(0.9) / 보통(1.0) / 큼(1.15). 앱 크롬에 `MediaQuery.textScaler`로 적용. 무대 프롬프터는 자체 크기 레벨을 쓰므로 배율을 초기화해 오버플로 방지.
- `main.dart`가 루트에서 컨트롤러를 구독해 테마 글꼴·텍스트 배율을 실시간 반영.
- `AppTheme.dark` → `AppTheme.dark({fontFamily})`로 변경.

### 버전 정보 표기 (앱 버전 규칙)
- `lib/constants/app_version.dart`: `APP_VERSION` + `VERSION_HISTORY`(최신순).
- 설정 "앱 정보"에 `v1.2.1` 상시 표기 + "업데이트 히스토리" 접이식.

## 검증
- `flutter analyze`: **No issues found**
- `flutter test`: **37개 전체 통과** (신규 `app_display_controller_test` 5건 포함)
- `flutter build windows --release`: **성공**

## 남은 과제 (v1.2.x 이후)
- **다국어 5종**: 문자열 전수 사전화 + `<html lang>`/locale 스위처 필요. 대규모 i18n 작업이라 별도 스프린트로 분리.
- **글꼴 8종 확대**: 나머지 5종은 현재 woff만 존재 → TTF/OTF 원본 확보 후 `fontFamilies`에 추가.
