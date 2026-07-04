// file: lib/widgets/mini_slider.dart
//
// +/- 보조 조작과 스크린 리더 라벨을 포함한 접근성 슬라이더.
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class MiniSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final double step;
  final String? semanticValue;
  final ValueChanged<double> onChanged;

  const MiniSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    this.step = 1,
    this.semanticValue,
    required this.onChanged,
  });

  double get _step => divisions != null ? (max - min) / divisions! : step;

  void _decrement() {
    onChanged((value - _step).clamp(min, max).toDouble());
  }

  void _increment() {
    onChanged((value + _step).clamp(min, max).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label 조절',
      value: semanticValue ?? value.toStringAsFixed(value % 1 == 0 ? 0 : 1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTypography.bodyMuted),
          Row(
            children: [
              StepButton(
                icon: Icons.remove,
                semanticsLabel: '$label 줄이기',
                onTap: _decrement,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 6,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 10,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16,
                    ),
                  ),
                  child: Slider(
                    min: min,
                    max: max,
                    divisions: divisions,
                    value: value.clamp(min, max).toDouble(),
                    semanticFormatterCallback: (_) =>
                        semanticValue ?? '$label ${value.toStringAsFixed(1)}',
                    onChanged: onChanged,
                  ),
                ),
              ),
              StepButton(
                icon: Icons.add,
                semanticsLabel: '$label 늘리기',
                onTap: _increment,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class StepButton extends StatelessWidget {
  final IconData icon;
  final String semanticsLabel;
  final VoidCallback onTap;

  const StepButton({
    super.key,
    required this.icon,
    required this.semanticsLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      button: true,
      enabled: true,
      child: SizedBox(
        width: 50,
        height: 50,
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, size: 22, color: AppColors.textPrimary),
          tooltip: semanticsLabel,
        ),
      ),
    );
  }
}
