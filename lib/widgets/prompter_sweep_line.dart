// file: lib/widgets/prompter_sweep_line.dart
//
// 현재 줄 하나만 그리는 잎 위젯. 노래가 흐르는 대로 글자가 왼쪽부터 하나씩
// 밝아져 "지금 어디를 부르고 있는지"를 글자 단위로 알려 준다.
//
// PrompterEqMeter와 같은 규칙을 따른다:
//   setState 없음 · 자체 Ticker · position은 명령형으로 읽음 ·
//   CustomPaint의 repaint notifier로만 다시 그림.
// 가사 Column 전체는 절대 리빌드하지 않는다(줄이 바뀔 때만 리빌드된다).
//
// 왜 CustomPainter + TextPainter인가:
//  - ShaderMask: 그라데이션 스톱이 **박스** 좌표라 중앙정렬 보정이 필요하고,
//    매 프레임 saveLayer가 붙으며, 줄바꿈된 줄의 계단 채움을 표현할 수 없다.
//  - Text 2단 + ClipRect: 클립 위치를 잡으려면 어차피 TextPainter로 재야 하고,
//    그림자 2겹이 중복되며, 두 Text가 서로 다른 지점에서 줄바꿈할 수 있다.
//  - TextPainter만 computeLineMetrics/getPositionForOffset/getOffsetForCaret을
//    준다. 큰 글씨의 긴 한글 줄은 메인 창에서 반드시 줄바꿈되므로 이게 결정적.
//
// 리페인트 빈도: 채움 위치를 **글자 경계로 내림 스냅한 뒤에** notifier에 쓴다.
// 그래서 60Hz가 아니라 글자당 한 번(초 3~8회)만 다시 그린다. Ticker는 60Hz로
// 돌지만 산술만 한다 — TextPainter.layout은 여기서 절대 부르지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../controllers/playback_controller.dart';
import '../models/prompter_lines.dart';
import 'prompter_current_line.dart';

/// 무대 두 화면이 함께 쓰는 스윕 빌더.
///
/// 싱크 시각이 없는 줄은 평범한 Text로 둔다 — 추정값으로 개별 글자를 켜면
/// 자신 있게 틀린 음절을 가리키게 된다.
Widget Function(PrompterLine line, TextStyle style)? prompterSweepBuilder({
  required PlaybackController playback,
  required bool enabled,
}) {
  if (!enabled) return null;
  return (line, style) => line.time == null
      ? Text(line.text, textAlign: TextAlign.center, style: style)
      : PrompterSweepLine(
          playback: playback,
          text: line.text,
          style: style,
        );
}

/// 이미 부른 구간의 사각형들. 줄바꿈되면 여러 개가 된다.
@immutable
class SweepGeometry {
  final List<Rect> filled;

  const SweepGeometry(this.filled);

  static const empty = SweepGeometry([]);

  bool sameAs(SweepGeometry other) {
    if (filled.length != other.filled.length) return false;
    for (var i = 0; i < filled.length; i++) {
      if (filled[i] != other.filled[i]) return false;
    }
    return true;
  }
}

/// 진행률 0..1을 이미 부른 구간으로 바꾼다. (순수 함수 — 테스트 대상)
///
/// 글자 **수**가 아니라 글리프 **폭**에 비례해 나눈다. 한글·영문·공백의
/// 폭이 제각각이라 글자 수로 나누면 눈에 띄게 어긋난다.
/// 부분적으로 걸친 줄은 문자 경계로 **내림 스냅**해 한 글자씩 켜지게 한다.
SweepGeometry sweepGeometryFor({
  required TextPainter painter,
  required double fraction,
}) {
  if (fraction <= 0) return SweepGeometry.empty;
  final metrics = painter.computeLineMetrics();
  if (metrics.isEmpty) return SweepGeometry.empty;

  final total = metrics.fold<double>(0, (sum, m) => sum + m.width);
  if (total <= 0) return SweepGeometry.empty;

  var remain = fraction.clamp(0.0, 1.0) * total;
  final filled = <Rect>[];

  for (final m in metrics) {
    final top = m.baseline - m.ascent;
    final bottom = m.baseline + m.descent;
    if (remain >= m.width) {
      filled.add(Rect.fromLTRB(m.left, top, m.left + m.width, bottom));
      remain -= m.width;
      continue;
    }
    if (remain <= 0) break;

    // 폭 위치를 문자 경계로 내림 — 글자가 반쯤 밝아지지 않게.
    final caret = painter.getPositionForOffset(
      Offset(m.left + remain, m.baseline),
    );
    final snapped = painter.getOffsetForCaret(
      TextPosition(offset: caret.offset),
      Rect.zero,
    );
    final right = snapped.dx.clamp(m.left, m.left + m.width);
    if (right > m.left) {
      filled.add(Rect.fromLTRB(m.left, top, right, bottom));
    }
    break;
  }

  return SweepGeometry(filled);
}

class PrompterSweepLine extends StatefulWidget {
  final PlaybackController playback;
  final String text;

  /// 현재 줄의 평소 스타일. 이미 부른 부분이 이 밝기로 켜진다.
  final TextStyle style;

  const PrompterSweepLine({
    super.key,
    required this.playback,
    required this.text,
    required this.style,
  });

  @override
  State<PrompterSweepLine> createState() => _PrompterSweepLineState();
}

class _PrompterSweepLineState extends State<PrompterSweepLine>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<SweepGeometry> _geometry = ValueNotifier(
    SweepGeometry.empty,
  );

  TextPainter? _sung;
  TextPainter? _unsung;
  double _laidOutWidth = 0;
  bool _listeningToPosition = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    widget.playback.state.addListener(_syncTicker);
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant PrompterSweepLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _disposePainters();
      _geometry.value = SweepGeometry.empty;
      _recompute();
    }
  }

  @override
  void dispose() {
    _stopPositionListener();
    widget.playback.state.removeListener(_syncTicker);
    _ticker.dispose();
    _geometry.dispose();
    _disposePainters();
    super.dispose();
  }

  void _disposePainters() {
    _sung?.dispose();
    _unsung?.dispose();
    _sung = null;
    _unsung = null;
    _laidOutWidth = 0;
  }

  /// 재생 중일 때만 틱을 돌린다. 멈춰 있는 동안은 위치 리스너로 대신한다 —
  /// 정지 상태에서 seek하면 스윕이 낡은 자리에 남기 때문이다.
  void _syncTicker() {
    final playing = widget.playback.state.value.playing;
    if (playing) {
      _stopPositionListener();
      if (!_ticker.isActive) _ticker.start();
      return;
    }
    if (_ticker.isActive) _ticker.stop();
    if (!_listeningToPosition) {
      widget.playback.position.addListener(_recompute);
      _listeningToPosition = true;
    }
    // 멈춘 자리에 정확히 놓이도록 한 번 더 계산한다.
    _recompute();
  }

  void _stopPositionListener() {
    if (!_listeningToPosition) return;
    widget.playback.position.removeListener(_recompute);
    _listeningToPosition = false;
  }

  void _onTick(Duration elapsed) => _recompute();

  /// 산술만 한다. TextPainter.layout은 여기서 절대 부르지 않는다.
  void _recompute() {
    final painter = _unsung;
    if (painter == null || !mounted) return;

    final fraction = widget.playback.currentLineFraction();
    final next = fraction == null
        ? SweepGeometry.empty
        : sweepGeometryFor(painter: painter, fraction: fraction);

    // 문자 경계가 그대로면 다시 그리지 않는다 — 리페인트가 글자당 한 번이 된다.
    if (next.sameAs(_geometry.value)) return;
    _geometry.value = next;
  }

  /// 폭이 바뀌었을 때만 다시 레이아웃한다.
  void _layout(double maxWidth) {
    if (_unsung != null && (_laidOutWidth - maxWidth).abs() < 0.5) return;
    _disposePainters();
    _sung = _painter(widget.style)..layout(maxWidth: maxWidth);
    _unsung = _painter(prompterUnsungStyle(widget.style))
      ..layout(maxWidth: maxWidth);
    _laidOutWidth = maxWidth;
  }

  TextPainter _painter(TextStyle style) => TextPainter(
    text: TextSpan(text: widget.text, style: style),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : double.infinity;
        if (maxWidth.isFinite) _layout(maxWidth);
        final painter = _unsung;
        if (painter == null) {
          return Text(
            widget.text,
            textAlign: TextAlign.center,
            style: widget.style,
          );
        }
        // 레이아웃이 새로 잡혔으면 스윕 위치도 즉시 맞춘다.
        WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());

        return Semantics(
          label: widget.text,
          child: CustomPaint(
            size: Size(painter.width, painter.height),
            painter: _SweepPainter(
              sung: _sung!,
              unsung: painter,
              repaint: _geometry,
            ),
          ),
        );
      },
    );
  }
}

class _SweepPainter extends CustomPainter {
  final TextPainter sung;
  final TextPainter unsung;
  final ValueNotifier<SweepGeometry> geometry;

  _SweepPainter({
    required this.sung,
    required this.unsung,
    required ValueNotifier<SweepGeometry> repaint,
  }) : geometry = repaint,
       super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    // 가운데 정렬된 줄이 CustomPaint 상자 안에서 흔들리지 않도록 원점을 잡는다.
    final origin = Offset((size.width - unsung.width) / 2, 0);
    unsung.paint(canvas, origin);

    final filled = geometry.value.filled;
    if (filled.isEmpty) return;

    canvas.save();
    final path = Path();
    for (final rect in filled) {
      path.addRect(rect.shift(origin));
    }
    canvas.clipPath(path);
    // 이미 부른 부분만 밝은 스타일로 덮어 그린다.
    sung.paint(canvas, origin);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SweepPainter oldDelegate) =>
      oldDelegate.sung != sung || oldDelegate.unsung != unsung;
}
