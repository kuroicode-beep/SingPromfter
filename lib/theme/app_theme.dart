import 'package:flutter/material.dart';

/// Core Precision Dark 팔레트 (Sprint 6).
/// WCAG AA 대비값은 아래 주석에 기록한다.
class AppColors {
  AppColors._();

  // Surface / tunnel layering
  static const background = Color(0xFF0E0D15);
  static const surface = Color(0xFF13131A);
  static const surfaceContainer = Color(0xFF1F1F27);
  static const elevated = Color(0xFF2A2931);

  // Brand emphasis
  static const primary = Color(0xFFC2C1FF);
  static const primaryContainer = Color(0xFF5856D6);
  static const secondary = Color(0xFFADC6FF);
  static const tertiary = Color(0xFFFFB785);

  // Content
  static const onSurface = Color(0xFFE4E1EC);
  static const onSurfaceVariant = Color(0xFFC7C4D6);
  static const onPrimaryContainer = Color(0xFFFFFFFF);

  // Structure
  static const outline = Color(0xFF464554);
  static const danger = Color(0xFFFFB4AB);

  // Selection / state
  static const selectedSurface = Color(0x1A5856D6);

  // Legacy aliases (기존 위젯 호환, 값은 Core Precision Dark 기준)
  static const accent = primary;
  static const accentHover = secondary;
  static const textPrimary = onSurface;
  static const textMuted = onSurfaceVariant;
  static const border = outline;

  // WCAG 2.1 AA contrast notes (dark theme, approximate):
  // onSurface #E4E1EC on background #0E0D15: ~14:1
  // onSurfaceVariant #C7C4D6 on surface #13131A: ~9:1
  // primary #C2C1FF on background #0E0D15: ~11:1
  // onPrimaryContainer #FFFFFF on primaryContainer #5856D6: ~5.5:1
  // secondary #ADC6FF on background #0E0D15: ~10:1
  // tertiary #FFB785 on surfaceContainer #1F1F27: ~7:1
}

class AppTheme {
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
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
          fontFamily: 'sans-serif',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.onSurface,
          letterSpacing: 0.3,
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
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: AppColors.onSurfaceVariant),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.primary,
        thumbColor: AppColors.primary,
        inactiveTrackColor: AppColors.elevated,
        overlayColor: Color(0x33C2C1FF),
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
        color: AppColors.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.outline),
        ),
      ),
    );
  }
}
