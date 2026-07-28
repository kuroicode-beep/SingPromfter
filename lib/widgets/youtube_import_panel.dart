// file: lib/widgets/youtube_import_panel.dart
//
// 유튜브 링크 가져오기 화면.
//
// 저작권 방침(소장님 확정 2026-07-28): 용도 제한과 책임 소재 문구를 상시 노출한다.
// 공개 배포 시 기능을 빼야 할 경우 이 화면과 진입점만 제거하면 되도록 격리해 둔다.
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../controllers/import_job_controller.dart';
import '../models/mr_source_mode.dart';
import '../theme/app_theme.dart';

class YoutubeImportPanel extends StatefulWidget {
  final List<ImportJob> jobs;
  final bool toolAvailable;
  final String? toolMissingReason;
  final void Function(String url, MrSourceMode mode) onSubmit;
  final ValueChanged<String> onCancelJob;
  final ValueChanged<String> onRetryJob;
  final VoidCallback onClearFinished;
  final VoidCallback onLocateTool;
  final String? toolVersion;
  final VoidCallback onUpdateTool;
  final String separatorStatusLabel;

  const YoutubeImportPanel({
    super.key,
    required this.jobs,
    required this.toolAvailable,
    required this.toolMissingReason,
    required this.onSubmit,
    required this.onCancelJob,
    required this.onRetryJob,
    required this.onClearFinished,
    required this.onLocateTool,
    this.toolVersion,
    required this.onUpdateTool,
    required this.separatorStatusLabel,
  });

  @override
  State<YoutubeImportPanel> createState() => _YoutubeImportPanelState();
}

class _YoutubeImportPanelState extends State<YoutubeImportPanel> {
  final _controller = TextEditingController();
  MrSourceMode _mode = MrSourceMode.asIs;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    widget.onSubmit(url, _mode);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text('가져오기 기록', style: AppTypography.screenTitle),
        const SizedBox(height: 6),
        Text(
          '곡 추가는 상단 [곡 추가] 버튼이 빠릅니다. 이 화면은 진행 상황과 기록을 봅니다.',
          style: AppTypography.bodyMuted,
        ),
        const SizedBox(height: 12),
        const _CopyrightNotice(),
        const SizedBox(height: 16),
        if (!widget.toolAvailable) ...[
          _ToolMissingCard(
            reason: widget.toolMissingReason ?? 'yt-dlp를 찾을 수 없습니다.',
            onLocate: widget.onLocateTool,
          ),
          const SizedBox(height: 16),
        ],
        if (widget.toolAvailable) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'yt-dlp ${widget.toolVersion ?? ''}',
                  style: AppTypography.monoMuted,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: widget.onUpdateTool,
                style: TextButton.styleFrom(
                  minimumSize: const Size(120, AppConstants.minTouchTarget),
                ),
                child: const Text('yt-dlp 업데이트'),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Text('영상 링크', style: AppTypography.bodyMuted),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          enabled: widget.toolAvailable,
          style: AppTypography.body,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            hintText: 'https://www.youtube.com/watch?v=...',
          ),
        ),
        const SizedBox(height: 16),
        Text('반주 처리 방식', style: AppTypography.bodyMuted),
        const SizedBox(height: 8),
        ...MrSourceMode.values.map(
          (mode) => _ModeOption(
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
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: widget.toolAvailable ? _submit : null,
          icon: const Icon(Icons.download),
          label: const Text('가져오기 시작'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(AppConstants.minTouchTarget),
          ),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Text('작업 목록', style: AppTypography.listTitle),
            const Spacer(),
            if (widget.jobs.any((j) => j.status.isFinished))
              TextButton(
                onPressed: widget.onClearFinished,
                style: TextButton.styleFrom(
                  minimumSize: const Size(72, AppConstants.minTouchTarget),
                ),
                child: const Text('완료 항목 지우기'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (widget.jobs.isEmpty)
          Text('아직 가져온 작업이 없습니다.', style: AppTypography.bodyMuted)
        else
          ...widget.jobs.map(
            (job) => _JobRow(
              job: job,
              onCancel: () => widget.onCancelJob(job.id),
              onRetry: () => widget.onRetryJob(job.id),
            ),
          ),
      ],
    );
  }
}

/// 용도 제한 + 책임 소재. 색이 아니라 텍스트로 분명히 드러낸다.
class _CopyrightNotice extends StatelessWidget {
  const _CopyrightNotice();

  static const String usageLimit = '개인이 저작권을 소유한 링크만 사용해야 합니다.';
  static const String responsibility = '개인적 용도의 사용에 대한 책임은 사용자 본인에게 있습니다.';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: AppShapes.controlRadius,
        border: Border.all(color: AppColors.tertiary, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: AppColors.tertiary),
              const SizedBox(width: 8),
              Text('사용 전 확인', style: AppTypography.body),
            ],
          ),
          const SizedBox(height: 8),
          Text(usageLimit, style: AppTypography.body),
          const SizedBox(height: 4),
          Text(responsibility, style: AppTypography.bodyMuted),
        ],
      ),
    );
  }
}

class _ToolMissingCard extends StatelessWidget {
  final String reason;
  final VoidCallback onLocate;

  const _ToolMissingCard({required this.reason, required this.onLocate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: AppShapes.controlRadius,
        border: Border.all(color: AppColors.danger, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('가져오기를 사용할 수 없음', style: AppTypography.body),
          const SizedBox(height: 6),
          Text(reason, style: AppTypography.bodyMuted),
          const SizedBox(height: 6),
          Text('설치: winget install yt-dlp', style: AppTypography.monoMuted),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: onLocate,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(160, AppConstants.minTouchTarget),
              side: const BorderSide(color: AppColors.borderStrong, width: 2),
            ),
            child: const Text('직접 경로 지정'),
          ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  final MrSourceMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _ModeOption({
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
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          borderRadius: AppShapes.controlRadius,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppConstants.minTouchTarget,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
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

class _JobRow extends StatelessWidget {
  final ImportJob job;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  const _JobRow({
    required this.job,
    required this.onCancel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = job.ratio;
    return Semantics(
      label: '${job.displayName}, ${job.status.label}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    job.displayName,
                    style: AppTypography.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // 상태는 색이 아니라 텍스트로 알린다.
                Text(job.status.label, style: AppTypography.monoMuted),
                if (!job.status.isFinished) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '작업 취소',
                    constraints: const BoxConstraints(
                      minWidth: AppConstants.minTouchTarget,
                      minHeight: AppConstants.minTouchTarget,
                    ),
                    onPressed: onCancel,
                  ),
                ] else if (job.status == ImportJobStatus.failed ||
                    job.status == ImportJobStatus.cancelled) ...[
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(
                      minimumSize:
                          const Size(88, AppConstants.minTouchTarget),
                    ),
                    child: const Text('다시 시도'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: AppColors.elevated,
              color: AppColors.primary,
            ),
            if (job.statusDetail != null) ...[
              const SizedBox(height: 6),
              Text(job.statusDetail!, style: AppTypography.bodyMuted),
            ],
          ],
        ),
      ),
    );
  }
}
