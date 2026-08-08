// file: lib/widgets/training_panel.dart
//
// 트레이닝 센터 — 4주 코스 + 오늘의 루틴 카드 + 달성률 + 연습 통계.
// 구조는 널리 통용되는 발성 교육 순서와 "주차 테마 + 매일 짧게" 커리큘럼
// 형식을 참고했다(2026-08-01 리서치, 특정 유료 프로그램 복제 아님).
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/practice_session.dart';
import '../models/vocal_course.dart';
import '../models/vocal_routine.dart';
import '../theme/app_theme.dart';
import '../utils/key_label.dart';
import 'training_session_card.dart';

class TrainingPanel extends StatelessWidget {
  final DailyGoalLog todayLog;
  final int streak;
  final int completedThisWeek;
  final List<PracticeSummary> summaries;
  final ValueChanged<String> onRoutineChanged;
  final ValueChanged<String> onToggleStep;

  /// 전체 일일 기록 — 주간/월간 달성률과 요일 점 계산용.
  final Map<String, DailyGoalLog> goalLogs;

  /// 4주 코스 시작일(yyyy-MM-dd). null이면 코스 미시작.
  final String? courseStart;
  final VoidCallback onStartCourse;

  /// 따라하기 세션 상태와 제어(음성 안내 자동 진행).
  final TrainingSessionView session;
  final VoidCallback onStartSession;
  final VoidCallback onTogglePauseSession;
  final VoidCallback onRestartSessionStep;
  final VoidCallback onSkipSessionStep;
  final VoidCallback onStopSession;

  const TrainingPanel({
    super.key,
    required this.todayLog,
    required this.streak,
    required this.completedThisWeek,
    required this.summaries,
    required this.onRoutineChanged,
    required this.onToggleStep,
    this.goalLogs = const {},
    this.courseStart,
    required this.onStartCourse,
    this.session = TrainingSessionView.idle,
    required this.onStartSession,
    required this.onTogglePauseSession,
    required this.onRestartSessionStep,
    required this.onSkipSessionStep,
    required this.onStopSession,
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
    final now = DateTime.now();
    final start = DateTime.tryParse(courseStart ?? '');
    final week = start == null ? null : VocalCourse.weekFor(start, now);
    final cycle = start == null ? 1 : VocalCourse.cycleFor(start, now);
    final weekDone = completedDaysThisWeek(logs: goalLogs, today: now);
    final monthDone = completedDaysThisMonth(logs: goalLogs, today: now);
    final dots = weekCompletionDots(logs: goalLogs, today: now);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text('트레이닝', style: AppTypography.screenTitle),
        const SizedBox(height: 12),
        if (session.active) ...[
          TrainingSessionCard(
            session: session,
            onTogglePause: onTogglePauseSession,
            onRestartStep: onRestartSessionStep,
            onSkipStep: onSkipSessionStep,
            onStop: onStopSession,
          ),
          const SizedBox(height: 12),
        ],
        if (week == null)
          _CourseStartCard(onStart: onStartCourse)
        else
          _CourseCard(
            week: week,
            cycle: cycle,
            weekDone: weekDone,
            dots: dots,
          ),
        const SizedBox(height: 12),
        _ProgressCard(
          todayRatio: routine.steps.isEmpty ? 0 : done / routine.steps.length,
          todayLabel: '$done/${routine.steps.length}단계',
          weekDone: weekDone,
          weekTarget: week?.targetDays ?? 4,
          monthDone: monthDone,
          streak: streak,
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
        if (!session.active)
          FilledButton.icon(
            onPressed: onStartSession,
            icon: const Icon(Icons.record_voice_over),
            label: Text('따라하기 시작 (${routine.totalMinutes}분, 음성 안내)'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(240, AppConstants.minTouchTarget),
            ),
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
                // 세션 중 루틴 교체는 진행과 어긋난다 — 종료 후에.
                onSelected:
                    session.active ? null : (_) => onRoutineChanged(r.id),
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

/// 코스 미시작 상태 — 시작 버튼 하나만 크게.
class _CourseStartCard extends StatelessWidget {
  final VoidCallback onStart;

  const _CourseStartCard({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppShapes.panel(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('4주 보컬 코스', style: AppTypography.listTitle),
          const SizedBox(height: 6),
          Text(
            '호흡과 지지 → 음정과 음역 → 딕션과 리듬 → 곡 완성. '
            '한 주에 하나씩, 매일 짧게 쌓는 코스예요. 4주를 마치면 '
            '다음 회차로 이어집니다.',
            style: AppTypography.bodyMuted.copyWith(height: 1.5),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.flag),
            label: const Text('오늘부터 코스 시작'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(200, AppConstants.minTouchTarget),
            ),
          ),
        ],
      ),
    );
  }
}

/// 이번 주 코스 카드 — 주차 테마·주간 목표·요일 점.
class _CourseCard extends StatelessWidget {
  final CourseWeek week;
  final int cycle;
  final int weekDone;
  final List<bool?> dots;

  const _CourseCard({
    required this.week,
    required this.cycle,
    required this.weekDone,
    required this.dots,
  });

  static const _dayNames = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    final met = weekDone >= week.targetDays;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppShapes.panel(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${week.number}주차',
                  style: AppTypography.emphasis,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(week.theme, style: AppTypography.listTitle),
              ),
              if (cycle > 1)
                Text('$cycle회차', style: AppTypography.monoMuted),
            ],
          ),
          const SizedBox(height: 8),
          Text(week.focus, style: AppTypography.body.copyWith(height: 1.5)),
          const SizedBox(height: 6),
          Text(
            '💡 ${week.tip}',
            style: AppTypography.bodyMuted.copyWith(height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '주간 목표 $weekDone/${week.targetDays}일',
                style: AppTypography.body,
              ),
              if (met) ...[
                const SizedBox(width: 8),
                Text('달성!', style: AppTypography.emphasis),
              ],
              const Spacer(),
              // 요일 점 — 완주 ● / 미완주 ○ / 미래는 빈칸. 색+글자 병행.
              for (var i = 0; i < 7; i++) ...[
                Semantics(
                  label:
                      '${_dayNames[i]}요일 ${dots[i] == null ? '예정' : dots[i]! ? '완주' : '미완주'}',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_dayNames[i], style: AppTypography.monoMuted),
                      const SizedBox(height: 2),
                      Icon(
                        dots[i] == true
                            ? Icons.circle
                            : Icons.circle_outlined,
                        size: 14,
                        color: dots[i] == true
                            ? AppColors.primary
                            : dots[i] == null
                                ? AppColors.border
                                : AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
                if (i < 6) const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 달성률 카드 — 오늘·이번 주·이번 달 + 연속.
class _ProgressCard extends StatelessWidget {
  final double todayRatio;
  final String todayLabel;
  final int weekDone;
  final int weekTarget;
  final int monthDone;
  final int streak;

  const _ProgressCard({
    required this.todayRatio,
    required this.todayLabel,
    required this.weekDone,
    required this.weekTarget,
    required this.monthDone,
    required this.streak,
  });

  @override
  Widget build(BuildContext context) {
    final weekRatio = weekTarget == 0
        ? 0.0
        : (weekDone / weekTarget).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppShapes.panel(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _ProgressMetric(
              label: '오늘',
              value: '${(todayRatio * 100).round()}%',
              detail: todayLabel,
              ratio: todayRatio,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _ProgressMetric(
              label: '이번 주',
              value: '${(weekRatio * 100).round()}%',
              detail: '$weekDone/$weekTarget일',
              ratio: weekRatio,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _ProgressMetric(
              label: '이번 달',
              value: '$monthDone일',
              detail: '연속 $streak일',
              ratio: null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressMetric extends StatelessWidget {
  final String label;
  final String value;
  final String detail;
  final double? ratio;

  const _ProgressMetric({
    required this.label,
    required this.value,
    required this.detail,
    required this.ratio,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $value, $detail',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.bodyMuted),
          const SizedBox(height: 4),
          Text(value, style: AppTypography.mono.copyWith(fontSize: 22)),
          const SizedBox(height: 2),
          Text(detail, style: AppTypography.monoMuted),
          if (ratio != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: AppColors.elevated,
                color: AppColors.primary,
              ),
            ),
          ],
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

  static IconData _kindIcon(RoutineStepKind kind) => switch (kind) {
    RoutineStepKind.breathing => Icons.air,
    RoutineStepKind.warmup => Icons.music_note,
    RoutineStepKind.scale => Icons.graphic_eq,
    RoutineStepKind.diction => Icons.record_voice_over,
    RoutineStepKind.routineSong => Icons.library_music,
    RoutineStepKind.targetSong => Icons.star,
    RoutineStepKind.cooldown => Icons.spa,
  };

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
                Icon(
                  _kindIcon(step.kind),
                  size: 22,
                  color: done ? AppColors.primary : AppColors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              step.kind.label,
                              style: AppTypography.body.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text('${step.minutes}분', style: AppTypography.mono),
                          // 색만이 아니라 글자로도 완료를 표시한다.
                          if (done) ...[
                            const SizedBox(width: 8),
                            Text('완료', style: AppTypography.emphasis),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        step.guide,
                        style: AppTypography.bodyMuted.copyWith(height: 1.4),
                      ),
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
