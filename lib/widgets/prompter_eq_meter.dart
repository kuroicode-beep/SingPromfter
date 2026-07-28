// file: lib/widgets/prompter_eq_meter.dart
//
// 전체화면 프롬프터 좌하단의 EQ 미터. 정적인 무대 화면에 살아있는 느낌을 준다.
//
// 렌더 원칙 (진행바와 같은 leaf 구독 철학):
// - setState를 쓰지 않는다 — CustomPaint의 repaint notifier로만 다시 그린다.
// - 자체 Ticker로 구동하고, 정지 상태에선 감쇠가 끝나면 Ticker를 멈춘다.
// - 시각 장식일 뿐이므로 IgnorePointer + ExcludeSemantics로 감싼다.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../controllers/playback_controller.dart';
import '../theme/app_theme.dart';

/// 스무딩 규칙: 어택은 즉시, 릴리즈는 프레임당 비율 감쇠. (순수 함수 — 테스트 대상)
double smoothLevel(double previous, double target, {double release = 0.08}) {
  if (target >= previous) return target;
  final next = previous - (previous - target) * release * 4;
  return next < target ? target : next;
}

/// 피크홀드 규칙: 새 값이 크면 갱신, 아니면 천천히 낙하. (순수 함수)
double holdPeak(double previousPeak, double current, {double fall = 0.012}) {
  if (current >= previousPeak) return current;
  final next = previousPeak - fall;
  return next < current ? current : next;
}

class _EqFrame {
  final List<double> bars; // 0..1
  final List<double> peaks; // 0..1
  const _EqFrame(this.bars, this.peaks);
}

class PrompterEqMeter extends StatefulWidget {
  final PlaybackController playback;

  const PrompterEqMeter({super.key, required this.playback});

  @override
  State<PrompterEqMeter> createState() => _PrompterEqMeterState();
}

class _PrompterEqMeterState extends State<PrompterEqMeter>
    with SingleTickerProviderStateMixin {
  static const int _fallbackBandCount = 6;

  late final Ticker _ticker;
  final ValueNotifier<_EqFrame> _frame = ValueNotifier(
    const _EqFrame([], []),
  );

  List<double> _bars = List.filled(_fallbackBandCount, 0);
  List<double> _peaks = List.filled(_fallbackBandCount, 0);
  double _pulsePhase = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    widget.playback.state.addListener(_syncTicker);
    widget.playback.trackLevels.addListener(_syncTicker);
    _syncTicker();
  }

  @override
  void dispose() {
    widget.playback.state.removeListener(_syncTicker);
    widget.playback.trackLevels.removeListener(_syncTicker);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  bool get _playing => widget.playback.state.value.playing;

  /// 재생 중이거나 막대가 아직 내려가는 중일 때만 Ticker를 돌린다.
  void _syncTicker() {
    final needsTick = _playing || _bars.any((b) => b > 0.005);
    if (needsTick && !_ticker.isActive) {
      _ticker.start();
    } else if (!needsTick && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final levels = widget.playback.trackLevels.value;
    final playing = _playing;

    List<double> targets;
    if (playing && levels != null && !levels.isEmpty) {
      final raw = levels.frameAt(widget.playback.position.value);
      targets = raw == null
          ? List.filled(levels.bandCount, 0.0)
          : raw.map((v) => v / 100).toList(growable: false);
    } else if (playing) {
      // 분석 전(또는 ffmpeg 부재) 폴백 — 위상이 다른 사인 펄스로 살아있게.
      _pulsePhase += 0.09;
      targets = List.generate(
        _fallbackBandCount,
        (i) => 0.25 + 0.2 * (1 + math.sin(_pulsePhase + i * 1.1)) / 2,
      );
    } else {
      targets = List.filled(_bars.length, 0.0);
    }

    if (targets.length != _bars.length) {
      _bars = List.filled(targets.length, 0);
      _peaks = List.filled(targets.length, 0);
    }

    var changed = false;
    for (var i = 0; i < targets.length; i++) {
      final nextBar = smoothLevel(_bars[i], targets[i]);
      final nextPeak = holdPeak(_peaks[i], nextBar);
      if ((nextBar - _bars[i]).abs() > 0.001 ||
          (nextPeak - _peaks[i]).abs() > 0.001) {
        changed = true;
      }
      _bars[i] = nextBar;
      _peaks[i] = nextPeak;
    }

    if (changed) {
      _frame.value = _EqFrame(
        List.unmodifiable(_bars),
        List.unmodifiable(_peaks),
      );
    }
    if (!playing) _syncTicker();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: SizedBox(
          width: 200,
          height: 72,
          child: CustomPaint(painter: _EqMeterPainter(repaint: _frame)),
        ),
      ),
    );
  }
}

class _EqMeterPainter extends CustomPainter {
  final ValueNotifier<_EqFrame> repaintNotifier;

  _EqMeterPainter({required ValueNotifier<_EqFrame> repaint})
    : repaintNotifier = repaint,
      super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final frame = repaintNotifier.value;
    final count = frame.bars.isEmpty ? 6 : frame.bars.length;
    const gap = 6.0;
    final barWidth = (size.width - gap * (count - 1)) / count;

    final trackPaint = Paint()..color = Colors.white.withValues(alpha: 0.06);
    final peakPaint = Paint()..color = AppColors.accentMax;

    for (var i = 0; i < count; i++) {
      final x = i * (barWidth + gap);
      final track = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, 0, barWidth, size.height),
        const Radius.circular(3),
      );
      canvas.drawRRect(track, trackPaint);

      final level = i < frame.bars.length ? frame.bars[i] : 0.0;
      if (level > 0.01) {
        final barHeight = size.height * level;
        final rect = Rect.fromLTWH(
          x,
          size.height - barHeight,
          barWidth,
          barHeight,
        );
        // 세로 그라데이션: 아래 primary → 위로 갈수록 accentMax → tertiary.
        final barPaint = Paint()
          ..shader = const LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              AppColors.primary,
              AppColors.accentMax,
              AppColors.tertiary,
            ],
            stops: [0.0, 0.7, 1.0],
          ).createShader(Rect.fromLTWH(x, 0, barWidth, size.height));
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          barPaint,
        );
      }

      final peak = i < frame.peaks.length ? frame.peaks[i] : 0.0;
      if (peak > 0.02) {
        final peakY = size.height * (1 - peak);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, peakY - 1.5, barWidth, 3),
            const Radius.circular(1.5),
          ),
          peakPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EqMeterPainter oldDelegate) => false;
}
