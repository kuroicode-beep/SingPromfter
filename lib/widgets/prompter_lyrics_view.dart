// file: lib/widgets/prompter_lyrics_view.dart
//
// 무대 가사 표시. 기본은 줄 목록이고, '줄 하이라이트' 모드만 3줄 창이다.
//
// v2.6.0 이전의 '전체 가사' 모드는 가사 전체를 하나의 Text로 그려서
// 줄별 표시·클릭·휠 이동이 원천적으로 불가능했다. 줄 단위 위젯으로 바꾸고
// 줄 목록 생성은 buildPrompterLines 한 곳에 맡긴다(인덱스 어긋남 방지).
import 'package:flutter/material.dart';

import '../models/prompter_display_mode.dart';
import '../models/prompter_lines.dart';
import '../models/timed_lyrics.dart';
import '../theme/app_theme.dart';
import 'prompter_line_list_view.dart';

class PrompterLyricsView extends StatelessWidget {
  final String lyricsText;

  /// 싱크 가사. 있으면 이 줄 목록과 타임스탬프를 쓴다.
  final TimedLyrics? timedLyrics;
  final PrompterDisplayMode displayMode;
  final double fontSize;
  final double lineHeight;
  final String? fontFamily;
  final bool boldText;
  final int highlightLineIndex;
  final ScrollController? scrollController;
  final EdgeInsetsGeometry padding;
  final Color textColor;
  final Color mutedColor;

  /// 줄을 눌렀을 때. null이면 누를 수 없다.
  final ValueChanged<int>? onLineTap;

  /// 현재 줄을 화면 안으로 따라오게 할지.
  final bool autoFollow;

  const PrompterLyricsView({
    super.key,
    required this.lyricsText,
    this.timedLyrics,
    required this.displayMode,
    required this.fontSize,
    required this.lineHeight,
    this.fontFamily,
    this.boldText = false,
    this.highlightLineIndex = 0,
    this.scrollController,
    this.padding = const EdgeInsets.fromLTRB(18, 10, 18, 18),
    this.textColor = AppColors.onSurface,
    this.mutedColor = AppColors.onSurfaceVariant,
    this.onLineTap,
    this.autoFollow = true,
  });

  PrompterLines get _lines =>
      buildPrompterLines(lyricsText: lyricsText, timedLyrics: timedLyrics);

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    if (displayMode.usesWindowedLayout) {
      return _buildHighlightView(lines);
    }
    return PrompterLineListView(
      lines: lines,
      currentIndex: highlightLineIndex,
      fontSize: fontSize,
      lineHeight: lineHeight,
      fontFamily: fontFamily,
      boldText: boldText,
      padding: padding is EdgeInsets
          ? padding as EdgeInsets
          : const EdgeInsets.fromLTRB(32, 48, 32, 24),
      textColor: textColor,
      mutedColor: mutedColor,
      onLineTap: onLineTap,
      autoFollow: autoFollow,
      scrollController: scrollController,
    );
  }

  /// 3줄 창 — 글자를 가장 크게 보고 싶을 때 쓰는 집중 모드.
  Widget _buildHighlightView(PrompterLines lines) {
    if (lines.isEmpty) {
      return Center(child: Text('(가사가 없습니다)', style: _baseStyle(fontSize)));
    }
    final texts = lines.texts;
    final current = highlightLineIndex.clamp(0, texts.length - 1);

    return Padding(
      padding: padding,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (current > 0)
            _highlightLine(texts[current - 1], current - 1, muted: true),
          const SizedBox(height: 12),
          _highlightLine(texts[current], current, muted: false),
          const SizedBox(height: 12),
          if (current < texts.length - 1)
            _highlightLine(texts[current + 1], current + 1, muted: true),
        ],
      ),
    );
  }

  Widget _highlightLine(String text, int index, {required bool muted}) {
    final size = muted ? fontSize * 0.82 : fontSize;
    final gutter = fontSize * 1.15;
    // 줄 목록 모드와 같은 강조 규칙(밑줄·배경·큰 화살표)을 쓴다.
    final child = Container(
      padding: EdgeInsets.symmetric(vertical: fontSize * 0.1),
      decoration: muted
          ? null
          : BoxDecoration(
              color: AppColors.tertiary.withValues(alpha: 0.12),
              border: const Border(
                bottom: BorderSide(color: AppColors.tertiary, width: 4),
              ),
            ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: gutter,
            child: muted
                ? null
                : Icon(
                    Icons.play_arrow_rounded,
                    size: fontSize * 1.0,
                    color: AppColors.tertiary,
                  ),
          ),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: _baseStyle(size).copyWith(
                color: muted ? mutedColor : AppColors.tertiary,
                fontWeight: muted
                    ? FontWeight.w500
                    : (boldText ? FontWeight.w800 : FontWeight.w700),
                shadows: muted
                    ? null
                    : const [
                        Shadow(color: AppColors.tertiary, blurRadius: 18),
                        Shadow(color: AppColors.tertiary, blurRadius: 8),
                      ],
              ),
            ),
          ),
          SizedBox(width: gutter),
        ],
      ),
    );

    if (onLineTap == null) return child;
    return Semantics(
      selected: !muted,
      button: true,
      label: muted ? text : '현재 줄: $text',
      child: InkWell(onTap: () => onLineTap!(index), child: child),
    );
  }

  TextStyle _baseStyle(double size) {
    // 무대 가사는 고가독이 최우선. 글꼴 미지정 시 손글씨(브랜드) 대신
    // 고딕(Malgun)으로 폴백해 저시력 가독성을 지킨다.
    return TextStyle(
      color: textColor,
      fontSize: size,
      height: lineHeight,
      fontFamily: fontFamily ?? AppFonts.legible,
      fontWeight: boldText ? FontWeight.w800 : FontWeight.w500,
    );
  }
}
