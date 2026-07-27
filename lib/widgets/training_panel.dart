// file: lib/widgets/training_panel.dart
//
// 트레이닝 센터 — 오늘의 루틴 체크 + 연습 통계.
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/practice_session.dart';
import '../models/vocal_routine.dart';
import '../theme/app_theme.dart';
import '../utils/key_label.dart';

class TrainingPanel extends StatelessWidget {
  final DailyGoalLog todayLog;
  final int streak;
  final int completedThisWeek;
  final List<PracticeSummary> summaries;
  final ValueChanged<String> onRoutineChanged;
  final ValueChanged<String> onToggleStep;

  const TrainingPanel({
    super.key,
    required this.todayLog,
    required this.streak,
    required this.completedThisWeek,
    required this.summaries,
    required this.onRoutineChanged,
    required this.onToggleStep,
  });

  static String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours > 0) return '$hours시간 $minutes분';
    if (minutes > 0) return '$minutes분';
    return '${d.inSeconds}초';
  }

  @override
  Widget build(BuildContext context) {
    final routine = VocalRoutines.byId(todayLog.routineId);
    final done = routine.steps.where((s) => todayLog.isDone(s.id)).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text('트레이닝', style: AppTypography.screenTitle),
        const SizedBox(height: 12),
        _SummaryCard(
          streak: streak,
          completedThisWeek: completedThisWeek,
          doneSteps: done,
          totalSteps: routine.steps.length,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Text('오늘의 루틴', style: AppTypography.listTitle),
            const Spacer(),
            Text('${routine.totalMinutes}분', style: AppTypography.mono),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: VocalRoutines.all.map((r) {
            final selected = r.id == routine.id;
            return Semantics(
              button: true,
              selected: selected,
              label: r.name,
              child: FilterChip(
                label: Text(r.name, style: AppTypography.body),
                selected: selected,
                showCheckmark: true,
                onSelected: (_) => onRoutineChanged(r.id),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                visualDensity: VisualDensity.standard,
              ),
            );
          }).toList(growable: false),
        ),
        const SizedBox(height: 12),
        ...routine.steps.map(
          (step) => _StepRow(
            step: step,
            done: todayLog.isDone(step.id),
            onToggle: () => onToggleStep(step.id),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '루틴곡·목표곡은 실제로 그 곡을 30초 이상 연습하면 자동으로 체크됩니다.',
          style: AppTypography.bodyMuted,
        ),
        const SizedBox(height: 28),
        Text('연습 통계', style: AppTypography.listTitle),
        const SizedBox(height: 8),
        if (summaries.isEmpty)
          Text('아직 연습 기록이 없습니다.', style: AppTypography.bodyMuted)
        else
          ...summaries.map(
            (s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Semantics(
                label:
                    '${s.songTitle}, ${s.sessionCount}회, '
                    '${_formatDuration(s.totalDuration)}, '
                    '${formatKeyLabel(s.dominantPitchSemitones)}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.songTitle,
                      style: AppTypography.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${s.sessionCount}회 · '
                      '${_formatDuration(s.totalDuration)} · '
                      '${formatKeyLabel(s.dominantPitchSemitones)}',
                      style: AppTypography.monoMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int streak;
  final int completedThisWeek;
  final int doneSteps;
  final int totalSteps;

  const _SummaryCard({
    required this.streak,
    required this.completedThisWeek,
    required this.doneSteps,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppShapes.panel(),
      child: Row(
        children: [
          _Metric(label: '연속 달성', value: '$streak일'),
          const SizedBox(width: 24),
          _Metric(label: '최근 7일', value: '$completedThisWeek일'),
          const SizedBox(width: 24),
          _Metric(label: '오늘 진행', value: '$doneSteps/$totalSteps'),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $value',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.bodyMuted),
          const SizedBox(height: 4),
          Text(value, style: AppTypography.mono.copyWith(fontSize: 20)),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final RoutineStep step;
  final bool done;
  final VoidCallback onToggle;

  const _StepRow({
    required this.step,
    required this.done,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      checked: done,
      label: '${step.title} ${done ? '완료' : '미완료'}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          borderRadius: AppShapes.controlRadius,
          onTap: onToggle,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppConstants.minTouchTarget,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: done ? AppColors.selectedSurface : AppColors.elevated,
              borderRadius: AppShapes.controlRadius,
              border: Border.all(
                color: done ? AppColors.primary : AppColors.borderStrong,
                width: 2,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  done ? Icons.check_box : Icons.check_box_outline_blank,
                  color: done ? AppColors.primary : AppColors.textMuted,
                  size: 26,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(step.title, style: AppTypography.body),
                          ),
                          // 색만이 아니라 글자로도 완료를 표시한다.
                          if (done)
                            Text('완료', style: AppTypography.emphasis),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(step.guide, style: AppTypography.bodyMuted),
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
