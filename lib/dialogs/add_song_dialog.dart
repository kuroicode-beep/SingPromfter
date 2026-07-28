// file: lib/dialogs/add_song_dialog.dart
//
// 곡 추가의 유일한 경로. 유튜브 링크를 붙여넣으면 내려받기 → (필요시) 보컬 분리 →
// 가사 자동 부착 → 목록 등록까지 한 번에 처리한다.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_constants.dart';
import '../models/import_plan.dart';
import '../models/mr_source_mode.dart';
import '../services/youtube_import_service.dart';
import '../utils/key_label.dart';
import '../theme/app_theme.dart';

/// 링크로 가져오기. 곡 추가는 링크 경로 하나로만 들어온다.
class AddSongFromUrl {
  final String url;
  final MrSourceMode mode;
  final bool fetchLyrics;

  /// 이 링크로 만들 반주 구성(원곡·MR·키조절).
  final ImportPlan plan;

  const AddSongFromUrl({
    required this.url,
    required this.mode,
    required this.fetchLyrics,
    this.plan = const ImportPlan.single(),
  });
}

class AddSongDialog extends StatefulWidget {
  final bool toolAvailable;
  final String? toolMissingReason;
  final String separatorStatusLabel;
  final bool separatorOnline;

  const AddSongDialog({
    super.key,
    required this.toolAvailable,
    required this.toolMissingReason,
    required this.separatorStatusLabel,
    required this.separatorOnline,
  });

  static Future<AddSongFromUrl?> show(
    BuildContext context, {
    required bool toolAvailable,
    required String? toolMissingReason,
    required String separatorStatusLabel,
    required bool separatorOnline,
  }) {
    return showDialog<AddSongFromUrl>(
      context: context,
      builder: (_) => AddSongDialog(
        toolAvailable: toolAvailable,
        toolMissingReason: toolMissingReason,
        separatorStatusLabel: separatorStatusLabel,
        separatorOnline: separatorOnline,
      ),
    );
  }

  @override
  State<AddSongDialog> createState() => _AddSongDialogState();
}

class _AddSongDialogState extends State<AddSongDialog> {
  final _controller = TextEditingController();
  MrSourceMode _mode = MrSourceMode.aiSeparate;
  bool _fetchLyrics = true;
  bool _makeOriginal = true;
  bool _makeInstrumental = true;
  bool _makePitch = true;
  int _pitchSemitones = -2;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pasteFromClipboard();
  }

  /// 링크를 복사해 온 직후일 때가 많아, 클립보드에 유튜브 주소가 있으면 미리 채운다.
  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (!mounted || text.isEmpty) return;
      if (!looksLikeYoutubeUrl(text)) return;
      if (_controller.text.isNotEmpty) return;
      setState(() => _controller.text = text);
    } catch (_) {
      // 클립보드 접근 실패는 무시한다 — 직접 붙여넣으면 된다.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _controller.text.trim();
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
      AddSongFromUrl(
        url: url,
        mode: _mode,
        fetchLyrics: _fetchLyrics,
        plan: ImportPlan(
          makeOriginal: _makeOriginal,
          makeInstrumental:
              _makeInstrumental && _mode == MrSourceMode.aiSeparate,
          pitchSemitones: _makePitch ? _pitchSemitones : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('곡 추가', style: AppTypography.screenTitle),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!widget.toolAvailable) ...[
                _WarnBox(
                  text:
                      widget.toolMissingReason ??
                      'yt-dlp를 찾을 수 없어 링크로 가져올 수 없습니다.',
                  color: AppColors.danger,
                ),
                const SizedBox(height: 12),
              ],
              Text('유튜브 링크', style: AppTypography.bodyMuted),
              const SizedBox(height: 6),
              TextField(
                controller: _controller,
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
              const SizedBox(height: 6),
              Text(
                '반주(MR) 영상을 링크하면 음질이 가장 좋습니다.',
                style: AppTypography.bodyMuted,
              ),
              const SizedBox(height: 16),
              Text('반주 처리', style: AppTypography.bodyMuted),
              const SizedBox(height: 6),
              ...MrSourceMode.values.map(
                (mode) => _ModeTile(
                  mode: mode,
                  selected: _mode == mode,
                  onTap: () => setState(() => _mode = mode),
                ),
              ),
              if (_mode == MrSourceMode.aiSeparate) ...[
                const SizedBox(height: 4),
                Text(
                  widget.separatorStatusLabel,
                  style: AppTypography.bodyMuted,
                ),
                if (!widget.separatorOnline) ...[
                  const SizedBox(height: 6),
                  _WarnBox(
                    text: 'SAW에서 보컬 분리 서버를 먼저 켜 주세요.',
                    color: AppColors.tertiary,
                  ),
                ],
              ],
              const SizedBox(height: 16),
              Text('이 링크로 만들 반주', style: AppTypography.bodyMuted),
              const SizedBox(height: 6),
              _CheckRow(
                label: '원곡 그대로 (가이드 보컬 포함)',
                description: '슬롯 1',
                checked: _makeOriginal,
                onTap: () => setState(() => _makeOriginal = !_makeOriginal),
              ),
              _CheckRow(
                label: 'MR (AI 보컬 분리)',
                description: _mode == MrSourceMode.aiSeparate
                    ? '슬롯 2'
                    : "반주 처리에서 'AI 보컬 분리'를 골라야 만들 수 있습니다",
                checked:
                    _makeInstrumental && _mode == MrSourceMode.aiSeparate,
                enabled: _mode == MrSourceMode.aiSeparate,
                onTap: () =>
                    setState(() => _makeInstrumental = !_makeInstrumental),
              ),
              _CheckRow(
                label: '키조절본 (MR 기준)',
                description: '슬롯 3 · ${formatKeyLabel(_pitchSemitones)}',
                checked: _makePitch,
                onTap: () => setState(() => _makePitch = !_makePitch),
              ),
              if (_makePitch)
                Padding(
                  padding: const EdgeInsets.only(left: 36, top: 2),
                  child: Row(
                    children: [
                      _StepButton(
                        icon: Icons.remove,
                        tooltip: '키 낮추기',
                        onTap: _pitchSemitones <= -6
                            ? null
                            : () => setState(() => _pitchSemitones -= 1),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          formatKeyLabel(_pitchSemitones),
                          style: AppTypography.mono,
                        ),
                      ),
                      _StepButton(
                        icon: Icons.add,
                        tooltip: '키 올리기',
                        onTap: _pitchSemitones >= 6
                            ? null
                            : () => setState(() => _pitchSemitones += 1),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Semantics(
                label: '가사 자동 가져오기',
                checked: _fetchLyrics,
                child: InkWell(
                  borderRadius: AppShapes.controlRadius,
                  onTap: () => setState(() => _fetchLyrics = !_fetchLyrics),
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: AppConstants.minTouchTarget,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        Icon(
                          _fetchLyrics
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          color: _fetchLyrics
                              ? AppColors.primary
                              : AppColors.textMuted,
                          size: 26,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '가사도 자동으로 찾아 붙이기 (싱크 가사)',
                            style: AppTypography.body,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
          icon: const Icon(Icons.playlist_add),
          label: const Text('가져와서 추가'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(160, AppConstants.minTouchTarget),
          ),
        ),
      ],
    );
  }
}

/// 반주 구성 선택용 체크 줄. 상태를 색만이 아니라 체크 아이콘으로도 알린다.
class _CheckRow extends StatelessWidget {
  final String label;
  final String description;
  final bool checked;
  final bool enabled;
  final VoidCallback onTap;

  const _CheckRow({
    required this.label,
    required this.description,
    required this.checked,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final on = checked && enabled;
    return Semantics(
      label: label,
      checked: on,
      enabled: enabled,
      child: InkWell(
        borderRadius: AppShapes.controlRadius,
        onTap: enabled ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppConstants.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              Icon(
                on ? Icons.check_box : Icons.check_box_outline_blank,
                color: !enabled
                    ? AppColors.textMuted
                    : (on ? AppColors.primary : AppColors.textMuted),
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: enabled
                          ? AppTypography.body
                          : AppTypography.bodyMuted,
                    ),
                    Text(description, style: AppTypography.caption),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _StepButton({required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(
              AppConstants.minTouchTarget,
              AppConstants.minTouchTarget,
            ),
            padding: EdgeInsets.zero,
          ),
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }
}

class _WarnBox extends StatelessWidget {
  final String text;
  final Color color;

  const _WarnBox({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: AppShapes.controlRadius,
        border: Border.all(color: color, width: 2),
      ),
      child: Text(text, style: AppTypography.body),
    );
  }
}

class _ModeTile extends StatelessWidget {
  final MrSourceMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _ModeTile({
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
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: InkWell(
          borderRadius: AppShapes.controlRadius,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppConstants.minTouchTarget,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.selectedSurface : AppColors.elevated,
              borderRadius: AppShapes.controlRadius,
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.borderStrong,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected ? AppColors.primary : AppColors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(mode.label, style: AppTypography.body),
                      const SizedBox(height: 2),
                      Text(mode.description, style: AppTypography.bodyMuted),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
