import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singpromfter_app/services/app_display_controller.dart';
import 'package:singpromfter_app/theme/app_theme.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppDisplayController.notifier.value = const AppDisplaySettings();
  });

  test('familyFor maps known keys, falls back to brand', () {
    expect(AppDisplayController.familyFor('맑은 고딕'), AppFonts.legible);
    expect(AppDisplayController.familyFor('없는 글꼴'), AppFonts.brand);
  });

  test('labelForScale maps scale to step label', () {
    expect(AppDisplayController.labelForScale(0.9), '작음');
    expect(AppDisplayController.labelForScale(1.0), '보통');
    expect(AppDisplayController.labelForScale(1.15), '큼');
  });

  test('setFont persists and updates notifier; invalid ignored', () async {
    await AppDisplayController.setFont('Segoe UI');
    expect(AppDisplayController.notifier.value.fontKey, 'Segoe UI');

    await AppDisplayController.setFont('깨진 옵션');
    expect(AppDisplayController.notifier.value.fontKey, 'Segoe UI');
  });

  test('load restores persisted values and rejects unknown', () async {
    SharedPreferences.setMockInitialValues({
      'app_display_font': '맑은 고딕',
      'app_display_scale': 1.15,
    });
    await AppDisplayController.load();
    expect(AppDisplayController.notifier.value.fontKey, '맑은 고딕');
    expect(AppDisplayController.notifier.value.textScale, 1.15);

    SharedPreferences.setMockInitialValues({
      'app_display_font': 'bogus',
      'app_display_scale': 9.9,
    });
    await AppDisplayController.load();
    expect(
      AppDisplayController.notifier.value.fontKey,
      AppDisplayController.defaultFontKey,
    );
    expect(AppDisplayController.notifier.value.textScale, 1.0);
  });

  test('AppDisplaySettings copyWith preserves unset fields', () {
    const s = AppDisplaySettings(fontKey: 'Segoe UI', textScale: 1.15);
    final c = s.copyWith(textScale: 0.9);
    expect(c.fontKey, 'Segoe UI');
    expect(c.textScale, 0.9);
    expect(describeIdentity(c).isNotEmpty, true);
  });
}
