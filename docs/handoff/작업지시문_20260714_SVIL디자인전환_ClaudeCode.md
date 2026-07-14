# SingPromfter 작업 지시문 — SVIL 디자인 표준 전환

> 작성일: 2026-07-14
> 작성자: Claude Code
> 기준 버전: v1.1.0 (커밋 `bbf7998`, Core Precision Dark 적용본)
> 기준 표준: `svil-frontend-design` 스킬 / `docs/Design_20260714_SVIL_프론트엔드_디자인가이드_ClaudeCode.md`
> **선행 두 문서의 "디자인 시스템(색·폰트)" 결정을 본 문서가 대체(supersede)한다.** 레이아웃·기능 지시(S7~S8, T1~T5)는 그대로 유효.
> 담당: Cursor (구현) / Codex (검증)

---

## 1. 배경 — 무엇이 바뀌나

v1.1.0은 `asset/stitch_ui.zip`의 **Core Precision Dark**(바이올렛 `#5856D6` + 흰 텍스트 버튼, Hanken/Pretendard)로 구현되었다. 이는 SVIL 계열 공통 표준과 **불일치**한다.

SVIL 표준으로 전환한다:

| 축 | 현재 (Core Precision Dark) | SVIL 표준 (목표) |
|---|---|---|
| 강조색 | 바이올렛 `#C2C1FF` / `#5856D6` | **블루 `#7ec8ff` / `#b3ddff`** |
| 주 버튼 | 어두운 바이올렛 배경 + 흰 글자 | **밝은 블루(`accent-strong`) 배경 + 검정 글자** (≈15:1) |
| 폰트 | Pretendard/시스템, `FontWeight.w600/w700` 강조 | **교보손글씨2019 단일 굵기**, 강조는 **크기·색** (bold 합성 금지) |
| 숫자/시간/버전 | 본문 폰트 | **Consolas 모노** |
| 본문 크기 | 16px | **18px 기본** (최소선 12px로 완화) |

> ⚠ **가장 큰 변경 2가지**: ① 주 버튼이 "어두운 배경+흰 글자"에서 "밝은 배경+검정 글자"로 반전된다(SVIL: 어두운 accent 배경 금지). ② `FontWeight.bold`/`w600`/`w700` 강조가 전부 사라지고 크기·색으로 대체된다(교보손글씨는 단일 굵기라 합성 볼드가 뭉개짐).

---

## 2. D1 — 컬러 토큰 전환 (P0)

- 대상: `lib/theme/app_theme.dart` (`AppColors`)
- 기존 심볼명은 최대한 유지하고 **값만 교체**하여 위젯 변경 범위를 줄인다.

### 토큰 매핑표 (그대로 반영)

```dart
class AppColors {
  AppColors._();

  // Surface (토널 레이어링)
  static const background       = Color(0xFF0D0D12); // SVIL bg
  static const surface          = Color(0xFF16161D); // SVIL surface (앱바·카드)
  static const surfaceContainer = Color(0xFF16161D); // 카드·패널
  static const elevated         = Color(0xFF1F1F2A); // SVIL surface-2 (입력·버튼·hover)

  // 강조 (블루)
  static const accent           = Color(0xFF7EC8FF); // 강조·선택·링크·아이콘
  static const accentStrong     = Color(0xFFB3DDFF); // 주 버튼 배경 (검정 글자)
  static const accentMax        = Color(0xFFD6ECFF); // 주 버튼 hover

  // 콘텐츠
  static const onSurface        = Color(0xFFF5F5F7); // text (≈15:1)
  static const onSurfaceVariant = Color(0xFFC9C9D4); // text-sub
  static const onAccent         = Color(0xFF000000); // accent-strong 위 글자 = 검정

  // 구조
  static const border           = Color(0xFF3A3A48); // 일반 경계선
  static const borderStrong     = Color(0xFF6B6B82); // 버튼 테두리 (대비 ≥3:1)

  // 상태 (색 + 텍스트 라벨 병행)
  static const positive         = Color(0xFF7EE2A8);
  static const warning          = Color(0xFFFFD479); // 예약·주의
  static const negative         = Color(0xFFFF9B9B); // 오류·삭제
  static const focus            = Color(0xFFFFD479); // 포커스 링

  // 선택 상태 배경 (accent 10%)
  static const selectedSurface  = Color(0x1A7EC8FF);

  // ── 심볼 매핑(기존 위젯 호환) ──
  // primary          → accent
  // primaryContainer → accentStrong  ★ 버튼 배경. 흰 글자였던 곳은 onAccent(검정)로 반드시 교체
  // onPrimaryContainer → onAccent (검정)
  // secondary        → accent
  // tertiary         → warning
  // outline          → border
  // danger           → negative
  // textPrimary/textMuted → onSurface/onSurfaceVariant
}
```

### 필수 후속 처리

1. `primaryContainer`(=accentStrong) 배경을 쓰는 모든 버튼의 **전경색을 `onAccent`(검정)로 교체**한다. 대상 확인: `song_tile.dart`([시작]), `app_theme.dart`(ElevatedButton/FAB), `home_now_playing_bar.dart`([곡 시작]), 큐 NOW 배지, 네비 활성 인디케이터, 상단 탭 [곡 등록].
2. `onPrimaryContainer = #FFFFFF` 잔존 검색 → 검정으로 교체(흰 글자를 밝은 블루 위에 두면 대비 미달).
3. `sliderTheme` active/thumb: `accent` 유지, overlay `0x337EC8FF`.
4. `inputDecorationTheme.focusedBorder`: `accent` 2px + 포커스 링 `focus`(#ffd479).
5. **버튼 테두리는 `border`가 아니라 `borderStrong`(#6b6b82)** 를 쓴다(WCAG 1.4.11, 3:1). 일반 구분선만 `border`.
6. 프롬프터 전체화면: 배경은 `background`(#0d0d12)에 준하는 딥다크 유지, 가사 `onSurface`, 하이라이트 글로우는 **바이올렛 → `accent`(#7ec8ff)** 로 교체.

### DoD
- 바이올렛(`#5856D6`/`#C2C1FF`/`#ADC6FF`/`#FFB785`) 하드코딩·심볼 잔존 0건
- 밝은 블루 버튼 위 흰 글자 0건(전부 검정)
- 신규 대비 주석을 `AppColors`에 기록(주 버튼 검정/accent-strong ≈15:1 등)

---

## 3. D2 — 타이포그래피: 교보손글씨2019 + 볼드 제거 (P0)

- 대상: `pubspec.yaml`, `lib/theme/app_theme.dart`(`AppTypography`), 볼드 사용처 전반

### 폰트 번들

1. `assets/fonts/`에 **KyoboHandwriting2019.ttf** 추가.
   - 원본 TTF 위치: `C:\Projects\inblue_money\fonts\KyoboHandwriting2019.ttf` (복사 사용)
2. `pubspec.yaml` fonts 섹션에 `family: Kyobo2019` 등록. 기존 MalgunGothic/SegoeUI는 **프롬프터 글꼴 선택 옵션으로만 유지**하고, 앱 기본 폰트는 교보손글씨로 지정한다.
3. 폴백 순서: 교보손글씨2019 → Malgun Gothic. (Pretendard/LINESeed 등 나머지 7종은 D5에서 TTF 확보 후 추가 — 현재 Promfter Maker에 woff만 있어 Flutter 직접 사용 불가.)

### 볼드 → 크기·색 전환 (교보손글씨는 단일 굵기)

`AppTypography`에서 `FontWeight.w600/w700` 을 전부 제거하고 위계를 **크기+색**으로 재정의한다.

```dart
class AppTypography {
  static const screenTitle = TextStyle(fontSize: 26, color: AppColors.onSurface);      // 화면 제목(크게)
  static const listTitle   = TextStyle(fontSize: 20, color: AppColors.onSurface);      // 리스트 제목
  static const body        = TextStyle(fontSize: 18, height: 1.6, color: AppColors.onSurface);
  static const bodyMuted   = TextStyle(fontSize: 18, height: 1.6, color: AppColors.onSurfaceVariant);
  static const emphasis    = TextStyle(fontSize: 18, color: AppColors.accent);         // 강조 = 색(볼드 대신)
  // 숫자·시간·버전·곡번호 전용 모노
  static const mono        = TextStyle(fontFamily: 'Consolas', fontSize: 18, color: AppColors.onSurface);
  static const monoMuted   = TextStyle(fontFamily: 'Consolas', fontSize: 16, color: AppColors.onSurfaceVariant);
}
```

- `letterSpacing: 0.02`, 한글 줄바꿈은 `softWrap` + `word-break:keep-all` 상응(Flutter는 기본 어절 단위 유지) 확인.
- `appBarTheme.titleTextStyle`/`labelStrong`/각 위젯의 `fontWeight` 지정 전수 제거. `TabBar`의 `labelStyle`(현재 w700)도 크기·언더라인으로 대체(§탭 규칙).
- **탭 선택 표시 = 3px accent 언더라인**(볼드 금지). 진행바/배지 radius 999px.

### 숫자 모노 적용 지점
- 재생 시간 `00:00`(`_DurationLabel`), 진행바 시간 텍스트, `크기 40pt` 등 pt 값, 앱 버전(`vX.Y.Z`), 곡 번호(검색 화면), 곡 수(`6/6곡`)의 숫자.

### DoD
- 프로젝트 내 `FontWeight.w600`/`w700`/`bold` 사용 0건(아이콘 폰트 제외)
- 교보손글씨로 렌더, 숫자/시간/버전은 Consolas로 렌더(육안 확인)
- 프롬프터 "굵게" 체크박스는 교보손글씨에서 효과가 약함 → 문구를 "굵게(고딕 계열에서만 적용)"로 바꾸거나, 굵게 체크 시 폰트를 Malgun Bold로 대체하는 안내 표기(D2 주의사항 참조)

---

## 4. D3 — 컴포넌트 규칙 정렬 (P1)

- 버튼·입력: **min 50px**, radius 12px, border **2px `borderStrong`**, hover=accent 보더, focus 3px `#ffd479`.
- 카드: `surface`, border 1px `border`, radius 16px, padding 22~24.
- 배지(NOW·예약 수 등): pill 999px, 1.5px currentColor, **색 + 텍스트 라벨 병행**.
- 주 버튼 hover: `accentStrong` → `accentMax`. 일반 버튼 hover: 대비 오르는 방향만(accent 테두리 + accent-strong 글자). **어두운 accent 배경 금지**.
- 리스트 활성 행: `selectedSurface`(accent 10%) + 좌측 3px accent 인디케이터 + `선택됨` 텍스트 라벨(현행 유지, 색만 교체).

### DoD
- `song_tile.dart`, `queue_panel.dart`, `home_now_playing_bar.dart`, `prompter_bottom_bar.dart`, `settings_panel.dart` 일관 적용.

---

## 5. D4 — 설정 화면 SVIL 3표준 (P1)

SVIL 표준(§2.1, 소장님 확정): **설정 메뉴가 있는 앱은 글꼴 선택·글자 크기·다국어 세 항목을 반드시 제공**한다. 이 앱은 `settings_panel.dart`가 있으므로 대상이다.

| 항목 | 요구 | 이 앱 적용 |
|---|---|---|
| **글꼴 선택** | 8종 전부 로컬 번들, 실재하는 것만 노출, 각 옵션은 해당 글꼴로 미리보기, 글꼴명 번역 금지 | **D5에서 TTF 확보 후 단계 도입.** 1차는 교보손글씨2019 + Malgun 2종만 노출(깨진 옵션 금지). 프롬프터 글꼴 선택과 앱 전역 글꼴 선택을 구분/연동 정리 |
| **글자 크기 3단계** | 작음 16 / 보통 18(기본) / 큼 20 (본문 기준), rem 기반 | 앱 전역 본문 스케일에 적용. 프롬프터 7단계 크기와 **별개**(프롬프터는 무대용 초대형 유지) |
| **다국어 5종** | 한국어·English·日本語·中文·Tiếng Việt, 사전 키·`{변수}` 치환, `<html lang>` 동기화 | **의사결정 필요(6장).** 착수 시 문자열 전수 사전화 |

### DoD (1차 범위 = 글꼴·글자 크기)
- 설정 화면에 "표시" 섹션 신설: 앱 글꼴 선택(미리보기) + 글자 크기 3단계
- 선택값은 `PrompterSettings` 또는 별도 앱 설정 키로 저장·복원
- 다국어는 6장 결정에 따름

---

## 6. 의사결정 필요 항목 (착수 전 확정)

| 항목 | 선택지 | Claude 권장 |
|---|---|---|
| **다국어 5종 도입 시점** | (A) 이번 전환에 포함 / (B) v1.2로 분리 | **B 권장.** 저시력 단일 사용자용 노래방 프롬프터라 5개국어 우선순위 낮음. 단 표준상 "설정 있으면 필수"이므로 v1.2 항목으로 명시 예약. 지금은 문자열 하드코딩을 사전 키로 정리하는 **준비 작업만** 병행 가능 |
| **글꼴 8종 완전 도입** | (A) 이번에 8종 TTF 확보 / (B) 교보+Malgun 2종으로 시작 후 확대 | **B 권장.** 나머지 6종은 woff만 존재 → TTF/OTF 원본 확보가 선행. 확보 전엔 노출 금지(SVIL "깨진 옵션 금지") |
| **프롬프터 "굵게" 체크박스** | (A) 제거 / (B) 굵게 시 Malgun Bold로 폰트 스왑 / (C) 유지(교보에선 효과 없음 안내) | **B 권장.** 저시력 사용자에게 굵기는 유효한 가독성 수단이라 제거보다 폰트 스왑이 접근성에 유리 |

> 위 3건은 사용자(소장님) 확인 후 확정한다. 확정 전에는 D1·D2·D3(색·폰트·컴포넌트)만 선행 진행해도 무방하다.

---

## 7. 작업 순서 및 버전

```
D1 (색) ──→ D2 (폰트·볼드제거) ──→ D3 (컴포넌트)     ← 시각 전환 본체
                                     └─→ D4 (설정 3표준, 6장 결정 후)
```

- 권장 버전: D1~D3 완료 = **v1.2.0-beta**, D4 포함·다국어 결정 반영 = **v1.2.0**
- `VERSION_HISTORY`에 "SVIL 디자인 표준 전환" 항목 추가(앱 버전 규칙 §).

## 8. 공통 완료 기준

1. `flutter analyze` 0건 / `flutter test` 전체 통과 / `flutter build windows` 성공
2. 본문 대비 ≥ 4.5:1, UI ≥ 3:1 (신규 팔레트 전 조합 검증, 주석 기록)
3. 색상만으로 상태 구분 없음 — 텍스트 라벨 병행(NOW·예약·삭제·초과 등)
4. 최소 폰트 12px(컴팩트) / 본문 18px, 터치 타겟 ≥50px(본문)·≥34px(컴팩트)
5. 숫자·시간·버전·ID는 Consolas 모노
6. 데이터 호환: 기존 SharedPreferences·백업 zip 로드 정상
7. 완료 보고서 `docs/cursor-completion-2026-07-14-svil-design.md` 작성, 로드맵 진행표 갱신

## 9. 리스크 및 주의사항

| 리스크 | 대응 |
|---|---|
| 버튼 반전(밝은 배경+검정) 후 눈에 띔 저하 우려 | SVIL 표준값이며 대비 ≈15:1로 오히려 상승. 무대 프롬프터는 별도 딥다크 유지 |
| 교보손글씨에서 볼드 제거로 위계 약화 | 크기 단계(26/20/18)·색(accent) 강조로 보완, 리스트 제목 20px 확보 |
| 교보손글씨 숫자 가독성 저하 | 숫자·시간은 예외 없이 Consolas 모노로 강제(D2) |
| 나머지 7종 폰트 woff만 존재 | Flutter는 TTF/OTF 필요. 미확보 폰트 노출 금지, D5(별도)에서 원본 확보 |
| 다국어 미도입 시 표준 위반 | v1.2 예약 항목으로 문서화(6장), 문자열 사전화 준비만 선행 |
| 이전 두 지시문과 색·폰트 충돌 | 본 문서가 디자인 시스템 결정을 대체함을 각 문서 상단에 교차 링크 |
