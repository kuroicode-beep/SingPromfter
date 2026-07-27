// file: lib/widgets/prompter_lyrics_view.dart
//
// 전체 스크롤·하이라이트 3줄 모드 가사 표시.
import 'package:flutter/material.dart';

import '../models/prompter_display_mode.dart';
import '../models/timed_lyrics.dart';
import '../theme/app_theme.dart';
import '../utils/lyrics_line_utils.dart';

class PrompterLyricsView extends StatelessWidget {
  final String lyricsText;

  /// 싱크 가사. timed 모드일 때 이 줄 목록을 그린다.
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
  });

  @override
  Widget build(BuildContext context) {
    if (displayMode.usesWindowedLayout) {
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
    // timed 모드에서는 LRC가 자기 줄 목록을 들고 있으므로 그대로 쓴다.
    // (splitLines는 빈 줄을 버려 인덱스가 어긋날 수 있어 섞지 않는다)
    final synced = timedLyrics;
    final lines = displayMode == PrompterDisplayMode.timed &&
            synced != null &&
            !synced.isEmpty
        ? synced.plainLines
        : LyricsLineUtils.splitLines(lyricsText);
    if (lines.isEmpty) {
      return Center(
        child: Text(
          LyricsLineUtils.emptyPlaceholder,
          style: _baseStyle(fontSize),
        ),
      );
    }
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
