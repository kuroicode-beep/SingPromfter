// file: lib/dialogs/add_track_dialog.dart
//
// 이미 등록된 곡에 반주를 하나 더 붙인다. 노래방 버전처럼 별도 링크로만
// 구할 수 있는 반주를 위한 경로다.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_constants.dart';
import '../models/backing_track.dart';
import '../models/mr_source_mode.dart';
import '../models/song.dart';
import '../models/track_variant.dart';
import '../services/youtube_import_service.dart';
import '../theme/app_theme.dart';

class AddTrackFromUrl {
  final String songId;
  final int slot;
  final String url;
  final MrSourceMode mode;
  final String label;

  const AddTrackFromUrl({
    required this.songId,
    required this.slot,
    required this.url,
    required this.mode,
    required this.label,
  });
}

class AddTrackDialog extends StatefulWidget {
  final Song song;
  final bool toolAvailable;
  final String? toolMissingReason;
  final String separatorStatusLabel;
  final bool separatorOnline;

  const AddTrackDialog({
    super.key,
    required this.song,
    required this.toolAvailable,
    required this.toolMissingReason,
    required this.separatorStatusLabel,
    required this.separatorOnline,
  });

  static Future<AddTrackFromUrl?> show(
    BuildContext context, {
    required Song song,
    required bool toolAvailable,
    required String? toolMissingReason,
    required String separatorStatusLabel,
    required bool separatorOnline,
  }) {
    return showDialog<AddTrackFromUrl>(
      context: context,
      builder: (_) => AddTrackDialog(
        song: song,
        toolAvailable: toolAvailable,
        toolMissingReason: toolMissingReason,
        separatorStatusLabel: separatorStatusLabel,
        separatorOnline: separatorOnline,
      ),
    );
  }

  @override
  State<AddTrackDialog> createState() => _AddTrackDialogState();
}

class _AddTrackDialogState extends State<AddTrackDialog> {
  final _urlController = TextEditingController();
  late final TextEditingController _labelController = TextEditingController(
    text: TrackVariant.karaoke.label,
  );
  late int _slot = _firstFreeSlot();
  MrSourceMode _mode = MrSourceMode.asIs;
  String? _error;

  int _firstFreeSlot() {
    final used = widget.song.availableTrackSlots.toSet();
    for (final slot in AppConstants.backingTrackSlots) {
      if (!used.contains(slot)) return slot;
    }
    return AppConstants.maxBackingTrackSlots;
  }

  bool get _allFull =>
      widget.song.availableTrackSlots.length >=
      AppConstants.maxBackingTrackSlots;

  @override
  void initState() {
    super.initState();
    _pasteFromClipboard();
  }

  /// 링크를 복사해 온 직후일 때가 많아 클립보드를 미리 확인한다.
  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (!mounted || text.isEmpty) return;
      if (!looksLikeYoutubeUrl(text)) return;
      if (_urlController.text.isNotEmpty) return;
      setState(() => _urlController.text = text);
    } catch (_) {
      // 클립보드 접근 실패는 무시한다.
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = '유튜브 링크를 붙여넣어 주세요.');
      return;
    }
    if (!looksLikeYoutubeUrl(url)) {
      setState(() => _error = '유튜브 주소가 아닙니다. 링크를 다시 확인해 주세요.');
      return;
    }
    Navigator.pop(
      context,
      AddTrackFromUrl(
        songId: widget.song.id,
        slot: _slot,
        url: url,
        mode: _mode,
        label: _labelController.text.trim().isEmpty
            ? TrackVariant.karaoke.label
            : _labelController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('반주 추가', style: AppTypography.screenTitle),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 어느 곡에 붙이는지 먼저 못박는다(오조작 방지).
              Text(
                '${widget.song.title} · ${widget.song.artist}',
                style: AppTypography.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              if (!widget.toolAvailable) ...[
                _Warn(
                  text:
                      widget.toolMissingReason ??
                      'yt-dlp를 찾을 수 없어 링크로 가져올 수 없습니다.',
                  color: AppColors.danger,
                ),
                const SizedBox(height: 12),
              ],
              if (_allFull) ...[
                const _Warn(
                  text: '반주 슬롯이 모두 찼습니다. 덮어쓸 슬롯을 골라 주세요.',
                  color: AppColors.tertiary,
                ),
                const SizedBox(height: 12),
              ],
              Text('유튜브 링크', style: AppTypography.bodyMuted),
              const SizedBox(height: 6),
              TextField(
                controller: _urlController,
                autofocus: true,
                enabled: widget.toolAvailable,
                style: AppTypography.body,
                onSubmitted: (_) => _submit(),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  hintText: 'https://www.youtube.com/watch?v=...',
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 14),
              Text('넣을 슬롯', style: AppTypography.bodyMuted),
              const SizedBox(height: 6),
              for (final slot in AppConstants.backingTrackSlots)
                _SlotRow(
                  slot: slot,
                  existing: widget.song.trackForSlot(slot),
                  selected: _slot == slot,
                  onTap: () => setState(() => _slot = slot),
                ),
              const SizedBox(height: 14),
              Text('반주 이름', style: AppTypography.bodyMuted),
              const SizedBox(height: 6),
              TextField(
                controller: _labelController,
                style: AppTypography.body,
                decoration: const InputDecoration(hintText: '노래방'),
              ),
              const SizedBox(height: 14),
              Text('반주 처리', style: AppTypography.bodyMuted),
              const SizedBox(height: 6),
              for (final mode in MrSourceMode.values)
                _ModeRow(
                  mode: mode,
                  selected: _mode == mode,
                  onTap: () => setState(() => _mode = mode),
                ),
              if (_mode == MrSourceMode.aiSeparate) ...[
                const SizedBox(height: 4),
                Text(
                  widget.separatorStatusLabel,
                  style: AppTypography.bodyMuted,
                ),
                if (!widget.separatorOnline) ...[
                  const SizedBox(height: 6),
                  const _Warn(
                    text: 'SAW에서 보컬 분리 서버를 먼저 켜 주세요.',
                    color: AppColors.tertiary,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            minimumSize: const Size(88, AppConstants.minTouchTarget),
          ),
          child: const Text('취소'),
        ),
        FilledButton.icon(
          onPressed: widget.toolAvailable ? _submit : null,
          icon: const Icon(Icons.library_add),
          label: const Text('반주 가져오기'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(160, AppConstants.minTouchTarget),
          ),
        ),
      ],
    );
  }
}

class _SlotRow extends StatelessWidget {
  final int slot;
  final BackingTrack? existing;
  final bool selected;
  final VoidCallback onTap;

  const _SlotRow({
    required this.slot,
    required this.existing,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final track = existing;
    final label = track == null
        ? '슬롯 $slot — 비어 있음'
        : '슬롯 $slot — ${track.label} (사용 중, 덮어씀)';
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: AppShapes.controlRadius,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppConstants.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 20,
                color: selected ? AppColors.primary : AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: AppTypography.body)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  final MrSourceMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _ModeRow({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: mode.label,
      child: InkWell(
        borderRadius: AppShapes.controlRadius,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppConstants.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 20,
                color: selected ? AppColors.primary : AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(mode.label, style: AppTypography.body)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Warn extends StatelessWidget {
  final String text;
  final Color color;

  const _Warn({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: AppShapes.controlRadius,
        border: Border.all(color: color, width: 2),
      ),
      child: Text(text, style: AppTypography.body),
    );
  }
}
