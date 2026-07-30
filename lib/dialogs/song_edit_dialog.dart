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
import '../utils/key_label.dart';
import '../utils/music_key.dart';
import '../utils/pitch_math.dart';

class SongEditDialog {
  SongEditDialog._();

  /// [trackPitches]: 슬롯별 현재 재생 키(반음). 설정에 있는 값이라
  /// 호출하는 쪽(코디네이터)이 넣어 준다.
  static Future<SongEditDraft?> show(
    BuildContext context,
    Song song, {
    Map<int, int> trackPitches = const {},
  }) {
    final titleController = TextEditingController(text: song.title);
    final artistController = TextEditingController(text: song.artist);
    // 자동 감지값을 사람이 읽는 표기로 채워 둔다. 비우면 다시 감지한다.
    final keyController = TextEditingController(
      text: song.musicalKey?.label ?? '',
    );
    String? keyError;
    final trackPaths = <int, String?>{
      for (final slot in AppConstants.backingTrackSlots) slot: null,
    };
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
    final trackBaked = <int, int>{
      for (final slot in AppConstants.backingTrackSlots)
        slot: song.trackForSlot(slot)?.bakedSemitones ?? 0,
    };
    final trackPitch = <int, int>{
      for (final slot in AppConstants.backingTrackSlots)
        slot: trackPitches[slot] ?? 0,
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
                      const SizedBox(height: 12),
                      TextField(
                        controller: keyController,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                        ),
                        decoration: InputDecoration(
                          labelText: '곡 조성 (선택) — 예: C, Am, F♯m',
                          labelStyle: const TextStyle(
                            color: AppColors.textMuted,
                          ),
                          helperText: keyError == null
                              ? '비워 두면 반주에서 자동으로 다시 추정합니다.'
                              : null,
                          helperStyle: const TextStyle(
                            color: AppColors.textMuted,
                          ),
                          errorText: keyError,
                        ),
                        onChanged: (_) {
                          if (keyError != null) setLocal(() => keyError = null);
                        },
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
                      Text(
                        '반주 교체 '
                        '(선택: 0~${AppConstants.maxBackingTrackSlots}개)',
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
                          hasTrack: trackPaths[slot] != null ||
                              song.trackForSlot(slot) != null,
                          labelValue: trackLabels[slot] ?? 'MR$slot',
                          onLabelChanged: (value) => trackLabels[slot] = value,
                          startMs: trackStartMs[slot],
                          endMs: trackEndMs[slot],
                          onStartChanged: (value) =>
                              trackStartMs[slot] = _parseSeconds(value),
                          onEndChanged: (value) =>
                              trackEndMs[slot] = _parseSeconds(value),
                          bakedSemitones: trackBaked[slot] ?? 0,
                          // 구운 키가 바뀌면 실효 키 표시도 따라가야 해서
                          // setLocal로 감싼다.
                          onBakedChanged: (value) => setLocal(
                            () => trackBaked[slot] = _parseSemitones(value),
                          ),
                          pitchSemitones: trackPitch[slot] ?? 0,
                          musicalKey: song.musicalKey,
                          onPitchAdjust: (delta) => setLocal(
                            () => trackPitch[slot] = clampSemitones(
                              (trackPitch[slot] ?? 0) + delta,
                            ),
                          ),
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
                    // 읽을 수 없는 조성은 조용히 버리지 않고 그 자리에서 알린다.
                    final keyText = keyController.text.trim();
                    final parsedKey = MusicKey.parse(keyText);
                    if (keyText.isNotEmpty && parsedKey == null) {
                      setLocal(() => keyError = '조성을 읽을 수 없습니다. C, Am, F♯m 처럼 적어 주세요.');
                      return;
                    }
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
                        applyMusicalKey: true,
                        musicalKey: parsedKey,
                        trackBakedSemitones: Map.of(trackBaked),
                        trackPitchSemitones: Map.of(trackPitch),
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

  /// 구운 키 입력. 비었거나 못 읽으면 0(구운 키 없음)으로 본다.
  static int _parseSemitones(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return 0;
    return parsed.clamp(-12, 12);
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

  /// 기존 파일이 있거나 새로 골랐는지. 없으면 재생 키 줄을 그리지 않는다.
  final bool hasTrack;
  final String labelValue;
  final int? startMs;
  final int? endMs;
  final int bakedSemitones;

  /// 이 슬롯의 재생 키(반음). 파일은 그대로, 재생할 때 변환한다.
  final int pitchSemitones;

  /// 곡 조성. 알면 실효 조성(구운 키+재생 키 반영)을 함께 보여준다.
  final MusicKey? musicalKey;
  final ValueChanged<String> onLabelChanged;
  final ValueChanged<String> onStartChanged;
  final ValueChanged<String> onEndChanged;
  final ValueChanged<String> onBakedChanged;
  final ValueChanged<int> onPitchAdjust;
  final VoidCallback onPick;
  final VoidCallback onKeep;

  const _TrackEditRow({
    required this.label,
    required this.value,
    required this.selected,
    required this.hasTrack,
    required this.labelValue,
    required this.startMs,
    required this.endMs,
    required this.bakedSemitones,
    required this.pitchSemitones,
    required this.musicalKey,
    required this.onLabelChanged,
    required this.onStartChanged,
    required this.onEndChanged,
    required this.onBakedChanged,
    required this.onPitchAdjust,
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
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    initialValue: bakedSemitones == 0
                        ? ''
                        : '$bakedSemitones',
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: '구운 키(반음)',
                      helperText: '이 파일에 이미 반영된 키. 표시용',
                      labelStyle: TextStyle(color: AppColors.textMuted),
                      helperStyle: TextStyle(color: AppColors.textMuted),
                      isDense: true,
                    ),
                    onChanged: onBakedChanged,
                  ),
                ),
              ],
            ),
            if (hasTrack) ...[
              const SizedBox(height: 10),
              _TrackPitchRow(
                slotLabel: labelValue,
                pitchSemitones: pitchSemitones,
                bakedSemitones: bakedSemitones,
                musicalKey: musicalKey,
                onAdjust: onPitchAdjust,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _secondsText(int? value) =>
      value == null ? '' : (value / 1000).toStringAsFixed(1);
}

/// 트랙 하나의 재생 키 조절 줄. 재생바 키 줄과 같은 문법(큰 -/+ 버튼,
/// '원키/2키 낮춤' 말 표기)을 쓰되, 이 반주에만 적용된다는 것을 함께 알린다.
class _TrackPitchRow extends StatelessWidget {
  final String slotLabel;
  final int pitchSemitones;
  final int bakedSemitones;
  final MusicKey? musicalKey;
  final ValueChanged<int> onAdjust;

  const _TrackPitchRow({
    required this.slotLabel,
    required this.pitchSemitones,
    required this.bakedSemitones,
    required this.musicalKey,
    required this.onAdjust,
  });

  @override
  Widget build(BuildContext context) {
    // 실제 들리는 키 = 파일에 구운 키 + 재생 키.
    final effective = bakedSemitones + pitchSemitones;
    final sounding = musicalKey?.transposed(effective);
    final showEffective = sounding != null || bakedSemitones != 0;

    return Row(
      children: [
        const Text('재생 키', style: TextStyle(color: AppColors.textPrimary)),
        const SizedBox(width: 8),
        Semantics(
          label: '$slotLabel 키 한 음 내리기',
          button: true,
          child: IconButton(
            icon: const Icon(Icons.remove),
            tooltip: '키 한 음 내리기',
            onPressed: pitchSemitones <= minPitchSemitones
                ? null
                : () => onAdjust(-1),
            constraints: const BoxConstraints(
              minWidth: AppConstants.minTouchTarget,
              minHeight: AppConstants.minTouchTarget,
            ),
          ),
        ),
        SizedBox(
          width: 92,
          child: Semantics(
            label: '$slotLabel 재생 키 ${formatKeyLabel(pitchSemitones)}',
            child: Text(
              formatKeyLabel(pitchSemitones),
              textAlign: TextAlign.center,
              style: AppTypography.mono,
            ),
          ),
        ),
        Semantics(
          label: '$slotLabel 키 한 음 올리기',
          button: true,
          child: IconButton(
            icon: const Icon(Icons.add),
            tooltip: '키 한 음 올리기',
            onPressed: pitchSemitones >= maxPitchSemitones
                ? null
                : () => onAdjust(1),
            constraints: const BoxConstraints(
              minWidth: AppConstants.minTouchTarget,
              minHeight: AppConstants.minTouchTarget,
            ),
          ),
        ),
        if (showEffective) ...[
          const SizedBox(width: 10),
          Semantics(
            label: sounding != null
                ? '실제 들리는 조성 ${sounding.label}, 원곡 대비 '
                      '${formatKeyLabel(effective)}'
                : '원곡 대비 ${formatKeyLabel(effective)}',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.tertiary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                sounding != null
                    ? '실효 ${sounding.label} (${formatKeyShort(effective)})'
                    : '실효 ${formatKeyShort(effective)}',
                style: AppTypography.mono.copyWith(color: AppColors.tertiary),
              ),
            ),
          ),
        ],
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '이 반주에만 적용 — 파일은 그대로, 재생할 때 변환',
            style: AppTypography.bodyMuted,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

void _showDialogSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
