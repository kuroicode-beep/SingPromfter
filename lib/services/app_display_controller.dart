// file: lib/services/app_display_controller.dart
//
// 앱 전역 표시 설정(글꼴·글자 크기)을 관리한다. SVIL 설정 표준.
// ValueNotifier로 루트가 구독해 테마 글꼴과 MediaQuery 텍스트 배율을 갱신한다.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

@immutable
class AppDisplaySettings {
  final String fontKey;
  final double textScale;

  const AppDisplaySettings({
    this.fontKey = AppDisplayController.defaultFontKey,
    this.textScale = 1.0,
  });

  AppDisplaySettings copyWith({String? fontKey, double? textScale}) {
    return AppDisplaySettings(
      fontKey: fontKey ?? this.fontKey,
      textScale: textScale ?? this.textScale,
    );
  }
}

class AppDisplayController {
  AppDisplayController._();

  static const String defaultFontKey = '교보손글씨2019';
  static const String _fontPrefKey = 'app_display_font';
  static const String _scalePrefKey = 'app_display_scale';

  // 실재하는(번들된) 글꼴만 노출 — SVIL "깨진 옵션 금지".
  static const Map<String, String> fontFamilies = {
    '교보손글씨2019': AppFonts.brand,
    '맑은 고딕': AppFonts.legible,
    'Segoe UI': 'SegoeUI',
  };

  // 글자 크기 3단계 (본문 배율). 큰 배율은 레이아웃 여유를 고려해 절제.
  static const Map<String, double> sizeSteps = {
    '작음': 0.9,
    '보통': 1.0,
    '큼': 1.15,
  };

  static final ValueNotifier<AppDisplaySettings> notifier =
      ValueNotifier<AppDisplaySettings>(const AppDisplaySettings());

  static String familyFor(String fontKey) =>
      fontFamilies[fontKey] ?? AppFonts.brand;

  static String labelForScale(double scale) {
    for (final entry in sizeSteps.entries) {
      if ((entry.value - scale).abs() < 0.001) return entry.key;
    }
    return '보통';
  }

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final fontKey = prefs.getString(_fontPrefKey);
    final scale = prefs.getDouble(_scalePrefKey);
    notifier.value = AppDisplaySettings(
      fontKey: fontFamilies.containsKey(fontKey) ? fontKey! : defaultFontKey,
      textScale: sizeSteps.values.contains(scale) ? scale! : 1.0,
    );
  }

  static Future<void> setFont(String fontKey) async {
    if (!fontFamilies.containsKey(fontKey)) return;
    notifier.value = notifier.value.copyWith(fontKey: fontKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fontPrefKey, fontKey);
  }

  static Future<void> setScale(double scale) async {
    if (!sizeSteps.values.contains(scale)) return;
    notifier.value = notifier.value.copyWith(textScale: scale);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_scalePrefKey, scale);
  }
}
