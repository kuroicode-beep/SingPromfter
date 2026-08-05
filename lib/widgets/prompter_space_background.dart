// file: lib/widgets/prompter_space_background.dart
//
// 프롬프터 우주 배경 — 2겹 별밭(원근 표류·반짝임·십자광) + 성운 3덩이 +
// 은하수 띠 + 별똥별. 가사 가독성이 우선이라 전부 저알파로 그린다.
// 설정(spaceBackground)과 단축키 B로 켜고 끈다.
//
// 시스템 '움직임 줄이기'는 따르지 않는다 — B 단축키가 있으니 사용자가 직접
// 끄는 것으로 정리(2026-08-05 사용자 지정).
//
// 렌더 원칙은 EQ 미터와 동일:
// - setState 없이 CustomPaint repaint notifier로만 다시 그린다.
// - 시각 장식이므로 IgnorePointer + ExcludeSemantics.
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
      twinkleSpeed: 0.4 + rng.nextDouble() * 1.6,
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

  void _syncTicker() {
    if (widget.enabled && !_ticker.isActive) {
      _ticker.start();
    } else if (!widget.enabled && _ticker.isActive) {
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
            painter: _SpacePainter(repaint: _time),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _SpacePainter extends CustomPainter {
  final ValueNotifier<double> time;

  _SpacePainter({required ValueNotifier<double> repaint})
    : time = repaint,
      super(repaint: repaint);

  /// 2겹 별밭 — 먼 층(작고 느림)·가까운 층(크고 빠름)으로 원근감을 낸다.
  static final List<SpaceStar> _farStars = generateStars(120, seed: 7);
  static final List<SpaceStar> _nearStars = generateStars(48, seed: 21);

  /// 별똥별 주기(초) — 한 주기 안에서 앞 1.1초만 날아간다.
  static const double _meteorPeriod = 6.5;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = time.value;

    // (1) 은하수 띠 — 대각선으로 아주 옅게 흐르는 빛무리.
    final bandShift = 0.06 * math.sin(t * 0.03);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(-1, -0.6 + bandShift),
          end: Alignment(1, 0.6 + bandShift),
          colors: [
            Colors.white.withValues(alpha: 0),
            AppColors.accentStrong.withValues(alpha: 0.045),
            Colors.white.withValues(alpha: 0.06),
            AppColors.primary.withValues(alpha: 0.045),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0.15, 0.38, 0.5, 0.62, 0.85],
        ).createShader(Offset.zero & size),
    );

    // (2) 성운 — 세 덩이가 천천히 표류하며 숨쉬듯 밝기가 오르내린다.
    final breathe = 0.75 + 0.25 * math.sin(t * 0.11);
    _nebula(
      canvas,
      size,
      center: Offset(
        size.width * (0.22 + 0.07 * math.sin(t * 0.05)),
        size.height * (0.28 + 0.06 * math.cos(t * 0.04)),
      ),
      radius: size.shortestSide * 0.58,
      color: AppColors.primary,
      alpha: 0.12 * breathe,
    );
    _nebula(
      canvas,
      size,
      center: Offset(
        size.width * (0.80 - 0.06 * math.cos(t * 0.037)),
        size.height * (0.66 + 0.07 * math.sin(t * 0.045)),
      ),
      radius: size.shortestSide * 0.52,
      color: AppColors.accentStrong,
      alpha: 0.10 * (1.5 - breathe * 0.5),
    );
    _nebula(
      canvas,
      size,
      center: Offset(
        size.width * (0.55 + 0.08 * math.sin(t * 0.028)),
        size.height * (0.12 + 0.04 * math.cos(t * 0.05)),
      ),
      radius: size.shortestSide * 0.38,
      color: AppColors.tertiary,
      alpha: 0.05,
    );

    // (3) 별 — 먼 층은 느리게, 가까운 층은 빠르게 흘러 원근감을 만든다.
    _drawStars(canvas, size, _farStars, t, drift: t * 0.003, scale: 0.8, maxAlpha: 0.45);
    _drawStars(canvas, size, _nearStars, t, drift: t * 0.009, scale: 1.35, maxAlpha: 0.62, cross: true);

    // (4) 별똥별 — 6.5초마다 대각선으로 스친다. 머리에 작은 광점.
    final cycle = t % _meteorPeriod;
    if (cycle < 1.1) {
      final progress = cycle / 1.1;
      final n = t ~/ _meteorPeriod;
      final rng = math.Random(n * 31 + 5);
      final sx = size.width * (0.10 + 0.75 * rng.nextDouble());
      final sy = size.height * (0.05 + 0.30 * rng.nextDouble());
      final head = Offset(
        sx + size.width * 0.26 * progress,
        sy + size.height * 0.20 * progress,
      );
      final tail = head - Offset(size.width * 0.08, size.height * 0.06);
      final fade = math.sin(progress * math.pi) * 0.7; // 스르륵 나타났다 사라짐
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
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round,
      );
      final headArea = Rect.fromCircle(center: head, radius: 7);
      canvas.drawCircle(
        head,
        7,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: fade * 0.9),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(headArea),
      );
    }
  }

  void _drawStars(
    Canvas canvas,
    Size size,
    List<SpaceStar> stars,
    double t, {
    required double drift,
    required double scale,
    required double maxAlpha,
    bool cross = false,
  }) {
    for (final star in stars) {
      final twinkle =
          0.30 + 0.70 * (1 + math.sin(star.twinklePhase + t * star.twinkleSpeed)) / 2;
      final alpha =
          (maxAlpha * twinkle * (0.4 + 0.6 * (star.size / 2.0))).clamp(0.0, maxAlpha);
      final color = switch (star.tone) {
        1 => AppColors.accentStrong,
        2 => AppColors.tertiary,
        _ => Colors.white,
      };
      final x = ((star.x + drift) % 1.0) * size.width;
      final y = star.y * size.height;
      final r = star.size * scale;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = color.withValues(alpha: alpha),
      );
      // 큰 별이 가장 밝은 순간에만 십자광이 살짝 번진다.
      if (cross && star.size > 1.3 && twinkle > 0.82) {
        final flare = (twinkle - 0.82) / 0.18;
        final len = r * (3.0 + 2.5 * flare);
        final flarePaint = Paint()
          ..color = color.withValues(alpha: 0.30 * flare)
          ..strokeWidth = 1.0
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(x - len, y), Offset(x + len, y), flarePaint);
        canvas.drawLine(Offset(x, y - len), Offset(x, y + len), flarePaint);
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
  bool shouldRepaint(covariant _SpacePainter oldDelegate) => false;
}
