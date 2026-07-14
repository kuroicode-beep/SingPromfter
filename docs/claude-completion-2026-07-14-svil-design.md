# 완료 보고서 — SVIL 디자인 표준 전환 (v1.2.0)

작성일: 2026-07-14
작성자: Claude Code
기준 지시문: `docs/handoff/작업지시문_20260714_SVIL디자인전환_ClaudeCode.md`
착수 커밋: `316a96f` (v1.1.3) → 결과 버전 `1.2.0+1`

## 요약

Core Precision Dark(바이올렛)에서 SVIL 프론트엔드 표준(고대비 다크 + 블루 accent + 교보손글씨2019)으로 전환했다. 심볼명을 유지하고 값만 교체해 위젯 변경 범위를 최소화했다.

## 변경 내역

### D1. 컬러 토큰 (`lib/theme/app_theme.dart`)
- 배경/표면: `#0D0D12` / `#16161D` / `#1F1F2A` / `#262633`
- 강조: primary(accent) `#7EC8FF`, primaryContainer(accent-strong) `#B3DDFF`, tertiary(warning) `#FFD479`
- **주 버튼 반전**: 밝은 블루 배경 + 검정 글자(`onPrimaryContainer #000`, ≈15:1)
- 콘텐츠 `#F5F5F7` / `#C9C9D4`, 구조 border `#3A3A48` / borderStrong `#6B6B82`, danger `#FF9B9B`
- 신규 토큰: accentStrong/accentMax/positive/focus/borderStrong
- WCAG 대비값 주석 갱신

### D2. 폰트 (`pubspec.yaml`, `app_theme.dart`, `prompter_settings_service.dart`, `prompter_lyrics_view.dart`)
- `assets/fonts/KyoboHandwriting2019.ttf` 번들, family `KyoboHandwriting2019` 등록
- 앱 기본 폰트를 교보손글씨2019로 지정(`ThemeData.fontFamily`)
- **볼드 합성 제거**: `AppTypography` 및 크롬 위젯의 `FontWeight.w600/w700` 제거 → 위계는 크기·색(accent)으로
- **숫자·시간 Consolas 모노**: `AppTypography.mono/monoMuted`, 진행률 시간·큐 순번에 적용
- 무대 가사 보호: `PrompterLyricsView`가 글꼴 미지정 시 손글씨 대신 Malgun(고가독)으로 폴백 → 저시력 가독성 유지
- 프롬프터 글꼴 옵션에 `교보손글씨2019` 추가(선택형, 기본 아님)

### D3. 컴포넌트
- 입력/버튼 테두리 `borderStrong`, 포커스 `accent` 2px, 라운딩 12px
- 카드 표면 `surface`, 탭 선택 표시를 색(accent)로 전환(볼드 금지)

## 검증

- `flutter analyze`: **No issues found**
- `flutter test`: **32개 전체 통과**
- `flutter build windows --release`: **성공** (`build/windows/x64/runner/Release/singpromfter_app.exe`)
- 데이터 호환: 토큰/폰트만 변경, 모델·저장 포맷 무변경

## 범위 밖(후속)

- D4 설정 3표준(글꼴 8종·글자 크기 3단계·다국어 5종): woff→TTF 원본 확보 및 i18n 준비 필요 → v1.2.x 이후
- 나머지 7종 글꼴: 현재 woff만 존재(Flutter는 TTF 필요), 미노출 유지
- `lib/widgets/app_nav_rail.dart`: 상단 탭 전환(v1.1.1) 이후 미사용 데드코드 → 정리 대상
