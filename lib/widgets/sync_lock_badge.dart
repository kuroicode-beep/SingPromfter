// file: lib/widgets/sync_lock_badge.dart
//
// 싱크 잠금(L) 상태 배지 — 프롬프터 우상단에 띄운다.
// "L이 눌렸는지 확인이 어렵다"는 실사용 요청. 색이 아니라 자물쇠 모양으로
// 알리고, 잠금이 아니면 아무것도 없다. v5.6.0에서 글자를 빼고 아이콘만
// 남겼다(가사 가림 최소화) — 아이콘을 키우고 Semantics·Tooltip을 남긴다.
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
        // 🔴 노드를 만들었다 지우지 않는다 — 항상 같은 노드를 두고 라벨만 바꾼다.
        // 켜질 때 생기고 꺼질 때 사라지는 접근성 노드가 Flutter 엔진 크래시를
        // 냈다(2026-09-22, center_alert.dart 머리말 참고).
        return Semantics(
          container: true,
          label: value ? '싱크 잠금 중 — L로 해제' : '',
          child: !value
              ? const SizedBox.shrink()
              : Tooltip(
                  message: '싱크 잠금 중 — L로 해제',
                  // 툴팁도 자체 노드를 만들지 않게 한다(라벨은 위에서 준다).
                  excludeFromSemantics: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.elevated.withValues(alpha: 0.92),
                      border: Border.all(color: AppColors.tertiary, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.lock,
                      size: 34,
                      color: AppColors.tertiary,
                    ),
                  ),
                ),
        );
      },
    );
  }
}
