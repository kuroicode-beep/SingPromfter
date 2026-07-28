// file: lib/widgets/prompter_drawer.dart
//
// 하단 조작판 드로어 — 손잡이(항상 보임) + 접히는 본체.
//
// 애니메이션은 SizeTransition만 쓴다. 내부적으로 Align(heightFactor) + ClipRect라
// **본체는 매 프레임 자기 온전한 높이로 레이아웃되고 부모가 보고하는 높이만
// 줄어든다.** 그래서 접히는 도중에 슬라이더가 찌그러지거나 글자가 다시
// 줄바꿈되지 않는다. 마지막 구간에 페이드를 얹어 낮은 높이에서 글자가
// 뭉개져 보이는 것도 막는다.
//
// 닫힌 상태는 IgnorePointer + ExcludeSemantics로 확실히 죽인다. v2.7.0까지
// 전체화면 바는 AnimatedOpacity(→0.2)라 **숨겨져도 자리를 먹고 클릭도 먹었다**.
//
// 손잡이는 아이콘만 두지 않는다 — 저시력 사용자에게 아이콘 하나짜리 토글은
// 못 찾는 버튼이다. 전폭 50dp에 한글 라벨을 함께 둔다.
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 드로어 색 묶음. `dark: bool` 대신 값 객체를 쓴다 —
/// 불리언 하나가 관계없는 스타일을 결정하기 시작하면 금방 엉킨다.
@immutable
class PrompterDrawerPalette {
  final Color surface;
  final Color border;
  final Color label;
  final Color icon;

  const PrompterDrawerPalette({
    required this.surface,
    required this.border,
    required this.label,
    required this.icon,
  });

  /// 메인 창 — SVIL 패널 표면.
  static const main = PrompterDrawerPalette(
    surface: AppColors.surfaceContainer,
    border: AppColors.outline,
    label: AppColors.onSurface,
    icon: AppColors.onSurfaceVariant,
  );

  /// 무대 — 가사를 방해하지 않도록 검정 위 흰 글씨.
  static const stage = PrompterDrawerPalette(
    surface: Color(0xC2000000),
    border: Colors.white24,
    label: Colors.white,
    icon: Colors.white70,
  );
}

/// 손잡이 높이. AppConstants.minTouchTarget과 같은 값이지만, 조작판을 여는
/// 유일한 입구라 다른 컨트롤이 작아지더라도 여기는 줄지 않도록 따로 둔다.
const double drawerHandleHeight = 50;

class PrompterDrawer extends StatefulWidget {
  final bool open;
  final ValueChanged<bool> onOpenChanged;

  /// 손잡이에 쓸 이름. '조작판 열기/닫기'로 조합된다.
  final String label;
  final Widget child;
  final PrompterDrawerPalette palette;

  /// 본체 높이를 고정한다. 무대는 고정해야 밴드·가사 뷰포트가 애니메이션
  /// 도중 리사이즈되지 않는다. 메인 창은 내용 높이를 그대로 쓴다(null).
  final double? fixedHeight;

  /// 애니메이션 진행도를 밖에서도 읽고 싶을 때(무대의 안정 크기 계산용).
  final ValueChanged<Animation<double>>? onAnimationReady;

  const PrompterDrawer({
    super.key,
    required this.open,
    required this.onOpenChanged,
    required this.child,
    this.label = '조작판',
    this.palette = PrompterDrawerPalette.main,
    this.fixedHeight,
    this.onAnimationReady,
  });

  @override
  State<PrompterDrawer> createState() => _PrompterDrawerState();
}

class _PrompterDrawerState extends State<PrompterDrawer>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 220);

  late final AnimationController _controller;
  late final Animation<double> _size;
  late final Animation<double> _fade;

  /// 닫히는 동안에도 클릭·시맨틱을 막기 위한 별도 플래그.
  /// ClipRect가 히트테스트를 잘라 주긴 하지만 중간 프레임을 확실히 덮는다.
  bool _interactive = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _duration,
      value: widget.open ? 1 : 0,
    );
    _size = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    // 마지막 40%에서만 나타난다 — 낮은 높이에서 글자가 뭉개지지 않게.
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.6, 1.0),
    );
    _interactive = widget.open;
    widget.onAnimationReady?.call(_size);
  }

  @override
  void didUpdateWidget(covariant PrompterDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open == widget.open) return;
    _apply();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 움직임을 줄여 달라는 시스템 설정이면 즉시 여닫는다.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.duration = Duration.zero;
    } else {
      _controller.duration = _duration;
    }
  }

  void _apply() {
    // 열 때는 먼저 살리고, 닫을 때는 먼저 죽인다 — 중간 프레임에 오작동이 없게.
    setState(() => _interactive = widget.open);
    if (widget.open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = widget.fixedHeight == null
        ? widget.child
        : SizedBox(height: widget.fixedHeight, child: widget.child);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Handle(
          open: widget.open,
          label: widget.label,
          palette: widget.palette,
          onTap: () => widget.onOpenChanged(!widget.open),
        ),
        ClipRect(
          child: SizeTransition(
            sizeFactor: _size,
            axisAlignment: -1,
            child: FadeTransition(
              opacity: _fade,
              child: IgnorePointer(
                ignoring: !_interactive,
                child: ExcludeSemantics(excluding: !_interactive, child: body),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 항상 보이는 손잡이. 텍스트 라벨을 함께 둔다(아이콘 전용 금지).
class _Handle extends StatelessWidget {
  final bool open;
  final String label;
  final PrompterDrawerPalette palette;
  final VoidCallback onTap;

  const _Handle({
    required this.open,
    required this.label,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = open ? '$label 닫기' : '$label 열기';
    return Semantics(
      button: true,
      expanded: open,
      label: text,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: drawerHandleHeight),
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: AppShapes.controlRadius,
              border: Border.all(color: palette.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                  color: palette.icon,
                ),
                const SizedBox(width: 8),
                Text(
                  text,
                  style: AppTypography.body.copyWith(color: palette.label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
