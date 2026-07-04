// file: lib/widgets/prompter_lyrics_view.dart
//
// 전체 스크롤·하이라이트 3줄 모드 가사 표시.
import 'package:flutter/material.dart';

import '../models/prompter_display_mode.dart';
import '../theme/app_theme.dart';
import '../utils/lyrics_line_utils.dart';

class PrompterLyricsView extends StatelessWidget {
  final String lyricsText;
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

  const PrompterLyricsView({
    super.key,
    required this.lyricsText,
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
  });

  @override
  Widget build(BuildContext context) {
    if (displayMode == PrompterDisplayMode.highlight) {
      return _buildHighlightView();
    }
    return _buildFullView();
  }

  Widget _buildFullView() {
    return SingleChildScrollView(
      controller: scrollController,
      padding: padding,
      child: Center(
        child: Text(
          lyricsText.isEmpty ? '(가사가 없습니다)' : lyricsText,
          textAlign: TextAlign.center,
          style: _baseStyle(fontSize),
        ),
      ),
    );
  }

  Widget _buildHighlightView() {
    final lines = LyricsLineUtils.splitLines(lyricsText);
    final current = highlightLineIndex.clamp(0, lines.length - 1);

    return Padding(
      padding: padding,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (current > 0)
            _highlightLine(
              lines[current - 1],
              fontSize * 0.82,
              mutedColor,
              FontWeight.w500,
            ),
          const SizedBox(height: 12),
          _highlightLine(
            lines[current],
            fontSize,
            textColor,
            boldText ? FontWeight.w800 : FontWeight.w700,
            glow: true,
          ),
          const SizedBox(height: 12),
          if (current < lines.length - 1)
            _highlightLine(
              lines[current + 1],
              fontSize * 0.82,
              mutedColor,
              FontWeight.w500,
            ),
        ],
      ),
    );
  }

  Widget _highlightLine(
    String text,
    double size,
    Color color,
    FontWeight weight, {
    bool glow = false,
  }) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: _baseStyle(size).copyWith(
        color: color,
        fontWeight: weight,
        shadows: glow
            ? const [
                Shadow(color: AppColors.primary, blurRadius: 18),
                Shadow(color: AppColors.primary, blurRadius: 8),
              ]
            : null,
      ),
    );
  }

  TextStyle _baseStyle(double size) {
    return TextStyle(
      color: textColor,
      fontSize: size,
      height: lineHeight,
      fontFamily: fontFamily,
      fontWeight: boldText ? FontWeight.w800 : FontWeight.w500,
    );
  }
}
