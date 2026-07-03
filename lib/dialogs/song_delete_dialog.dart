// file: lib/dialogs/song_delete_dialog.dart
//
// 곡 삭제 확인 다이얼로그.
import 'package:flutter/material.dart';

import '../models/song.dart';
import '../theme/app_theme.dart';

class SongDeleteDialog {
  SongDeleteDialog._();

  static Future<bool> confirm(BuildContext context, Song song) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        title: const Text('삭제', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          '"${song.title}"을(를) 삭제하시겠습니까?',
          style: const TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return confirmed == true;
  }
}
