// file: lib/widgets/training_session_card.dart
//
// 따라하기 세션 러너 카드 — 세션 중 트레이닝 패널 상단에 뜬다.
// 현재 스텝·대형 안내 텍스트·남은 시간·진행도와 제어 버튼(일시정지/이 단계
// 다시/건너뛰기/종료)을 보여 준다. 모달이 아니라서 곡 스텝 중 홈으로 가도
// 세션(음성 안내)은 계속된다.
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../theme/app_theme.dart';

/// 컨트롤러 상태를 패널에 전달하기 위한 불변 뷰.
class TrainingSessionView {
  final bool active;
  final bool finished;
  final bool paused;
  final String stepTitle;
  final String bigText;
  final Duration? remaining;
  final int stepIndex;
  final int stepCount;

  const TrainingSessionView({
    required this.active,
    required this.finished,
    required this.paused,
    required this.stepTitle,
    required this.bigText,
    required this.remaining,
    required this.stepIndex,
    required this.stepCount,
  });

  static const idle = TrainingSessionView(
    active: false,
    finished: false,
    paused: false,
    stepTitle: '',
    bigText: '',
    remaining: null,
    stepIndex: 0,
    stepCount: 0,
  );
}

class TrainingSessionCard extends StatelessWidget {
  final TrainingSessionView session;
  final VoidCallback onTogglePause;
  final VoidCallback onRestartStep;
  final VoidCallback onSkipStep;
  final VoidCallback onStop;

  const TrainingSessionCard({
    super.key,
    required this.session,
    required this.onTogglePause,
    required this.onRestartStep,
    required this.onSkipStep,
    required this.onStop,
  });

  static String _mmss(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final remaining = session.remaining;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.selectedSurface,
        borderRadius: AppShapes.panelRadius,
        border: Border.all(color: AppColors.primary, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                session.paused ? Icons.pause_circle : Icons.play_circle,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  session.paused
                      ? '따라하기 일시정지 — ${session.stepTitle}'
                      : '따라하기 — ${session.stepTitle}',
                  style: AppTypography.listTitle,
                ),
              ),
              if (session.stepCount > 0)
                Text(
                  '${session.stepIndex + 1}/${session.stepCount}단계',
                  style: AppTypography.mono,
                ),
            ],
          ),
          const SizedBox(height: 12),
          // 대형 안내 텍스트 — 저시력 접근성을 위해 크게.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  session.bigText.isEmpty ? '…' : session.bigText,
                  style: AppTypography.screenTitle.copyWith(fontSize: 28),
                ),
              ),
              if (remaining != null)
                Text(
                  _mmss(remaining),
                  style: AppTypography.mono.copyWith(fontSize: 26),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onTogglePause,
                icon: Icon(session.paused ? Icons.play_arrow : Icons.pause),
                label: Text(session.paused ? '재개 (Space)' : '일시정지 (Space)'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, AppConstants.minTouchTarget),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onRestartStep,
                icon: const Icon(Icons.replay),
                label: const Text('이 단계 다시 (Home)'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppConstants.minTouchTarget),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onSkipStep,
                icon: const Icon(Icons.skip_next),
                label: const Text('건너뛰기'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppConstants.minTouchTarget),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onStop,
                icon: const Icon(Icons.stop),
                label: const Text('종료'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppConstants.minTouchTarget),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
