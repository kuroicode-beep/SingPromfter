// file: lib/dialogs/duet_mix_dialog.dart
//
// 듀엣 합성 — 남자 파트·여자 파트 테이크를 하나씩 골라 반주와 합친다.
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/recording_take.dart';
import '../theme/app_theme.dart';

class DuetMixSelection {
  final RecordingTake partA;
  final RecordingTake partB;

  const DuetMixSelection({required this.partA, required this.partB});
}

class DuetMixDialog {
  DuetMixDialog._();

  /// 테이크 표시 이름 — 곡·시각·코멘트로 구분한다.
  static String takeLabel(RecordingTake take) {
    String two(int v) => v.toString().padLeft(2, '0');
    final at = take.recordedAt;
    final when =
        '${two(at.month)}/${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
    final comment = take.comment.trim();
    return comment.isEmpty
        ? '${take.songTitle} · $when'
        : '${take.songTitle} · $when · $comment';
  }

  static Future<DuetMixSelection?> show(
    BuildContext context,
    List<RecordingTake> takes,
  ) {
    RecordingTake? partA;
    RecordingTake? partB;
    return showDialog<DuetMixSelection>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Widget partPicker({
            required String label,
            required RecordingTake? value,
            required ValueChanged<RecordingTake?> onChanged,
          }) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Semantics(
                label: label,
                child: DropdownButtonFormField<RecordingTake>(
                  initialValue: value,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: label,
                    labelStyle: const TextStyle(color: AppColors.textMuted),
                  ),
                  dropdownColor: AppColors.surface,
                  style: AppTypography.body,
                  items: takes
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(
                            takeLabel(t),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: onChanged,
                ),
              ),
            );
          }

          final ready = partA != null && partB != null && partA != partB;
          final sameSong =
              partA == null || partB == null || partA!.songId == partB!.songId;
          return AlertDialog(
            backgroundColor: AppColors.elevated,
            title: const Text(
              '듀엣 합성',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '남자 파트와 여자 파트로 녹음한 테이크를 하나씩 고르면 '
                    '반주에 맞춰 한 곡으로 합칩니다.',
                    style: AppTypography.bodyMuted,
                  ),
                  const SizedBox(height: 16),
                  partPicker(
                    label: '남자 파트 테이크',
                    value: partA,
                    onChanged: (t) => setLocal(() => partA = t),
                  ),
                  partPicker(
                    label: '여자 파트 테이크',
                    value: partB,
                    onChanged: (t) => setLocal(() => partB = t),
                  ),
                  if (partA != null && partA == partB)
                    Text(
                      '서로 다른 테이크를 골라 주세요.',
                      style: AppTypography.bodyMuted.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  if (!sameSong)
                    Text(
                      '서로 다른 곡의 테이크입니다 — 합성은 되지만 반주는 '
                      '남자 파트 곡을 따릅니다.',
                      style: AppTypography.bodyMuted,
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(120, AppConstants.minTouchTarget),
                ),
                onPressed: ready
                    ? () => Navigator.pop(
                        ctx,
                        DuetMixSelection(partA: partA!, partB: partB!),
                      )
                    : null,
                child: const Text('합성하기'),
              ),
            ],
          );
        },
      ),
    );
  }
}
