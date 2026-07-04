// file: lib/widgets/collapsible_queue_sidebar.dart
//
// 빈 예약 큐일 때 폭을 줄이고 접이식으로 전환하는 사이드바.
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../theme/app_theme.dart';

class CollapsibleQueueSidebar extends StatefulWidget {
  final bool queueIsEmpty;
  final Widget child;

  const CollapsibleQueueSidebar({
    super.key,
    required this.queueIsEmpty,
    required this.child,
  });

  @override
  State<CollapsibleQueueSidebar> createState() => _CollapsibleQueueSidebarState();
}

class _CollapsibleQueueSidebarState extends State<CollapsibleQueueSidebar> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant CollapsibleQueueSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.queueIsEmpty) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.queueIsEmpty) {
      return SizedBox(
        width: AppConstants.homeQueueWidth,
        child: widget.child,
      );
    }

    if (!_expanded) {
      return SizedBox(
        width: 52,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Semantics(
              label: '예약 큐 열기',
              button: true,
              child: IconButton(
                onPressed: () => setState(() => _expanded = true),
                icon: const Icon(Icons.queue_music, color: AppColors.textMuted),
                tooltip: '예약 큐',
                constraints: const BoxConstraints(
                  minWidth: AppConstants.minTouchTarget,
                  minHeight: AppConstants.minTouchTarget,
                ),
              ),
            ),
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
            child: IconButton(
              onPressed: () => setState(() => _expanded = false),
              icon: const Icon(Icons.chevron_right),
              tooltip: '예약 큐 접기',
              constraints: const BoxConstraints(
                minWidth: AppConstants.minTouchTarget,
                minHeight: AppConstants.minTouchTarget,
              ),
            ),
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}
