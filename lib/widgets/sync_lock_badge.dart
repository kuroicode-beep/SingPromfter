// file: lib/widgets/sync_lock_badge.dart
//
// 싱크 잠금(L) 상태 배지 — 프롬프터 좌상단에 크게 띄운다.
// "L이 눌렸는지 확인이 어렵다"는 실사용 요청. 저시력 기준으로 색이
// 아니라 자물쇠 아이콘 + 글자로 알리고, 잠금이 아니면 아무것도 없다.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SyncLockBadge extends StatelessWidget {
  final ValueListenable<bool> locked;

  const SyncLockBadge({super.key, required this.locked});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: locked,
      builder: (context, value, _) {
        if (!value) return const SizedBox.shrink();
        return Semantics(
          label: '싱크 잠금 중 — L로 해제',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.elevated.withValues(alpha: 0.92),
              border: Border.all(color: AppColors.tertiary, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock, size: 30, color: AppColors.tertiary),
                SizedBox(width: 8),
                Text(
                  '싱크 잠금',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
