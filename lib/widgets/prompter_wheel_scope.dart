// file: lib/widgets/prompter_wheel_scope.dart
//
// 무대·메인 창에서 마우스 휠의 뜻을 바꾼다.
//   Ctrl+휠   → 글자 크기
//   Alt+휠    → 키(피치)
//   Shift+휠  → 템포
//   그냥 휠   → 아무 일도 하지 않는다
//
// v3.0.0까지는 맨휠이 가사 줄 이동이었는데, Windows에서 수식키 상태가
// 이벤트 사이에 순간적으로 빠져 보이는 일이 있어 Alt+휠을 굴리는 중에
// 줄 이동이 끼어들었다("키도 바뀌고 줄도 넘어감"). 수식키 없는 휠을
// 아예 비워 두면 그 새는 이벤트가 조용히 무시된다 — 줄 이동은 줄 클릭·
// 위/아래 버튼·Home/End가 맡는다.
//
// 모드는 **완전히 배타적**이다. 한 이벤트는 한 모드에만 들어가고,
// 모드가 바뀌면 이전 모드의 누적·시간 제한을 즉시 버린다.
//
// 자식 가사 뷰가 NeverScrollableScrollPhysics를 쓰기 때문에 Scrollable이
// 포인터 시그널을 가져가지 않고 여기까지 올라온다.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/wheel_step_accumulator.dart';

/// 휠 입력이 무엇을 뜻하는지. (순수 판정 — 테스트 대상)
enum WheelMode { fontSize, pitch, tempo }

/// 눌린 수식키로 모드를 정한다. 수식키가 없으면 null — 휠은 쉰다.
///
/// 우선순위 alt(키) > shift(템포) > ctrl(크기).
/// 여러 개가 눌려도 하나만 고른다 — 두 가지가 동시에 먹으면 무대에서
/// 무엇이 바뀌었는지 알 수 없다(v2.7.0에서 고쳤던 바로 그 문제).
WheelMode? wheelModeFor({
  required bool ctrl,
  required bool alt,
  bool shift = false,
}) {
  if (alt) return WheelMode.pitch;
  if (shift) return WheelMode.tempo;
  if (ctrl) return WheelMode.fontSize;
  return null;
}

class PrompterWheelScope extends StatefulWidget {
  final Widget child;

  /// +1 = 크게, -1 = 작게.
  final void Function(int sizeDelta) onStepFontSize;

  /// +1 = 키 올림, -1 = 키 내림. null이면 Alt+휠은 아무 일도 하지 않는다.
  final void Function(int pitchDelta)? onStepPitch;

  /// +1 = 빠르게, -1 = 느리게. null이면 Shift+휠은 아무 일도 하지 않는다.
  final void Function(int tempoDelta)? onStepTempo;

  const PrompterWheelScope({
    super.key,
    required this.child,
    required this.onStepFontSize,
    this.onStepPitch,
    this.onStepTempo,
  });

  @override
  State<PrompterWheelScope> createState() => _PrompterWheelScopeState();
}

class _PrompterWheelScopeState extends State<PrompterWheelScope> {
  // 모드마다 누적기를 따로 둔다. 하나로 쓰면 모드를 바꿀 때 직전 모드의
  // 잔여 델타가 새어 나가 엉뚱하게 한 칸이 움직인다.
  final _accumulators = {
    for (final mode in WheelMode.values) mode: WheelStepAccumulator(),
  };

  /// 휠을 빠르게 굴릴 때 seek·렌더가 폭주하지 않게 막는다.
  /// 모드별로 따로 재는다 — 공유하면 크기 변경이 줄 이동을 삼킨다.
  final _lastStep = <WheelMode, Stopwatch>{};
  static const _minInterval = Duration(milliseconds: 60);

  WheelMode? _activeMode;

  void _handleSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;

    final keyboard = HardwareKeyboard.instance;
    final mode = wheelModeFor(
      ctrl: keyboard.isControlPressed,
      alt: keyboard.isAltPressed,
      shift: keyboard.isShiftPressed,
    );
    if (mode == null) return; // 수식키 없는 휠은 쉰다
    if (mode == WheelMode.pitch && widget.onStepPitch == null) return;
    if (mode == WheelMode.tempo && widget.onStepTempo == null) return;

    // 모드가 바뀌면 이전 모드의 흔적을 전부 버린다.
    if (_activeMode != mode) {
      for (final acc in _accumulators.values) {
        acc.reset();
      }
      _lastStep.clear();
      _activeMode = mode;
    }

    final steps = _accumulators[mode]!.consume(event.scrollDelta.dy);
    if (steps == 0) return;

    final since = _lastStep[mode];
    if (since != null && since.elapsed < _minInterval) return;
    _lastStep[mode] = Stopwatch()..start();

    switch (mode) {
      case WheelMode.fontSize:
        // 휠을 위로 굴리면 델타가 음수 — 글자는 커지는 쪽이 자연스럽다.
        widget.onStepFontSize(-steps);
      case WheelMode.pitch:
        widget.onStepPitch!(-steps);
      case WheelMode.tempo:
        widget.onStepTempo!(-steps);
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
