// file: lib/dialogs/song_edit_dialog.dart
//
// 곡 수정 시 제목, 가사 교체, 반주 교체 입력을 담당하는 다이얼로그.
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/song.dart';
import '../models/song_draft.dart';
import '../theme/app_theme.dart';

class SongEditDialog {
  SongEditDialog._();

  static Future<SongEditDraft?> show(BuildContext context, Song song) {
    final titleController = TextEditingController(text: song.title);
    final artistController = TextEditingController(text: song.artist);
    final trackPaths = <int, String?>{1: null, 2: null, 3: null};
    final trackLabels = <int, String>{
      for (final slot in AppConstants.backingTrackSlots)
        slot: song.trackForSlot(slot)?.label ?? 'MR$slot',
    };
    final trackStartMs = <int, int?>{
      for (final slot in AppConstants.backingTrackSlots)
        slot: song.trackForSlot(slot)?.startMs,
    };
    final trackEndMs = <int, int?>{
      for (final slot in AppConstants.backingTrackSlots)
        slot: song.trackForSlot(slot)?.endMs,
    };
    String? nextLyricsText;
    String? nextLyricsFileName;

    return showDialog<SongEditDraft>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> pickLyrics() async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['txt'],
                dialogTitle: '새 가사 파일(txt) 선택',
              );
              if (!ctx.mounted) return;
              if (result == null || result.files.isEmpty) return;

              final picked = result.files.first;
              if ((picked.extension ?? '').toLowerCase() != 'txt') {
                _showDialogSnack(ctx, 'txt 파일만 선택할 수 있습니다.');
                return;
              }

              List<int>? bytes = picked.bytes;
              if (bytes == null && picked.path != null) {
                try {
                  bytes = await File(picked.path!).readAsBytes();
                } catch (e, stack) {
                  debugPrint('수정용 가사 파일 바이트 읽기 실패: $e\n$stack');
                }
              }
              if (!ctx.mounted) return;
              if (bytes == null) {
                _showDialogSnack(ctx, '가사 파일 내용을 읽을 수 없습니다.');
                return;
              }

              try {
                final decoded = _decodeLyricsFromBytes(bytes);
                setLocal(() {
                  nextLyricsText = decoded;
                  nextLyricsFileName = picked.name;
                });
              } catch (e, stack) {
                debugPrint('수정용 가사 파일 디코딩 실패: $e\n$stack');
                _showDialogSnack(ctx, '가사 파일 읽기에 실패했습니다.');
              }
            }

            Future<void> pickTrack(int slot) async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.audio,
                dialogTitle: '새 반주$slot 파일 선택',
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
                '곡 수정',
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
                      const SizedBox(height: 12),
                      TextField(
                        controller: artistController,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                        ),
                        decoration: const InputDecoration(
                          labelText: '가수 (선택)',
                          labelStyle: TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _LyricsPickerCard(
                        fileName: nextLyricsFileName,
                        onPick: pickLyrics,
                        onKeep: () {
                          setLocal(() {
                            nextLyricsText = null;
                            nextLyricsFileName = null;
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '반주 교체 (선택: 0~3개)',
                        style: AppTypography.bodyMuted,
                      ),
                      const SizedBox(height: 8),
                      for (final slot in AppConstants.backingTrackSlots)
                        _TrackEditRow(
                          label: '반주$slot (mp3)',
                          value: trackPaths[slot] != null
                              ? trackPaths[slot]!.split('\\').last
                              : (song.trackForSlot(slot)?.fileName ?? '없음'),
                          selected: trackPaths[slot] != null,
                          labelValue: trackLabels[slot] ?? 'MR$slot',
                          onLabelChanged: (value) => trackLabels[slot] = value,
                          startMs: trackStartMs[slot],
                          endMs: trackEndMs[slot],
                          onStartChanged: (value) =>
                              trackStartMs[slot] = _parseSeconds(value),
                          onEndChanged: (value) =>
                              trackEndMs[slot] = _parseSeconds(value),
                          onPick: () => pickTrack(slot),
                          onKeep: () => setLocal(() => trackPaths[slot] = null),
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
                        ? song.title
                        : titleController.text.trim();
                    final normalized = <int, String>{};
                    final normalizedLabels = <int, String>{};
                    final normalizedStartMs = <int, int?>{};
                    final normalizedEndMs = <int, int?>{};
                    trackPaths.forEach((slot, path) {
                      if (path != null && path.trim().isNotEmpty) {
                        normalized[slot] = path;
                      }
                    });
                    trackLabels.forEach((slot, label) {
                      if (label.trim().isNotEmpty) {
                        normalizedLabels[slot] = label;
                      }
                    });
                    trackStartMs.forEach((slot, value) {
                      normalizedStartMs[slot] = value;
                    });
                    trackEndMs.forEach((slot, value) {
                      normalizedEndMs[slot] = value;
                    });
                    Navigator.pop(
                      ctx,
                      SongEditDraft(
                        title: title,
                        artist: artistController.text.trim(),
                        lyricsText: nextLyricsText,
                        trackPaths: normalized,
                        trackLabels: normalizedLabels,
                        trackStartMs: normalizedStartMs,
                        trackEndMs: normalizedEndMs,
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

  static String _decodeLyricsFromBytes(List<int> bytes) {
    try {
      return utf8.decode(bytes).trim();
    } catch (e, stack) {
      debugPrint('UTF-8 가사 디코딩 실패, latin1 fallback 사용: $e\n$stack');
      return latin1.decode(bytes).trim();
    }
  }

  static int? _parseSeconds(String value) {
    final parsed = double.tryParse(value.trim());
    if (parsed == null || parsed <= 0) return null;
    return (parsed * 1000).round();
  }
}

class _LyricsPickerCard extends StatelessWidget {
  final String? fileName;
  final VoidCallback onPick;
  final VoidCallback onKeep;

  const _LyricsPickerCard({
    required this.fileName,
    required this.onPick,
    required this.onKeep,
  });

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '가사 (txt)',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            fileName ?? '기존 파일 유지',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fileName == null
                  ? AppColors.textMuted
                  : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ElevatedButton(
                onPressed: onPick,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(88, 42),
                ),
                child: const Text('다시 선택'),
              ),
              const SizedBox(width: 6),
              TextButton(onPressed: onKeep, child: const Text('유지')),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrackEditRow extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final String labelValue;
  final int? startMs;
  final int? endMs;
  final ValueChanged<String> onLabelChanged;
  final ValueChanged<String> onStartChanged;
  final ValueChanged<String> onEndChanged;
  final VoidCallback onPick;
  final VoidCallback onKeep;

  const _TrackEditRow({
    required this.label,
    required this.value,
    required this.selected,
    required this.labelValue,
    required this.startMs,
    required this.endMs,
    required this.onLabelChanged,
    required this.onStartChanged,
    required this.onEndChanged,
    required this.onPick,
    required this.onKeep,
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
                  child: const Text('교체'),
                ),
                const SizedBox(width: 6),
                TextButton(onPressed: onKeep, child: const Text('유지')),
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
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _secondsText(startMs),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: '시작(초)',
                      labelStyle: TextStyle(color: AppColors.textMuted),
                      isDense: true,
                    ),
                    onChanged: onStartChanged,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    initialValue: _secondsText(endMs),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: '끝(초)',
                      labelStyle: TextStyle(color: AppColors.textMuted),
                      isDense: true,
                    ),
                    onChanged: onEndChanged,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _secondsText(int? value) =>
      value == null ? '' : (value / 1000).toStringAsFixed(1);
}

void _showDialogSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
