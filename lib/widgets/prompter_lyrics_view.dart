// file: lib/widgets/prompter_lyrics_view.dart
//
// 무대 가사 표시. 기본은 줄 목록이고, '줄 하이라이트' 모드만 3줄 창이다.
//
// v2.6.0 이전의 '전체 가사' 모드는 가사 전체를 하나의 Text로 그려서
// 줄별 표시·클릭·휠 이동이 원천적으로 불가능했다. 줄 단위 위젯으로 바꾸고
// 줄 목록 생성은 buildPrompterLines 한 곳에 맡긴다(인덱스 어긋남 방지).
//
// 줄 목록을 State에 캐시하는 이유: 예전에는 build마다 다시 만드는 getter라
// 리빌드가 잦아지면 그대로 비용이 됐다. 가사·싱크·끝 시각이 바뀔 때만 만든다.
import 'package:flutter/material.dart';

import '../models/prompter_display_mode.dart';
import '../models/prompter_lines.dart';
import '../models/timed_lyrics.dart';
import '../theme/app_theme.dart';
import 'prompter_current_line.dart';
import 'prompter_line_list_view.dart';

class PrompterLyricsView extends StatefulWidget {
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

  /// 마지막 줄의 끝을 정하는 곡 끝(가사와 같은 원본 시간축).
  /// 모르면 마지막 줄은 스윕하지 않는다.
  final Duration? trackEnd;

  /// 현재 줄을 한 글자씩 밝히는 렌더러. null이면 평범한 Text.
  final Widget Function(PrompterLine line, TextStyle style)? sweepBuilder;

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
    this.trackEnd,
    this.sweepBuilder,
  });

  @override
  State<PrompterLyricsView> createState() => _PrompterLyricsViewState();
}

class _PrompterLyricsViewState extends State<PrompterLyricsView> {
  late PrompterLines _lines;

  @override
  void initState() {
    super.initState();
    _lines = _build();
  }

  @override
  void didUpdateWidget(covariant PrompterLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyricsText != widget.lyricsText ||
        !identical(oldWidget.timedLyrics, widget.timedLyrics) ||
        oldWidget.trackEnd != widget.trackEnd) {
      _lines = _build();
    }
  }

  PrompterLines _build() => buildPrompterLines(
    lyricsText: widget.lyricsText,
    timedLyrics: widget.timedLyrics,
    trackEnd: widget.trackEnd,
  );

  @override
  Widget build(BuildContext context) {
    if (widget.displayMode.usesWindowedLayout) {
      return _buildHighlightView(_lines);
    }
    return PrompterLineListView(
      lines: _lines,
      currentIndex: widget.highlightLineIndex,
      fontSize: widget.fontSize,
      lineHeight: widget.lineHeight,
      fontFamily: widget.fontFamily,
      boldText: widget.boldText,
      padding: widget.padding is EdgeInsets
          ? widget.padding as EdgeInsets
          : const EdgeInsets.fromLTRB(32, 48, 32, 24),
      textColor: widget.textColor,
      mutedColor: widget.mutedColor,
      onLineTap: widget.onLineTap,
      autoFollow: widget.autoFollow,
      sweepBuilder: widget.sweepBuilder,
      scrollController: widget.scrollController,
    );
  }

  /// 3줄 창 — 글자를 가장 크게 보고 싶을 때 쓰는 집중 모드.
  Widget _buildHighlightView(PrompterLines lines) {
    if (lines.isEmpty) {
      return Center(
        child: Text(
          '(가사가 없습니다)',
          style: prompterLineStyle(
            fontSize: widget.fontSize,
            lineHeight: widget.lineHeight,
            boldText: widget.boldText,
            isCurrent: false,
            mutedColor: widget.mutedColor,
            fontFamily: widget.fontFamily,
          ),
        ),
      );
    }
    final texts = lines.texts;
    final current = widget.highlightLineIndex.clamp(0, texts.length - 1);

    return Padding(
      padding: widget.padding,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (current > 0) _line(texts[current - 1], current - 1, false),
          const SizedBox(height: 12),
          _line(texts[current], current, true),
          const SizedBox(height: 12),
          if (current < texts.length - 1)
            _line(texts[current + 1], current + 1, false),
        ],
      ),
    );
  }

  /// 3줄 창의 한 줄. 목록 모드와 같은 위젯이라 강조 규칙이 갈라지지 않는다.
  Widget _line(String text, int index, bool isCurrent) {
    return PrompterCurrentLine(
      text: text,
      isCurrent: isCurrent,
      fontSize: widget.fontSize,
      mutedScale: windowMutedScale,
      lineHeight: widget.lineHeight,
      fontFamily: widget.fontFamily,
      boldText: widget.boldText,
      mutedColor: widget.mutedColor,
      fillWidth: false,
      sweepBuilder: widget.sweepBuilder == null || !isCurrent
          ? null
          : (style) => widget.sweepBuilder!(_lines.lines[index], style),
      onTap: widget.onLineTap == null ? null : () => widget.onLineTap!(index),
    );
  }
}
