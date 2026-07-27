// file: lib/widgets/prompter_progress_bar.dart
//
// 재생 위치/전체 길이 진행률 바와 시간 텍스트.
//
// 드래그 중에는 스트림 위치 대신 로컬 값을 표시한다 — 위치가 60Hz로
// 갱신되므로 그대로 두면 손잡이가 계속 제자리로 튕겨 조작이 불가능하다.
// 탐색은 손을 놓는 순간 한 번만 보낸다.
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

String formatPrompterDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

class PrompterProgressBar extends StatefulWidget {
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
  State<PrompterProgressBar> createState() => _PrompterProgressBarState();
}

class _PrompterProgressBarState extends State<PrompterProgressBar> {
  /// 드래그 중인 값(ms). null이면 스트림 위치를 그대로 쓴다.
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final maxMs = widget.duration.inMilliseconds.toDouble().clamp(
      1.0,
      double.infinity,
    );
    final streamMs = widget.position.inMilliseconds.toDouble().clamp(
      0.0,
      maxMs.toDouble(),
    );
    final shownMs = (_dragMs ?? streamMs).clamp(0.0, maxMs.toDouble());
    final shownPosition = Duration(milliseconds: shownMs.round());

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
                activeTrackColor: widget.activeColor,
                inactiveTrackColor: AppColors.outline,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                min: 0,
                max: maxMs.toDouble(),
                value: shownMs.toDouble(),
                onChangeStart: widget.enabled
                    ? (v) => setState(() => _dragMs = v)
                    : null,
                onChanged: widget.enabled
                    ? (v) => setState(() => _dragMs = v)
                    : null,
                onChangeEnd: widget.enabled
                    ? (v) {
                        setState(() => _dragMs = null);
                        widget.onSeek(Duration(milliseconds: v.round()));
                      }
                    : null,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatPrompterDuration(shownPosition),
                style: AppTypography.mono.copyWith(color: widget.labelColor),
              ),
              Text(
                formatPrompterDuration(widget.duration),
                style: AppTypography.mono.copyWith(color: widget.labelColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
