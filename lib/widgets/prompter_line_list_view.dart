// file: lib/widgets/prompter_line_list_view.dart
//
// 무대 가사 줄 목록. 여러 줄을 한눈에 보여주고, 현재 줄을 표시하며,
// 줄을 누르면 그 지점으로 반주를 옮긴다.
//
// 스크롤 물리를 NeverScrollable로 두는 이유: 마우스 휠은 스크롤이 아니라
// "이전/다음 줄"로 쓰기로 했다(PrompterWheelScope). Scrollable이 포인터
// 시그널을 먼저 가져가면 조상 Listener에 휠이 도달하지 않는다.
// 프로그램적 animateTo/jumpTo는 그대로 동작한다.
import 'package:flutter/material.dart';

import '../models/prompter_lines.dart';
import '../theme/app_theme.dart';

class PrompterLineListView extends StatefulWidget {
  final PrompterLines lines;
  final int currentIndex;
  final double fontSize;
  final double lineHeight;
  final String? fontFamily;
  final bool boldText;
  final EdgeInsetsGeometry padding;
  final Color textColor;
  final Color mutedColor;

  /// 줄을 눌렀을 때. null이면 누를 수 없다.
  final ValueChanged<int>? onLineTap;

  /// 현재 줄을 화면 안으로 따라오게 할지.
  final bool autoFollow;

  final ScrollController? scrollController;

  const PrompterLineListView({
    super.key,
    required this.lines,
    required this.currentIndex,
    required this.fontSize,
    required this.lineHeight,
    this.fontFamily,
    this.boldText = false,
    this.padding = const EdgeInsets.fromLTRB(32, 48, 32, 24),
    this.textColor = Colors.white,
    this.mutedColor = Colors.white70,
    this.onLineTap,
    this.autoFollow = true,
    this.scrollController,
  });

  @override
  State<PrompterLineListView> createState() => _PrompterLineListViewState();
}

class _PrompterLineListViewState extends State<PrompterLineListView> {
  final _keys = <int, GlobalKey>{};

  @override
  void didUpdateWidget(covariant PrompterLineListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 글자 크기·줄 간격이 바뀌면 위쪽 줄들의 높이가 전부 달라지는데
    // 스크롤 오프셋은 그대로라 가사가 통째로 미끄러진다. 그게 "줄이 같이
    // 움직인다"로 보였다. 줄 번호가 안 바뀌어도 다시 잡아 준다.
    final reflowed =
        oldWidget.fontSize != widget.fontSize ||
        oldWidget.lineHeight != widget.lineHeight ||
        oldWidget.lines.length != widget.lines.length;
    if (oldWidget.currentIndex != widget.currentIndex || reflowed) {
      _followCurrent();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _followCurrent());
  }

  /// 현재 줄을 화면 위쪽 40% 지점으로 끌어온다.
  void _followCurrent() {
    if (!widget.autoFollow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _keys[widget.currentIndex]?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.4,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lines.lines;
    if (lines.isEmpty) return const SizedBox.shrink();
    final current = widget.currentIndex.clamp(0, lines.length - 1);

    return SingleChildScrollView(
      controller: widget.scrollController,
      physics: const NeverScrollableScrollPhysics(),
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < lines.length; i++)
            _LineTile(
              key: _keys.putIfAbsent(i, GlobalKey.new),
              text: lines[i].text,
              isCurrent: i == current,
              fontSize: widget.fontSize,
              lineHeight: widget.lineHeight,
              fontFamily: widget.fontFamily,
              boldText: widget.boldText,
              mutedColor: widget.mutedColor,
              onTap: widget.onLineTap == null
                  ? null
                  : () => widget.onLineTap!(i),
            ),
        ],
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  final String text;
  final bool isCurrent;
  final double fontSize;
  final double lineHeight;
  final String? fontFamily;
  final bool boldText;
  final Color mutedColor;
  final VoidCallback? onTap;

  const _LineTile({
    super.key,
    required this.text,
    required this.isCurrent,
    required this.fontSize,
    required this.lineHeight,
    required this.fontFamily,
    required this.boldText,
    required this.mutedColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 색만으로는 약하다는 피드백에 따라 v2.7.0에서 강조를 겹쳤다:
    // 두꺼운 밑줄 + 배경 띠 + 큰 화살표 + 크기 차이. 색을 못 봐도 구분된다.
    final size = isCurrent ? fontSize : fontSize * 0.72;
    final gutter = fontSize * 1.15;

    return Semantics(
      selected: isCurrent,
      button: onTap != null,
      label: isCurrent ? '현재 줄: $text' : text,
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: EdgeInsets.symmetric(vertical: fontSize * 0.12),
          padding: EdgeInsets.symmetric(vertical: fontSize * 0.1),
          decoration: isCurrent
              ? BoxDecoration(
                  color: AppColors.tertiary.withValues(alpha: 0.12),
                  border: const Border(
                    bottom: BorderSide(color: AppColors.tertiary, width: 4),
                  ),
                )
              : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 좌우 대칭 거터 — 마커가 붙고 떨어져도 본문이 밀리지 않는다.
              SizedBox(
                width: gutter,
                child: isCurrent
                    ? Icon(
                        Icons.play_arrow_rounded,
                        size: fontSize * 1.0,
                        color: AppColors.tertiary,
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: size,
                    height: lineHeight,
                    // 무대는 고가독 고딕으로 폴백한다(저시력 우선).
                    fontFamily: fontFamily ?? AppFonts.legible,
                    color: isCurrent ? AppColors.tertiary : mutedColor,
                    fontWeight: isCurrent
                        ? (boldText ? FontWeight.w800 : FontWeight.w700)
                        : FontWeight.w500,
                    shadows: isCurrent
                        ? const [
                            Shadow(color: AppColors.tertiary, blurRadius: 18),
                            Shadow(color: AppColors.tertiary, blurRadius: 8),
                          ]
                        : null,
                  ),
                ),
              ),
              SizedBox(width: gutter),
            ],
          ),
        ),
      ),
    );
  }
}
