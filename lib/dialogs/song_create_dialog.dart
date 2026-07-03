// file: lib/dialogs/song_create_dialog.dart
//
// 곡 등록 시 제목과 선택 반주 파일들을 입력받는 다이얼로그.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/song_draft.dart';
import '../theme/app_theme.dart';

class SongCreateDialog {
  SongCreateDialog._();

  static Future<SongDraft?> show(BuildContext context, String fileName) {
    final titleController = TextEditingController(
      text: fileName.replaceAll(RegExp(r'\.txt$', caseSensitive: false), ''),
    );
    final trackPaths = <int, String?>{1: null, 2: null, 3: null};
    final trackLabels = <int, String>{1: 'MR1', 2: 'MR2', 3: 'MR3'};

    return showDialog<SongDraft>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> pickTrack(int slot) async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.audio,
                dialogTitle: '반주$slot 파일 선택',
              );
              if (!ctx.mounted) return;
              if (result == null || result.files.isEmpty) return;
              final path = result.files.first.path;
              if (path == null) {
                _showDialogSnack(ctx, '반주 파일 경로를 읽을 수 없습니다.');
                return;
              }
              setLocal(() => trackPaths[slot] = path);
            }

            final maxWidth = MediaQuery.of(ctx).size.width;
            final dialogWidth = (maxWidth * 0.86).clamp(620.0, 920.0);

            return AlertDialog(
              backgroundColor: AppColors.elevated,
              title: const Text(
                '곡 등록 (가사1 + 반주1~3)',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              content: SizedBox(
                width: dialogWidth,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: titleController,
                        autofocus: true,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                        ),
                        decoration: const InputDecoration(
                          labelText: '곡 제목',
                          labelStyle: TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _InfoRow(label: '가사1 (txt)', value: fileName),
                      const SizedBox(height: 14),
                      const Text(
                        '반주 (선택: 0~3개)',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final slot in AppConstants.backingTrackSlots)
                        _TrackPickerRow(
                          label: '반주$slot (mp3)',
                          value: trackPaths[slot] == null
                              ? '선택 안 됨'
                              : trackPaths[slot]!.split('\\').last,
                          selected: trackPaths[slot] != null,
                          pickLabel: '선택',
                          clearLabel: '취소',
                          labelValue: trackLabels[slot] ?? 'MR$slot',
                          onLabelChanged: (value) => trackLabels[slot] = value,
                          onPick: () => pickTrack(slot),
                          onClear: () =>
                              setLocal(() => trackPaths[slot] = null),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('닫기'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final title = titleController.text.trim().isEmpty
                        ? fileName
                        : titleController.text.trim();
                    final normalized = <int, String>{};
                    final normalizedLabels = <int, String>{};
                    trackPaths.forEach((slot, path) {
                      if (path != null && path.trim().isNotEmpty) {
                        normalized[slot] = path;
                        normalizedLabels[slot] = trackLabels[slot] ?? 'MR$slot';
                      }
                    });
                    Navigator.pop(
                      ctx,
                      SongDraft(
                        title: title,
                        trackPaths: normalized,
                        trackLabels: normalizedLabels,
                      ),
                    );
                  },
                  child: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 98,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackPickerRow extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final String pickLabel;
  final String clearLabel;
  final String labelValue;
  final ValueChanged<String> onLabelChanged;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _TrackPickerRow({
    required this.label,
    required this.value,
    required this.selected,
    required this.pickLabel,
    required this.clearLabel,
    required this.labelValue,
    required this.onLabelChanged,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 98,
                  child: Text(
                    label,
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: onPick,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(88, 42),
                  ),
                  child: Text(pickLabel),
                ),
                const SizedBox(width: 6),
                TextButton(onPressed: onClear, child: Text(clearLabel)),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: labelValue,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: '반주 라벨',
                labelStyle: TextStyle(color: AppColors.textMuted),
                isDense: true,
              ),
              onChanged: onLabelChanged,
            ),
          ],
        ),
      ),
    );
  }
}

void _showDialogSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
