// file: lib/widgets/prompter_space_background.dart
//
// 프롬프터 우주 배경 — 단계별로 패턴이 다른 5가지 연출 + 끄기.
// B 단축키가 1→2→3→4→5→끄기→1 로 순환한다(설정 spaceBackgroundLevel).
//
//   1 성야     : 별밭 2겹 + 성운 + 은하수 + 별똥별 (기본)
//   2 오로라   : 물결치는 오로라 커튼 3겹 + 성긴 별
//   3 은하     : 회전하는 3팔 나선은하 + 코어 광휘
//   4 유성우   : 별똥별 4줄기 동시 낙하 + 밀한 별밭
//   5 스톰     : 성운 맥동 + 폭발 링 + 쌍별똥별 — 가장 화려하게
//
// 시스템 '움직임 줄이기'는 따르지 않는다 — B로 직접 제어(2026-08-05 지정).
// 전부 어두운 저채도 톤 위에 그려 흰 가사 대비를 지킨다.
//
// 렌더 원칙은 EQ 미터와 동일: setState 없이 repaint notifier, IgnorePointer.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_theme.dart';

/// 우주 배경 단계 수(끄기 제외).
const int spaceBackgroundMaxLevel = 5;

/// B 순환 규칙: 1→2→…→5→0(끄기)→1. (순수 함수 — 테스트 대상)
int nextSpaceBackgroundLevel(int current) =>
    current >= spaceBackgroundMaxLevel ? 0 : current + 1;

/// 단계 이름 — 스낵 안내·설정 칩 공용.
String spaceBackgroundLevelLabel(int level) => switch (level) {
  0 => '끄기',
  1 => '1단계 · 성야',
  2 => '2단계 · 오로라',
  3 => '3단계 · 은하',
  4 => '4단계 · 유성우',
  5 => '5단계 · 스톰',
  _ => '$level단계',
};

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
  /// 0=끄기, 1~5=단계. 범위 밖은 안전하게 0 취급.
  final int level;

  const PrompterSpaceBackground({super.key, required this.level});

  @override
  State<PrompterSpaceBackground> createState() =>
      _PrompterSpaceBackgroundState();
}

class _PrompterSpaceBackgroundState extends State<PrompterSpaceBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  /// 경과 시간(초) — painter가 모든 위상을 이걸로 만든다.
  final ValueNotifier<double> _time = ValueNotifier(0);

  bool get _on =>
      widget.level >= 1 && widget.level <= spaceBackgroundMaxLevel;

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
    if (oldWidget.level != widget.level) _syncTicker();
  }

  void _syncTicker() {
    if (_on && !_ticker.isActive) {
      _ticker.start();
    } else if (!_on && _ticker.isActive) {
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
    if (!_on) return const SizedBox.shrink();
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _SpacePainter(repaint: _time, level: widget.level),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _SpacePainter extends CustomPainter {
  final ValueNotifier<double> time;
  final int level;

  _SpacePainter({required ValueNotifier<double> repaint, required this.level})
    : time = repaint,
      super(repaint: repaint);

  static final List<SpaceStar> _farStars = generateStars(160, seed: 7);
  static final List<SpaceStar> _nearStars = generateStars(70, seed: 21);

  /// 나선은하 팔 입자(3팔 × 80개) — 극좌표를 미리 만들어 두고 회전만 시킨다.
  static final List<({double theta, double radius, double size})> _spiral = () {
    final rng = math.Random(11);
    final points = <({double theta, double radius, double size})>[];
    for (var arm = 0; arm < 3; arm++) {
      for (var i = 0; i < 80; i++) {
        final along = i / 80.0;
        points.add((
          theta: along * 4.6 +
              arm * 2 * math.pi / 3 +
              (rng.nextDouble() - 0.5) * 0.35,
          radius: 0.05 + along * 0.42 + (rng.nextDouble() - 0.5) * 0.03,
          size: 0.8 + rng.nextDouble() * 1.4,
        ));
      }
    }
    return points;
  }();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = time.value;

    _deepSpaceWash(canvas, size);
    switch (level) {
      case 1:
        _paintStarryNight(canvas, size, t);
      case 2:
        _paintAurora(canvas, size, t);
      case 3:
        _paintGalaxy(canvas, size, t);
      case 4:
        _paintMeteorShower(canvas, size, t);
      default:
        _paintCosmicStorm(canvas, size, t);
    }
  }

  // ── 1단계 성야 ──
  void _paintStarryNight(Canvas canvas, Size size, double t) {
    _milkyWay(canvas, size, t, intensity: 1.0);
    _breathingNebulas(canvas, size, t, intensity: 1.0);
    _drawStars(canvas, size, _farStars, t,
        drift: t * 0.003, scale: 0.9, maxAlpha: 0.70);
    _drawStars(canvas, size, _nearStars, t,
        drift: t * 0.011, scale: 1.6, maxAlpha: 0.92, cross: true);
    _meteor(canvas, size, t, period: 4.5, seedBase: 5, brightness: 0.95);
  }

  // ── 2단계 오로라 — 빛나는 커튼 3겹. 세로 컬럼마다 물결 위치·주름 밝기를
  // 달리해 커튼이 너울대는 느낌을 낸다(위아래 모두 페이드 — 능선처럼 안 보이게).
  void _paintAurora(Canvas canvas, Size size, double t) {
    _drawStars(canvas, size, _farStars, t,
        drift: t * 0.002, scale: 0.8, maxAlpha: 0.55);
    const cols = 44;
    final colW = size.width / cols;
    final colors = [AppColors.accentMax, AppColors.accentStrong, Colors.white];
    for (var band = 0; band < 3; band++) {
      final baseY = size.height * (0.12 + band * 0.11);
      final amp = size.height * (0.05 + band * 0.02);
      final speed = 0.55 + band * 0.25;
      final color = colors[band];
      for (var i = 0; i < cols; i++) {
        final fx = i / cols;
        final topY = baseY +
            amp * math.sin(fx * 5.5 + t * speed + band * 2.1) +
            amp * 0.4 * math.sin(fx * 11 - t * speed * 1.7);
        final h = size.height *
            0.20 *
            (0.6 + 0.4 * math.sin(fx * 7 + t * (speed + 0.3) + band));
        // 커튼 주름 — 밝은 세로줄이 옆으로 흘러간다.
        final fold = 0.5 + 0.5 * math.sin(fx * 17 + t * 1.4 + band * 3.0);
        // 컬럼을 두 배 폭으로 겹쳐 그려 세로 이음선을 지운다(가산이라 자연 블렌딩).
        final alpha = (0.09 + 0.15 * fold) * (1 - band * 0.15);
        final rect = Rect.fromLTWH(i * colW - colW * 0.5, topY, colW * 2, h);
        canvas.drawRect(
          rect,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0),
                color.withValues(alpha: alpha),
                color.withValues(alpha: 0),
              ],
              stops: const [0.0, 0.35, 1.0],
            ).createShader(rect),
        );
      }
    }
    _meteor(canvas, size, t, period: 8.0, seedBase: 17, brightness: 0.6);
  }

  // ── 3단계 은하 — 나선팔이 천천히 돈다 ──
  void _paintGalaxy(Canvas canvas, Size size, double t) {
    _drawStars(canvas, size, _farStars, t,
        drift: t * 0.002, scale: 0.85, maxAlpha: 0.55);
    final center = Offset(size.width * 0.52, size.height * 0.44);
    final unit = size.shortestSide;
    final rot = t * 0.06;

    // 코어 광휘 — 맥동.
    final corePulse = 0.8 + 0.2 * math.sin(t * 0.9);
    final coreArea = Rect.fromCircle(center: center, radius: unit * 0.20);
    canvas.drawCircle(
      center,
      unit * 0.20,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.30 * corePulse),
            AppColors.tertiary.withValues(alpha: 0.12 * corePulse),
            Colors.transparent,
          ],
          stops: const [0.0, 0.35, 1.0],
        ).createShader(coreArea),
    );

    // 팔 입자 — 바깥일수록 어둡고 파랗다.
    for (final p in _spiral) {
      final theta = p.theta + rot;
      final pos = center +
          Offset(math.cos(theta), math.sin(theta) * 0.62) * (p.radius * unit);
      final inner = 1 - (p.radius / 0.47);
      final color = Color.lerp(
        AppColors.accentStrong,
        Colors.white,
        inner.clamp(0.0, 1.0),
      )!;
      canvas.drawCircle(
        pos,
        p.size,
        Paint()..color = color.withValues(alpha: 0.25 + 0.45 * inner),
      );
    }
    _meteor(canvas, size, t, period: 9.0, seedBase: 29, brightness: 0.55);
  }

  // ── 4단계 유성우 — 별똥별 네 줄기가 겹쳐 떨어진다 ──
  void _paintMeteorShower(Canvas canvas, Size size, double t) {
    _milkyWay(canvas, size, t, intensity: 0.8);
    _drawStars(canvas, size, _farStars, t,
        drift: t * 0.004, scale: 0.9, maxAlpha: 0.75);
    _drawStars(canvas, size, _nearStars, t,
        drift: t * 0.013, scale: 1.5, maxAlpha: 0.9, cross: true);
    _meteor(canvas, size, t, period: 3.2, seedBase: 5, brightness: 1.0);
    _meteor(canvas, size, t + 1.1, period: 2.7, seedBase: 43, brightness: 0.85);
    _meteor(canvas, size, t + 2.0, period: 3.9, seedBase: 71, brightness: 0.9);
    _meteor(canvas, size, t + 0.6, period: 4.6, seedBase: 97, brightness: 0.7);
  }

  // ── 5단계 스톰 — 전부 켜고 폭발 링까지 ──
  void _paintCosmicStorm(Canvas canvas, Size size, double t) {
    _milkyWay(canvas, size, t, intensity: 1.4);
    _breathingNebulas(canvas, size, t, intensity: 1.6, speed: 2.2);
    _drawStars(canvas, size, _farStars, t,
        drift: t * 0.005, scale: 1.0, maxAlpha: 0.8);
    _drawStars(canvas, size, _nearStars, t,
        drift: t * 0.016, scale: 1.7, maxAlpha: 1.0, cross: true);

    // 폭발 링 — 3초마다 어딘가에서 빛의 파문이 퍼진다.
    const ringPeriod = 3.0;
    final cycle = t % ringPeriod;
    final n = t ~/ ringPeriod;
    final rng = math.Random(n * 13 + 3);
    final center = Offset(
      size.width * (0.1 + 0.8 * rng.nextDouble()),
      size.height * (0.1 + 0.8 * rng.nextDouble()),
    );
    final progress = cycle / ringPeriod;
    final radius = size.shortestSide * (0.04 + 0.30 * progress);
    final fade = (1 - progress) * 0.55;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * (1 - progress) + 0.6
        ..color = AppColors.accentMax.withValues(alpha: fade),
    );
    canvas.drawCircle(
      center,
      radius * 0.72,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: fade * 0.5),
    );

    _meteor(canvas, size, t, period: 2.6, seedBase: 5, brightness: 1.0);
    _meteor(canvas, size, t + 1.3, period: 3.4, seedBase: 57, brightness: 0.9);
  }

  // ── 공용 요소 ──

  /// 심우주 남색 워시 — 모든 단계 공통 바탕.
  void _deepSpaceWash(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF0E1430).withValues(alpha: 0.55),
            const Color(0xFF090C1E).withValues(alpha: 0.30),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Offset.zero & size),
    );
  }

  void _milkyWay(Canvas canvas, Size size, double t, {required double intensity}) {
    final bandShift = 0.06 * math.sin(t * 0.03);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(-1, -0.6 + bandShift),
          end: Alignment(1, 0.6 + bandShift),
          colors: [
            Colors.white.withValues(alpha: 0),
            AppColors.accentStrong.withValues(alpha: 0.10 * intensity),
            Colors.white.withValues(alpha: 0.13 * intensity),
            AppColors.primary.withValues(alpha: 0.10 * intensity),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0.15, 0.38, 0.5, 0.62, 0.85],
        ).createShader(Offset.zero & size),
    );
  }

  void _breathingNebulas(
    Canvas canvas,
    Size size,
    double t, {
    required double intensity,
    double speed = 1.0,
  }) {
    final breathe = 0.75 + 0.25 * math.sin(t * 0.11 * speed);
    _nebula(canvas, size,
        center: Offset(
          size.width * (0.22 + 0.07 * math.sin(t * 0.05 * speed)),
          size.height * (0.28 + 0.06 * math.cos(t * 0.04 * speed)),
        ),
        radius: size.shortestSide * 0.62,
        color: AppColors.primary,
        alpha: 0.22 * breathe * intensity);
    _nebula(canvas, size,
        center: Offset(
          size.width * (0.80 - 0.06 * math.cos(t * 0.037 * speed)),
          size.height * (0.66 + 0.07 * math.sin(t * 0.045 * speed)),
        ),
        radius: size.shortestSide * 0.55,
        color: AppColors.accentStrong,
        alpha: 0.18 * (1.5 - breathe * 0.5) * intensity);
    _nebula(canvas, size,
        center: Offset(
          size.width * (0.55 + 0.08 * math.sin(t * 0.028 * speed)),
          size.height * (0.12 + 0.04 * math.cos(t * 0.05 * speed)),
        ),
        radius: size.shortestSide * 0.42,
        color: AppColors.tertiary,
        alpha: 0.10 * intensity);
  }

  /// 별똥별 하나 — 주기의 앞 1.2초 동안 날아간다. 시드로 궤적이 달라진다.
  void _meteor(
    Canvas canvas,
    Size size,
    double t, {
    required double period,
    required int seedBase,
    required double brightness,
  }) {
    final cycle = t % period;
    if (cycle >= 1.2) return;
    final progress = cycle / 1.2;
    final n = t ~/ period;
    final rng = math.Random(n * 31 + seedBase);
    final sx = size.width * (0.05 + 0.8 * rng.nextDouble());
    final sy = size.height * (0.05 + 0.35 * rng.nextDouble());
    final head = Offset(
      sx + size.width * 0.28 * progress,
      sy + size.height * 0.22 * progress,
    );
    final tail = head - Offset(size.width * 0.10, size.height * 0.075);
    final fade = math.sin(progress * math.pi) * brightness;
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
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
    final headArea = Rect.fromCircle(center: head, radius: 10);
    canvas.drawCircle(
      head,
      10,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: fade),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(headArea),
    );
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
          (maxAlpha * twinkle * (0.4 + 0.6 * (star.size / 2.0))).clamp(0.0, 1.0);
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
      // 큰 별이 밝아지는 순간 십자광이 번진다.
      if (cross && star.size > 1.1 && twinkle > 0.76) {
        final flare = (twinkle - 0.76) / 0.24;
        final len = r * (3.2 + 3.0 * flare);
        final flarePaint = Paint()
          ..color = color.withValues(alpha: 0.5 * flare)
          ..strokeWidth = 1.2
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
            color.withValues(alpha: alpha.clamp(0.0, 1.0)),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }

  @override
  bool shouldRepaint(covariant _SpacePainter oldDelegate) =>
      oldDelegate.level != level;
}
