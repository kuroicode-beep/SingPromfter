// file: lib/dialogs/pitch_report_dialog.dart
//
// 녹음 채점 결과 — 점수 두 개와 "틀린 곳" 목록.
// 색이 아니라 글자로 말한다: "01:23 · 음정 반음쯤 낮게 (−78센트) · 박자 0.3초 늦게".
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../services/pitch_coach_client.dart';
import '../theme/app_theme.dart';

class PitchReportDialog {
  PitchReportDialog._();

  static Future<void> show(
    BuildContext context, {
    required String songTitle,
    required PitchAnalysis analysis,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => _PitchReportBody(
        songTitle: songTitle,
        analysis: analysis,
      ),
    );
  }
}

class _PitchReportBody extends StatelessWidget {
  final String songTitle;
  final PitchAnalysis analysis;

  const _PitchReportBody({required this.songTitle, required this.analysis});

  @override
  Widget build(BuildContext context) {
    final summary = analysis.summary;
    final problems = analysis.problems;
    return AlertDialog(
      title: Text('$songTitle — 채점 결과'),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _ScoreTile(label: '음정', score: summary.pitchScore),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ScoreTile(label: '박자', score: summary.timingScore),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '음표 ${summary.totalNotes}개 중 ${summary.sungNotes}개를 불렀습니다.'
              '${summary.medianTimingMs.abs() >= 100 ? ' 전체적으로 '
                  '${(summary.medianTimingMs.abs() / 1000).toStringAsFixed(1)}초 '
                  '${summary.medianTimingMs > 0 ? '늦는' : '빠른'} 편입니다.' : ''}',
              style: AppTypography.bodyMuted,
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text(
              problems.isEmpty ? '틀린 곳 없음' : '틀린 곳 ${problems.length}군데',
              style: AppTypography.body,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: problems.isEmpty
                  ? Center(
                      child: Text(
                        '잘 불렀습니다! 표시할 만큼 틀린 음표가 없습니다.',
                        style: AppTypography.bodyMuted,
                      ),
                    )
                  : ListView.separated(
                      itemCount: problems.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final note = problems[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                note.positionLabel,
                                style: AppTypography.mono,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  note.describe(),
                                  style: AppTypography.body,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(
            minimumSize: const Size(96, AppConstants.minTouchTarget),
          ),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}

/// 점수 타일 — 숫자를 크게, 라벨을 글자로.
class _ScoreTile extends StatelessWidget {
  final String label;
  final double? score;

  const _ScoreTile({required this.label, required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: AppShapes.controlRadius,
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        children: [
          Text(label, style: AppTypography.bodyMuted),
          const SizedBox(height: 4),
          Text(
            score == null ? '—' : score!.round().toString(),
            style: AppTypography.mono.copyWith(fontSize: 34),
          ),
          Text('/ 100', style: AppTypography.monoMuted),
        ],
      ),
    );
  }
}
