// file: lib/widgets/import_progress_strip.dart
//
// 홈 상단의 가져오기 진행 표시. 곡 추가가 주 경로가 되면서, 진행 상황을
// 별도 탭까지 가지 않고 홈에서 바로 볼 수 있어야 한다.
// 진행 중인 작업이 없으면 아무것도 그리지 않는다.
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../controllers/import_job_controller.dart';
import '../theme/app_theme.dart';

class ImportProgressStrip extends StatelessWidget {
  final List<ImportJob> jobs;
  final ValueChanged<String> onCancel;
  final VoidCallback onOpenJobs;

  const ImportProgressStrip({
    super.key,
    required this.jobs,
    required this.onCancel,
    required this.onOpenJobs,
  });

  @override
  Widget build(BuildContext context) {
    final active = jobs
        .where((j) => !j.status.isFinished)
        .toList(growable: false);
    if (active.isEmpty) return const SizedBox.shrink();

    final job = active.first;
    final more = active.length - 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainer,
        border: Border(bottom: BorderSide(color: AppColors.outline)),
      ),
      child: Semantics(
        label:
            '${job.displayName} 가져오는 중, '
            '${job.statusDetail ?? job.status.label}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.downloading,
                  size: 20,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    job.displayName,
                    style: AppTypography.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (more > 0) ...[
                  Text('외 $more건', style: AppTypography.monoMuted),
                  const SizedBox(width: 8),
                ],
                // 상태는 색이 아니라 글자로 알린다.
                Text(
                  job.statusDetail ?? job.status.label,
                  style: AppTypography.bodyMuted,
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: '가져오기 취소',
                  constraints: const BoxConstraints(
                    minWidth: AppConstants.minTouchTarget,
                    minHeight: 40,
                  ),
                  onPressed: () => onCancel(job.id),
                ),
                IconButton(
                  icon: const Icon(Icons.list_alt, size: 20),
                  tooltip: '가져오기 목록 보기',
                  constraints: const BoxConstraints(
                    minWidth: AppConstants.minTouchTarget,
                    minHeight: 40,
                  ),
                  onPressed: onOpenJobs,
                ),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: job.ratio,
              minHeight: 6,
              backgroundColor: AppColors.elevated,
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}
