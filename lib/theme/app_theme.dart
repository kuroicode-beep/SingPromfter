import 'package:flutter/material.dart';

/// SVIL 프론트엔드 표준 팔레트 (고대비 다크 + 블루 accent).
/// 참조: svil-frontend-design 가이드. 대비값은 아래 주석에 기록한다.
class AppColors {
  AppColors._();

  // Surface (토널 레이어링)
  static const background = Color(0xFF0D0D12); // SVIL bg
  static const surface = Color(0xFF16161D); // SVIL surface (앱바·카드)
  static const surfaceContainer = Color(0xFF1F1F2A); // SVIL surface-2 (패널)
  static const elevated = Color(0xFF262633); // 입력·hover 표면

  // 강조 (블루)
  static const primary = Color(0xFF7EC8FF); // accent: 강조·선택·링크·아이콘
  static const primaryContainer = Color(0xFFB3DDFF); // accent-strong: 주 버튼 배경
  static const secondary = Color(0xFF7EC8FF); // 포커스·보조 강조
  static const tertiary = Color(0xFFFFD479); // warning: 예약·주의

  // 강조 파생
  static const accentStrong = Color(0xFFB3DDFF);
  static const accentMax = Color(0xFFD6ECFF); // 주 버튼 hover
  static const positive = Color(0xFF7EE2A8);
  static const focus = Color(0xFFFFD479); // 포커스 링

  // 콘텐츠
  static const onSurface = Color(0xFFF5F5F7); // text
  static const onSurfaceVariant = Color(0xFFC9C9D4); // text-sub
  static const onPrimaryContainer = Color(0xFF000000); // accent-strong 위 = 검정

  // 구조
  static const outline = Color(0xFF3A3A48); // 일반 경계선
  static const borderStrong = Color(0xFF6B6B82); // 버튼 테두리 (대비 ≥3:1)
  static const danger = Color(0xFFFF9B9B); // negative

  // 선택 상태 배경 (accent 10%)
  static const selectedSurface = Color(0x1A7EC8FF);

  // Legacy aliases (기존 위젯 호환, 값은 SVIL 기준)
  static const accent = primary;
  static const accentHover = accentMax;
  static const textPrimary = onSurface;
  static const textMuted = onSurfaceVariant;
  static const border = outline;

  // WCAG 2.1 대비 (dark theme, approximate):
  // onSurface #F5F5F7 on background #0D0D12: ~16:1
  // onSurfaceVariant #C9C9D4 on surface #16161D: ~10:1
  // primary(accent) #7EC8FF on background #0D0D12: ~10:1
  // onPrimaryContainer #000000 on primaryContainer #B3DDFF: ~15:1 (주 버튼)
  // tertiary #FFD479 on surfaceContainer #1F1F2A: ~11:1
  // danger #FF9B9B on surface #16161D: ~7:1
  // borderStrong #6B6B82 on surfaceContainer #1F1F2A: ~3:1 (버튼 테두리)
}

/// SVIL 폰트: 교보손글씨2019(브랜드) / Consolas(숫자·시간) / Malgun(고가독 무대).
class AppFonts {
  AppFonts._();

  static const String brand = 'KyoboHandwriting2019';
  static const String mono = 'Consolas';
  static const String legible = 'MalgunGothic';
}

/// SVIL 셰이프·타이포 규칙.
/// 교보손글씨2019는 단일 굵기 → 위계는 크기·색으로 표현(볼드 합성 금지).
class AppShapes {
  AppShapes._();

  static const double panelRadiusValue = 16;
  static const double controlRadiusValue = 12;
  static const BorderRadius panelRadius = BorderRadius.all(Radius.circular(16));
  static const BorderRadius controlRadius = BorderRadius.all(
    Radius.circular(12),
  );

  static BoxDecoration panel({Color? color}) => BoxDecoration(
    color: color ?? AppColors.surfaceContainer,
    borderRadius: panelRadius,
    border: Border.all(color: AppColors.outline),
  );
}

class AppTypography {
  AppTypography._();

  // 위계는 크기로. 볼드(FontWeight) 미사용 — 교보손글씨는 단일 굵기.
  static const screenTitle = TextStyle(
    fontFamily: AppFonts.brand,
    fontSize: 24,
    color: AppColors.onSurface,
  );
  static const listTitle = TextStyle(
    fontFamily: AppFonts.brand,
    fontSize: 19,
    color: AppColors.onSurface,
  );
  static const body = TextStyle(
    fontFamily: AppFonts.brand,
    fontSize: 16,
    color: AppColors.onSurface,
  );
  static const bodyMuted = TextStyle(
    fontFamily: AppFonts.brand,
    fontSize: 16,
    color: AppColors.onSurfaceVariant,
  );
  // 강조는 색(accent)으로. (구 labelStrong 자리 호환)
  static const labelStrong = TextStyle(
    fontFamily: AppFonts.brand,
    fontSize: 16,
    color: AppColors.onSurface,
  );
  static const emphasis = TextStyle(
    fontFamily: AppFonts.brand,
    fontSize: 16,
    color: AppColors.primary,
  );

  // 숫자·시간·버전·ID 전용 모노.
  static const mono = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 16,
    color: AppColors.onSurface,
  );
  static const monoMuted = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 15,
    color: AppColors.onSurfaceVariant,
  );
}

class AppTheme {
  static ThemeData dark({String fontFamily = AppFonts.brand}) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.surface,
        primary: AppColors.primaryContainer,
        onPrimary: AppColors.onPrimaryContainer,
        secondary: AppColors.secondary,
        tertiary: AppColors.tertiary,
        onSurface: AppColors.onSurface,
        outline: AppColors.outline,
        error: AppColors.danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: AppFonts.brand,
          fontSize: 20,
          color: AppColors.onSurface,
          letterSpacing: 0.2,
        ),
      ),
      dividerColor: AppColors.outline,
      dividerTheme: const DividerThemeData(
        color: AppColors.outline,
        thickness: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryContainer,
          foregroundColor: AppColors.onPrimaryContainer,
          shape: const RoundedRectangleBorder(
            borderRadius: AppShapes.controlRadius,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.onSurfaceVariant,
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.primary,
        thumbColor: AppColors.primary,
        inactiveTrackColor: AppColors.elevated,
        overlayColor: Color(0x337EC8FF),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: AppColors.onSurface),
        bodyMedium: TextStyle(color: AppColors.onSurface),
        bodySmall: TextStyle(color: AppColors.onSurfaceVariant),
        labelSmall: TextStyle(color: AppColors.onSurfaceVariant),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primaryContainer,
        foregroundColor: AppColors.onPrimaryContainer,
        elevation: 4,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppShapes.panelRadius,
          side: const BorderSide(color: AppColors.outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.elevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: AppShapes.controlRadius,
          borderSide: const BorderSide(color: AppColors.borderStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppShapes.controlRadius,
          borderSide: const BorderSide(color: AppColors.borderStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppShapes.controlRadius,
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }
}
