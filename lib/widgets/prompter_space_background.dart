// file: lib/widgets/prompter_space_background.dart
//
// 프롬프터 우주 배경 — 별밭(반짝임) + 성운 + 이따금 별똥별.
// 가사 가독성이 우선이라 전부 저채도·저알파로 그린다(별 최대 알파 0.55,
// 성운 0.09). 설정(spaceBackground)과 단축키 B로 켜고 끈다.
//
// 렌더 원칙은 EQ 미터와 동일:
// - setState 없이 CustomPaint repaint notifier로만 다시 그린다.
// - 시각 장식이므로 IgnorePointer + ExcludeSemantics.
// - 시스템 '움직임 줄이기'면 Ticker를 멈추고 정적인 별만 남긴다.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_theme.dart';

/// 별 하나의 불변 속성 — 시드 고정 난수로 만들어 프레임마다 재계산하지 않는다.
class SpaceStar {
  final double x; // 0..1 (폭 비율)
  final double y; // 0..1
  final double size; // px
  final double twinklePhase;
  final double twinkleSpeed;

  /// 0=백색, 1=청색, 2=앰버 — SVIL 팔레트 안의 세 톤만 쓴다.
  final int tone;

  const SpaceStar({
    required this.x,
    required this.y,
    required this.size,
    required this.twinklePhase,
    required this.twinkleSpeed,
    required this.tone,
  });
}

/// 별밭을 만든다. (순수 함수 — 테스트 대상)
List<SpaceStar> generateStars(int count, {int seed = 7}) {
  final rng = math.Random(seed);
  return List.generate(count, (_) {
    final toneRoll = rng.nextDouble();
    return SpaceStar(
      x: rng.nextDouble(),
      y: rng.nextDouble(),
      size: 0.6 + rng.nextDouble() * 1.4,
      twinklePhase: rng.nextDouble() * math.pi * 2,
      twinkleSpeed: 0.4 + rng.nextDouble() * 1.2,
      tone: toneRoll < 0.72 ? 0 : (toneRoll < 0.94 ? 1 : 2),
    );
  });
}

class PrompterSpaceBackground extends StatefulWidget {
  final bool enabled;

  const PrompterSpaceBackground({super.key, required this.enabled});

  @override
  State<PrompterSpaceBackground> createState() =>
      _PrompterSpaceBackgroundState();
}

class _PrompterSpaceBackgroundState extends State<PrompterSpaceBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  /// 경과 시간(초) — painter가 반짝임·표류·별똥별 위상을 전부 이걸로 만든다.
  final ValueNotifier<double> _time = ValueNotifier(0);
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      // 33ms 스로틀 — 배경 장식에 60fps를 쓰지 않는다(가사 렌더가 우선).
      final seconds = elapsed.inMilliseconds / 1000.0;
      if (seconds - _time.value >= 0.033) _time.value = seconds;
    });
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant PrompterSpaceBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _syncTicker();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced == _reducedMotion) return;
    _reducedMotion = reduced;
    _syncTicker();
  }

  void _syncTicker() {
    final needsTick = widget.enabled && !_reducedMotion;
    if (needsTick && !_ticker.isActive) {
      _ticker.start();
    } else if (!needsTick && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _SpacePainter(repaint: _time, static_: _reducedMotion),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _SpacePainter extends CustomPainter {
  final ValueNotifier<double> time;
  final bool static_;

  _SpacePainter({required ValueNotifier<double> repaint, this.static_ = false})
    : time = repaint,
      super(repaint: repaint);

  static final List<SpaceStar> _stars = generateStars(110);

  /// 별똥별 주기(초) — 한 주기 안에서 앞 0.9초만 날아간다.
  static const double _meteorPeriod = 11.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = static_ ? 0.0 : time.value;

    // (1) 성운 — 아주 옅은 방사 그라데이션 두 덩이가 천천히 표류한다.
    _nebula(
      canvas,
      size,
      center: Offset(
        size.width * (0.24 + 0.06 * math.sin(t * 0.05)),
        size.height * (0.30 + 0.05 * math.cos(t * 0.04)),
      ),
      radius: size.shortestSide * 0.55,
      color: AppColors.primary,
      alpha: 0.085,
    );
    _nebula(
      canvas,
      size,
      center: Offset(
        size.width * (0.78 - 0.05 * math.cos(t * 0.037)),
        size.height * (0.68 + 0.06 * math.sin(t * 0.045)),
      ),
      radius: size.shortestSide * 0.48,
      color: AppColors.accentStrong,
      alpha: 0.06,
    );

    // (2) 별 — 사인 반짝임. 화면을 아주 느리게 흘러(표류) 살아있게 한다.
    final drift = static_ ? 0.0 : t * 0.004;
    for (final star in _stars) {
      final twinkle = static_
          ? 0.55
          : 0.35 + 0.65 * (1 + math.sin(star.twinklePhase + t * star.twinkleSpeed)) / 2;
      final alpha = 0.55 * twinkle * (0.4 + 0.6 * (star.size / 2.0));
      final color = switch (star.tone) {
        1 => AppColors.accentStrong,
        2 => AppColors.tertiary,
        _ => Colors.white,
      };
      final x = ((star.x + drift) % 1.0) * size.width;
      final y = star.y * size.height;
      canvas.drawCircle(
        Offset(x, y),
        star.size,
        Paint()..color = color.withValues(alpha: alpha.clamp(0.0, 0.55)),
      );
    }

    // (3) 별똥별 — 주기의 앞 0.9초 동안 대각선으로 스친다. 정적 모드는 생략.
    if (!static_) {
      final cycle = t % _meteorPeriod;
      if (cycle < 0.9) {
        final progress = cycle / 0.9;
        // 주기 번호로 시작점을 바꿔 매번 다른 곳에서 떨어진다.
        final n = (t ~/ _meteorPeriod);
        final rng = math.Random(n * 31 + 5);
        final sx = size.width * (0.15 + 0.7 * rng.nextDouble());
        final sy = size.height * (0.05 + 0.25 * rng.nextDouble());
        final head = Offset(
          sx + size.width * 0.22 * progress,
          sy + size.height * 0.18 * progress,
        );
        final tail = head - Offset(size.width * 0.05, size.height * 0.04);
        final fade = (1 - progress) * 0.5;
        canvas.drawLine(
          tail,
          head,
          Paint()
            ..shader = LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: fade),
              ],
            ).createShader(Rect.fromPoints(tail, head))
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  void _nebula(
    Canvas canvas,
    Size size, {
    required Offset center,
    required double radius,
    required Color color,
    required double alpha,
  }) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: Alignment(
            (center.dx / size.width) * 2 - 1,
            (center.dy / size.height) * 2 - 1,
          ),
          radius: radius / size.shortestSide,
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }

  @override
  bool shouldRepaint(covariant _SpacePainter oldDelegate) =>
      oldDelegate.static_ != static_;
}
