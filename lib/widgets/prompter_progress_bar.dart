// file: lib/widgets/prompter_progress_bar.dart
//
// 재생 위치/전체 길이 진행률 바와 시간 텍스트.
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

String formatPrompterDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

class PrompterProgressBar extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final bool enabled;
  final ValueChanged<Duration> onSeek;
  final Color activeColor;
  final Color labelColor;

  const PrompterProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.enabled,
    required this.onSeek,
    this.activeColor = AppColors.primary,
    this.labelColor = AppColors.onSurfaceVariant,
  });

  @override
  Widget build(BuildContext context) {
    final maxMs = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final value =
        position.inMilliseconds.toDouble().clamp(0.0, maxMs.toDouble());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 6,
                activeTrackColor: activeColor,
                inactiveTrackColor: AppColors.outline,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                min: 0,
                max: maxMs.toDouble(),
                value: value.toDouble(),
                onChanged: enabled
                    ? (v) => onSeek(Duration(milliseconds: v.round()))
                    : null,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatPrompterDuration(position),
                style: AppTypography.mono.copyWith(color: labelColor),
              ),
              Text(
                formatPrompterDuration(duration),
                style: AppTypography.mono.copyWith(color: labelColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
