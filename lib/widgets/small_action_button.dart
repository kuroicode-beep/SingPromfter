// file: lib/widgets/small_action_button.dart
//
// 곡 카드에서 사용하는 접근성 라벨 포함 소형 액션 버튼.
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SmallActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  const SmallActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      enabled: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: primary ? AppColors.primaryContainer : AppColors.border,
            borderRadius: AppShapes.controlRadius,
          ),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: primary
                      ? AppColors.onPrimaryContainer
                      : AppColors.textPrimary,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: AppTypography.labelStrong.copyWith(
                    color: primary
                        ? AppColors.onPrimaryContainer
                        : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
