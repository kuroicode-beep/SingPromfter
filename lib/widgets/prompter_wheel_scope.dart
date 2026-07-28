// file: lib/widgets/prompter_wheel_scope.dart
//
// 무대에서 마우스 휠의 뜻을 바꾼다.
//   그냥 휠  → 이전/다음 가사 줄 (반주도 그 줄로 이동)
//   Ctrl+휠 → 글자 크기
//
// 자식 가사 뷰가 NeverScrollableScrollPhysics를 쓰기 때문에 Scrollable이
// 포인터 시그널을 가져가지 않고 여기까지 올라온다.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/wheel_step_accumulator.dart';

class PrompterWheelScope extends StatefulWidget {
  final Widget child;

  /// +1 = 다음 줄(아래로), -1 = 이전 줄.
  final void Function(int lineDelta) onStepLine;

  /// +1 = 크게, -1 = 작게.
  final void Function(int sizeDelta) onStepFontSize;

  const PrompterWheelScope({
    super.key,
    required this.child,
    required this.onStepLine,
    required this.onStepFontSize,
  });

  @override
  State<PrompterWheelScope> createState() => _PrompterWheelScopeState();
}

class _PrompterWheelScopeState extends State<PrompterWheelScope> {
  // Ctrl 여부에 따라 누적기를 나눈다. 하나로 쓰면 모드를 바꿀 때
  // 직전 모드의 잔여 델타가 새어 나가 엉뚱하게 한 칸이 움직인다.
  final _lineAccumulator = WheelStepAccumulator();
  final _sizeAccumulator = WheelStepAccumulator();

  /// 휠을 빠르게 굴릴 때 seek이 폭주하지 않게 막는다.
  /// 아직 한 번도 움직이지 않았으면(null) 무조건 통과시킨다 —
  /// 스톱워치를 생성 시점부터 돌리면 화면을 연 직후의 첫 휠이 삼켜진다.
  static const _minInterval = Duration(milliseconds: 60);
  Stopwatch? _sinceLastStep;

  void _handleSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;

    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final accumulator = ctrl ? _sizeAccumulator : _lineAccumulator;
    final steps = accumulator.consume(event.scrollDelta.dy);
    if (steps == 0) return;

    final since = _sinceLastStep;
    if (since != null && since.elapsed < _minInterval) return;
    _sinceLastStep = Stopwatch()..start();

    if (ctrl) {
      // 휠을 위로 굴리면 델타가 음수 — 글자는 커지는 쪽이 자연스럽다.
      widget.onStepFontSize(-steps);
    } else {
      widget.onStepLine(steps);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: _handleSignal,
      child: widget.child,
    );
  }
}
