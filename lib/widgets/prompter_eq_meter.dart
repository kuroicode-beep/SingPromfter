// file: lib/widgets/prompter_eq_meter.dart
//
// 전체화면 프롬프터 좌하단의 EQ 미터. 정적인 무대 화면에 살아있는 느낌을 준다.
//
// 렌더 원칙 (진행바와 같은 leaf 구독 철학):
// - setState를 쓰지 않는다 — CustomPaint의 repaint notifier로만 다시 그린다.
// - 자체 Ticker로 구동하고, 정지 상태에선 감쇠가 끝나면 Ticker를 멈춘다.
// - 시각 장식일 뿐이므로 IgnorePointer + ExcludeSemantics로 감싼다.
//
// v2.8.0 연출: 24밴드 얇은 막대 + 반사 + 블룸 + 가로 세그먼트 + 피크 페이드.
// 색은 SVIL 팔레트(냉색 블루 램프 + 앰버 하나) 안에 머문다 — 무지개 스펙트럼은
// 가이드 위반이고, 앰버는 "핫"이라는 뜻을 지켜야 해서 레벨이 높을 때만 쓴다.
//
// 비용에서 가장 중요한 결정: 블룸을 막대마다 걸지 않는다. 24개 막대를 한
// Path에 모아 blur를 **한 번만** 건다. 프레임당 MaskFilter.blur 24회가
// 이 위젯에서 유일하게 프레임을 떨어뜨릴 수 있는 지점이다.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../controllers/playback_controller.dart';
import '../services/level_analysis_service.dart' show levelBandCount;
import '../theme/app_theme.dart';

/// 스무딩 규칙: 어택도 릴리즈도 지수 보간 — 즉시 점프하던 어택을 v4.1.0에서
/// 부드럽게 바꿨다(프레임당 55%씩 접근, 반응성은 유지). (순수 함수 — 테스트 대상)
double smoothLevel(
  double previous,
  double target, {
  double attack = 0.55,
  double release = 0.10,
}) {
  if (target >= previous) {
    final next = previous + (target - previous) * attack;
    return (target - next) < 0.002 ? target : next;
  }
  final next = previous - (previous - target) * release * 4;
  return next < target ? target : next;
}

/// 피크홀드 규칙: 새 값이 크면 갱신, 아니면 천천히 낙하. (순수 함수)
double holdPeak(double previousPeak, double current, {double fall = 0.012}) {
  if (current >= previousPeak) return current;
  final next = previousPeak - fall;
  return next < current ? current : next;
}

/// 막대 폭과 간격. (순수 함수 — 테스트 대상)
///
/// 예전 식은 간격이 **전체 폭**의 3%라 밴드가 늘면 간격이 막대를 잡아먹었다
/// (24밴드·520px에서 간격이 폭의 44%). 이제 막대 피치 비율로 잡는다.
({double barWidth, double gap}) eqBarMetrics(double width, int count) {
  if (count <= 0 || width <= 0) return (barWidth: 0, gap: 0);
  if (count == 1) return (barWidth: width, gap: 0);
  final pitch = width / count;
  final gap = (pitch * 0.28).clamp(1.0, 6.0);
  final barWidth = ((width - gap * (count - 1)) / count).clamp(
    1.0,
    double.infinity,
  );
  return (barWidth: barWidth, gap: gap);
}

class _EqFrame {
  final List<double> bars; // 0..1
  final List<double> peaks; // 0..1

  /// 피크가 얼마나 갓 찍혔는지 1..0. 갓 찍힌 피크만 밝게 번쩍인다.
  final List<double> peakAges;

  /// 급상승 스파크 1..0 — 막대가 빠르게 치솟은 직후 끝이 빛난다. (v4.1.0)
  final List<double> sparks;

  /// 하이라이트 스윕의 가로 위상 0..1. (v4.1.0)
  final double shimmer;

  const _EqFrame(
    this.bars,
    this.peaks,
    this.peakAges, [
    this.sparks = const [],
    this.shimmer = 0,
  ]);
}

class PrompterEqMeter extends StatefulWidget {
  final PlaybackController playback;

  const PrompterEqMeter({super.key, required this.playback});

  @override
  State<PrompterEqMeter> createState() => _PrompterEqMeterState();
}

class _PrompterEqMeterState extends State<PrompterEqMeter>
    with SingleTickerProviderStateMixin {
  /// 분석 결과가 오기 전 사인 폴백에 쓸 밴드 수. 실제 밴드 수와 맞춘다.
  static const int _fallbackBandCount = levelBandCount;

  late final Ticker _ticker;
  final ValueNotifier<_EqFrame> _frame = ValueNotifier(
    const _EqFrame([], [], []),
  );

  List<double> _bars = List.filled(_fallbackBandCount, 0);
  List<double> _peaks = List.filled(_fallbackBandCount, 0);
  List<double> _peakAges = List.filled(_fallbackBandCount, 0);
  List<double> _sparks = List.filled(_fallbackBandCount, 0);
  double _pulsePhase = 0;
  double _shimmer = 0;
  bool _reducedMotion = false;

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 움직임을 줄여 달라는 시스템 설정을 존중한다. 켜져 있으면 틱을 돌리지 않고
    // 정적인 막대만 남긴다(설정의 EQ 끄기와는 별개의 안전망).
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced == _reducedMotion) return;
    _reducedMotion = reduced;
    _syncTicker();
  }

  bool get _playing =>
      !_reducedMotion && widget.playback.state.value.playing;

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
      // frameAt이 아니라 sampleAt — 25fps 데이터를 60Hz로 그리면 프레임이
      // 2.4번씩 반복돼 얇은 막대에서 계단이 보인다.
      targets =
          levels.sampleAt(widget.playback.position.value) ??
          List.filled(levels.bandCount, 0.0);
    } else if (playing) {
      // 분석 전(또는 ffmpeg 부재) 폴백 — 위상이 다른 사인 펄스로 살아있게.
      // 진폭을 넓게 잡아 분석 결과가 없어도 움직임이 또렷하게 보이도록 한다.
      _pulsePhase += 0.09;
      targets = List.generate(
        _fallbackBandCount,
        // 위상 간격을 밴드 수에 맞춰 좁힌다 — 24밴드에 1.1을 쓰면 모아레가 생긴다.
        (i) => 0.30 + 0.55 * (1 + math.sin(_pulsePhase + i * 0.28)) / 2,
      );
    } else {
      targets = List.filled(_bars.length, 0.0);
    }

    if (targets.length != _bars.length) {
      _bars = List.filled(targets.length, 0);
      _peaks = List.filled(targets.length, 0);
      _peakAges = List.filled(targets.length, 0);
      _sparks = List.filled(targets.length, 0);
    }

    var changed = false;
    var levelSum = 0.0;
    for (var i = 0; i < targets.length; i++) {
      final nextBar = smoothLevel(_bars[i], targets[i]);
      final nextPeak = holdPeak(_peaks[i], nextBar);
      // 피크가 새로 찍히면 1로 되살아나고, 아니면 천천히 식는다.
      final nextAge = nextPeak > _peaks[i] + 0.001
          ? 1.0
          : (_peakAges[i] - 0.02).clamp(0.0, 1.0);
      // 급상승이면 스파크가 되살아나고, 아니면 빠르게 식는다.
      final nextSpark = nextBar - _bars[i] > 0.07
          ? 1.0
          : (_sparks[i] - 0.06).clamp(0.0, 1.0);
      if ((nextBar - _bars[i]).abs() > 0.001 ||
          (nextPeak - _peaks[i]).abs() > 0.001 ||
          (nextAge - _peakAges[i]).abs() > 0.001 ||
          (nextSpark - _sparks[i]).abs() > 0.001) {
        changed = true;
      }
      _bars[i] = nextBar;
      _peaks[i] = nextPeak;
      _peakAges[i] = nextAge;
      _sparks[i] = nextSpark;
      levelSum += nextBar;
    }

    // 스윕은 레벨이 높을수록 빨라진다 — 조용하면 거의 멈춘 듯 흐른다.
    if (playing && targets.isNotEmpty) {
      final avg = levelSum / targets.length;
      _shimmer = (_shimmer + 0.003 + 0.009 * avg) % 1.0;
      changed = true;
    }

    if (changed) {
      _frame.value = _EqFrame(
        List.unmodifiable(_bars),
        List.unmodifiable(_peaks),
        List.unmodifiable(_peakAges),
        List.unmodifiable(_sparks),
        _shimmer,
      );
    }
    if (!playing) _syncTicker();
  }

  @override
  Widget build(BuildContext context) {
    // 크기는 부모(무대 밴드)가 정한다. 제약이 없는 곳에 놓였을 때만
    // 예전 기본값으로 떨어진다.
    final painter = CustomPaint(
      painter: _EqMeterPainter(repaint: _frame, reducedMotion: _reducedMotion),
    );
    return IgnorePointer(
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            width: constraints.hasBoundedWidth ? constraints.maxWidth : 200,
            height: constraints.hasBoundedHeight
                ? constraints.maxHeight
                : 72,
            child: painter,
          ),
        ),
      ),
    );
  }
}

class _EqMeterPainter extends CustomPainter {
  final ValueNotifier<_EqFrame> repaintNotifier;
  final bool reducedMotion;

  _EqMeterPainter({
    required ValueNotifier<_EqFrame> repaint,
    this.reducedMotion = false,
  }) : repaintNotifier = repaint,
       super(repaint: repaint);

  /// 막대 영역과 반사 영역의 비율.
  static const double _mainRatio = 0.70;
  static const double _gapRatio = 0.04;

  /// 앰버(tertiary)를 쓰기 시작하는 레벨. 앰버는 "핫"이라는 뜻을 지킨다.
  static const double _hotLevel = 0.88;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = repaintNotifier.value;
    final count = frame.bars.isEmpty ? levelBandCount : frame.bars.length;
    if (count <= 0 || size.width <= 0 || size.height <= 0) return;

    final m = eqBarMetrics(size.width, count);
    if (m.barWidth <= 0) return;

    final mainH = size.height * _mainRatio;
    final reflectTop = mainH + size.height * _gapRatio;
    final reflectH = size.height - reflectTop;
    final radius = Radius.circular((m.barWidth / 2).clamp(1.0, 4.0));

    final trackPaint = Paint()..color = Colors.white.withValues(alpha: 0.05);
    var levelSum = 0.0;
    final bloom = Path();

    for (var i = 0; i < count; i++) {
      final x = i * (m.barWidth + m.gap);
      final level = i < frame.bars.length ? frame.bars[i] : 0.0;
      levelSum += level;

      // (1) 바탕 트랙 — 조용할 때도 미터가 거기 있다는 걸 보여 준다.
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, 0, m.barWidth, mainH), radius),
        trackPaint,
      );
      if (level <= 0.01) continue;

      final barH = mainH * level;
      final rect = Rect.fromLTWH(x, mainH - barH, m.barWidth, barH);

      // (2) 반사 — saveLayer 없이 깊이를 만든다.
      if (reflectH > 0 && !reducedMotion) {
        final rh = (barH * 0.5).clamp(0.0, reflectH);
        if (rh > 0.5) {
          final area = Rect.fromLTWH(x, reflectTop, m.barWidth, rh);
          canvas.drawRect(
            area,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary.withValues(alpha: 0.22),
                  AppColors.primary.withValues(alpha: 0),
                ],
              ).createShader(area),
          );
        }
      }

      // (3) 막대 — 레벨이 높을수록 밝아지고, 아주 뜨거울 때만 앰버가 얹힌다.
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, radius),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Color.lerp(AppColors.primary, AppColors.accentStrong, level)!,
              AppColors.accentMax,
              level > _hotLevel ? AppColors.tertiary : AppColors.accentMax,
            ],
            stops: const [0.0, 0.72, 1.0],
          ).createShader(rect),
      );
      bloom.addRRect(RRect.fromRectAndRadius(rect, radius));
    }

    // (4) 블룸 — 막대마다 blur를 걸면 24회가 된다. 한 Path에 모아 한 번만.
    final avg = levelSum / count;
    if (!reducedMotion && avg > 0.02) {
      canvas.drawPath(
        bloom,
        Paint()
          ..color = AppColors.accentStrong.withValues(alpha: 0.10 + 0.28 * avg)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + 8 * avg)
          ..blendMode = BlendMode.plus,
      );
    }

    // (4b) 하이라이트 스윕 — 밝은 띠 하나가 막대들 위를 흐른다. (v4.1.0)
    // blur 없이 가로 그라데이션 사각형 하나라 비용이 거의 없다.
    if (!reducedMotion && avg > 0.02 && frame.shimmer > 0) {
      final bandW = size.width * 0.22;
      final x = frame.shimmer * (size.width + bandW) - bandW;
      final area = Rect.fromLTWH(x, 0, bandW, mainH);
      canvas.save();
      canvas.clipPath(bloom);
      canvas.drawRect(
        area,
        Paint()
          ..shader = LinearGradient(
            colors: [
              AppColors.accentMax.withValues(alpha: 0),
              AppColors.accentMax.withValues(alpha: 0.10 + 0.16 * avg),
              AppColors.accentMax.withValues(alpha: 0),
            ],
          ).createShader(area)
          ..blendMode = BlendMode.plus,
      );
      canvas.restore();
    }

    // (4c) 급상승 스파크 — 치솟은 막대 끝만 반짝. 원마다 방사 그라데이션이라
    // MaskFilter 없이 끝난다(blur 1회 규칙 유지). (v4.1.0)
    if (!reducedMotion) {
      for (var i = 0; i < count; i++) {
        final spark = i < frame.sparks.length ? frame.sparks[i] : 0.0;
        if (spark <= 0.12) continue;
        final level = i < frame.bars.length ? frame.bars[i] : 0.0;
        if (level <= 0.02) continue;
        final cx = i * (m.barWidth + m.gap) + m.barWidth / 2;
        final cy = mainH * (1 - level);
        final r = m.barWidth * 1.6 + 3;
        final area = Rect.fromCircle(center: Offset(cx, cy), radius: r);
        canvas.drawCircle(
          Offset(cx, cy),
          r,
          Paint()
            ..shader = RadialGradient(
              colors: [
                AppColors.accentMax.withValues(alpha: 0.55 * spark),
                AppColors.accentMax.withValues(alpha: 0),
              ],
            ).createShader(area)
            ..blendMode = BlendMode.plus,
        );
      }
    }

    // (5) 가로 세그먼트 — 막대마다 계산하지 않고 전폭 선 스무 줄로 끝낸다.
    final segStep = (mainH / 20).clamp(3.0, 8.0);
    final segPaint = Paint()
      ..color = AppColors.background.withValues(alpha: 0.55)
      ..strokeWidth = 1.5;
    for (var y = segStep; y < mainH; y += segStep) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), segPaint);
    }

    // (6) 피크 캡 — 갓 찍힌 피크는 밝고, 오래된 피크는 흐려진다.
    // 갓 찍힌 캡 아래로 짧은 잔광 꼬리를 남긴다(v4.1.0, blur 없음).
    for (var i = 0; i < count; i++) {
      final peak = i < frame.peaks.length ? frame.peaks[i] : 0.0;
      if (peak <= 0.02) continue;
      final age = i < frame.peakAges.length ? frame.peakAges[i] : 0.0;
      final x = i * (m.barWidth + m.gap);
      final y = mainH * (1 - peak);
      if (!reducedMotion && age > 0.05) {
        final trailH = (10.0 * age).clamp(0.0, mainH - y);
        if (trailH > 1) {
          final area = Rect.fromLTWH(x, y + 1, m.barWidth, trailH);
          canvas.drawRect(
            area,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.accentMax.withValues(alpha: 0.35 * age),
                  AppColors.accentMax.withValues(alpha: 0),
                ],
              ).createShader(area),
          );
        }
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y - 1, m.barWidth, 2),
          const Radius.circular(1),
        ),
        Paint()
          ..color = AppColors.accentMax.withValues(alpha: 0.25 + 0.75 * age),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EqMeterPainter oldDelegate) =>
      oldDelegate.reducedMotion != reducedMotion;
}
