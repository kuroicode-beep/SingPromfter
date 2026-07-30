// file: lib/widgets/collapsible_queue_sidebar.dart
//
// 예약 큐 사이드바 — 드로어 아이콘으로 여닫는다(기본 열림, 설정에 저장).
//
// v2.15까지는 "큐가 비면 자동으로 접히고 차면 자동으로 펴지는" 규칙이었는데,
// 화면이 스스로 움직이면 저시력 사용자가 배치를 외울 수 없다. 이제 사용자가
// 아이콘으로 정한 상태가 그대로 유지된다.
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../theme/app_theme.dart';

class CollapsibleQueueSidebar extends StatelessWidget {
  final bool open;
  final ValueChanged<bool> onOpenChanged;

  /// 접힌 상태에서도 몇 곡이 기다리는지 보여 준다(색이 아니라 숫자로).
  final int queueLength;
  final Widget child;

  const CollapsibleQueueSidebar({
    super.key,
    required this.open,
    required this.onOpenChanged,
    required this.queueLength,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!open) {
      return SizedBox(
        width: 52,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Semantics(
              label: '예약 큐 열기, $queueLength곡 대기 중',
              button: true,
              child: IconButton(
                onPressed: () => onOpenChanged(true),
                icon: const Icon(Icons.queue_music, color: AppColors.textMuted),
                tooltip: '예약 큐 열기',
                constraints: const BoxConstraints(
                  minWidth: AppConstants.minTouchTarget,
                  minHeight: AppConstants.minTouchTarget,
                ),
              ),
            ),
            if (queueLength > 0)
              Text('$queueLength', style: AppTypography.monoMuted),
          ],
        ),
      );
    }

    return SizedBox(
      width: AppConstants.homeQueueWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Semantics(
              label: '예약 큐 숨기기',
              button: true,
              child: IconButton(
                onPressed: () => onOpenChanged(false),
                icon: const Icon(Icons.chevron_right),
                tooltip: '예약 큐 숨기기',
                constraints: const BoxConstraints(
                  minWidth: AppConstants.minTouchTarget,
                  minHeight: AppConstants.minTouchTarget,
                ),
              ),
            ),
          ),
          // 상단 고정 — 남는 높이를 큐가 전부 갖는다.
          Expanded(child: child),
        ],
      ),
    );
  }
}
