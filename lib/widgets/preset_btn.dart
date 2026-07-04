// file: lib/widgets/preset_btn.dart
//
// 접근성 프리셋과 사용자 정의 글자 크기 진입에 사용하는 버튼.
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PresetBtn extends StatelessWidget {
  final String label;
  final String? semanticsLabel;
  final VoidCallback onTap;

  const PresetBtn({
    super.key,
    required this.label,
    required this.onTap,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel ?? label,
      button: true,
      enabled: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 50, minHeight: 50),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: AppShapes.controlRadius,
          ),
          child: ExcludeSemantics(
            child: Text(
              label,
              style: AppTypography.labelStrong,
            ),
          ),
        ),
      ),
    );
  }
}
