// file: lib/widgets/snack_message.dart
//
// 사용자 알림을 화면 가운데 큰 오버레이 토스트로 표시한다.
// 하단 스낵바는 전체화면 프롬프터·저시력 환경에서 안 보인다는 실사용
// 피드백(v3.20.0)으로 교체됐다. rootOverlay에 띄워 다이얼로그 위에서도 보인다.
import 'dart:async';

import 'package:flutter/material.dart';

class SnackMessage {
  SnackMessage._();

  static OverlayEntry? _entry;
  static Timer? _timer;

  /// [actionLabel]/[onAction]을 주면 토스트에 실행 버튼(예: 실행취소)이 붙는다.
  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 2600),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    dismiss();
    final entry = OverlayEntry(
      builder: (_) => _ToastOverlay(
        message: message,
        actionLabel: actionLabel,
        onAction: onAction == null
            ? null
            : () {
                dismiss();
                onAction();
              },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(duration, dismiss);
  }

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

class _ToastOverlay extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _ToastOverlay({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: onAction == null,
        child: Align(
          // 가운데보다 살짝 아래 — 가사·다이얼로그 본문을 덜 가린다.
          alignment: const Alignment(0, 0.55),
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 720),
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.symmetric(
                horizontal: 28,
                vertical: 20,
              ),
              decoration: BoxDecoration(
                color: const Color(0xF2101418),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.primary, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.campaign, color: scheme.primary, size: 28),
                  const SizedBox(width: 14),
                  Flexible(
                    child: Text(
                      message,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.35,
                      ),
                    ),
                  ),
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(width: 18),
                    FilledButton(
                      onPressed: onAction,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(110, 50),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
