// file: lib/widgets/snack_message.dart
//
// 짧은 사용자 알림 스낵바를 표시한다.
import 'package:flutter/material.dart';

class SnackMessage {
  SnackMessage._();

  static void show(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }
}
