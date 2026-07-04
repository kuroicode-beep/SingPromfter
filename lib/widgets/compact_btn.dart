// file: lib/widgets/compact_btn.dart
//
// 프롬프터 하단 제어 바의 50dp 접근성 버튼.
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../theme/app_theme.dart';

class CompactBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool highlighted;
  final String semanticsLabel;
  final bool? toggled;

  const CompactBtn({
    super.key,
    required this.icon,
    required this.onTap,
    required this.semanticsLabel,
    this.highlighted = false,
    this.toggled,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      button: true,
      enabled: true,
      toggled: toggled,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: AppConstants.minTouchTarget,
          height: AppConstants.minTouchTarget,
          decoration: BoxDecoration(
            color: highlighted ? AppColors.primaryContainer : AppColors.elevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: highlighted ? AppColors.primaryContainer : AppColors.border,
            ),
          ),
          child: ExcludeSemantics(
            child: Icon(
              icon,
              size: 24,
              color: highlighted
                  ? AppColors.onPrimaryContainer
                  : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
