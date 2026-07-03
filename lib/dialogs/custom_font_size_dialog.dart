// file: lib/dialogs/custom_font_size_dialog.dart
//
// 접근성 설정의 사용자 정의 글자 크기를 입력받는 다이얼로그.
import 'package:flutter/material.dart';

import '../models/prompter_settings.dart';
import '../theme/app_theme.dart';

class CustomFontSizeDialog {
  CustomFontSizeDialog._();

  static Future<double?> show(BuildContext context, double currentFontSizePt) {
    final controller = TextEditingController(
      text: currentFontSizePt.round().toString(),
    );

    return showDialog<double>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('사용자 정의 글자 크기'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '글자 크기(pt)',
              helperText: '12~120 사이 값을 입력하세요.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, double.nan),
              child: const Text('단계값 사용'),
            ),
            ElevatedButton(
              onPressed: () {
                final parsed = double.tryParse(controller.text.trim());
                if (parsed == null) return;
                Navigator.pop(ctx, parsed.clamp(12, 120).toDouble());
              },
              child: const Text('적용'),
            ),
          ],
        );
      },
    );
  }

  static Future<PrompterSettings?> pickSettings(
    BuildContext context,
    PrompterSettings settings,
  ) async {
    final value = await show(
      context,
      settings.customFontSizePt ?? settings.effectiveFontSizePt,
    );
    if (value == null) return null;
    if (value.isNaN) return settings.copyWith(clearCustomFontSize: true);
    return settings.copyWith(customFontSizePt: value);
  }
}
