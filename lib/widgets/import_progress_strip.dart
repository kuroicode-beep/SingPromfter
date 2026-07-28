// file: lib/widgets/import_progress_strip.dart
//
// 홈 상단의 가져오기 진행 표시. 곡 추가가 주 경로가 되면서, 진행 상황을
// 별도 탭까지 가지 않고 홈에서 바로 볼 수 있어야 한다.
// 진행 중 작업이 없고 실패 작업도 없으면 아무것도 그리지 않는다.
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../controllers/import_job_controller.dart';
import '../theme/app_theme.dart';

class ImportProgressStrip extends StatelessWidget {
  final List<ImportJob> jobs;
  final ValueChanged<String> onCancel;
  final ValueChanged<String> onRetry;
  final VoidCallback onOpenJobs;

  const ImportProgressStrip({
    super.key,
    required this.jobs,
    required this.onCancel,
    required this.onRetry,
    required this.onOpenJobs,
  });

  @override
  Widget build(BuildContext context) {
    final active = jobs
        .where((j) => !j.status.isFinished)
        .toList(growable: false);
    // 진행 중이 없어도 실패 작업은 재시도할 수 있게 남겨서 보여준다.
    final failed = jobs
        .where((j) => j.status == ImportJobStatus.failed)
        .toList(growable: false);
    if (active.isEmpty && failed.isEmpty) return const SizedBox.shrink();

    final job = active.isNotEmpty ? active.first : failed.first;
    final isFailed = job.status == ImportJobStatus.failed;
    final more = (active.isNotEmpty ? active.length : failed.length) - 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainer,
        border: Border(bottom: BorderSide(color: AppColors.outline)),
      ),
      child: Semantics(
        label:
            '${job.displayName} ${isFailed ? '가져오기 실패' : '가져오는 중'}, '
            '${job.statusDetail ?? job.status.label}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  isFailed ? Icons.error_outline : Icons.downloading,
                  size: 20,
                  color: isFailed ? AppColors.danger : AppColors.primary,
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
                if (isFailed)
                  TextButton(
                    onPressed: () => onRetry(job.id),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(88, AppConstants.minTouchTarget),
                    ),
                    child: const Text('다시 시도'),
                  )
                else
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
              value: isFailed ? 0 : job.ratio,
              minHeight: 6,
              backgroundColor: AppColors.elevated,
              color: isFailed ? AppColors.danger : AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}
