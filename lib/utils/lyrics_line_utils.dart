// file: lib/utils/lyrics_line_utils.dart
//
// 가사 텍스트를 줄 단위로 분리한다.

/// 원본 텍스트의 줄 번호를 함께 들고 있는 가사 한 줄.
class IndexedLyricLine {
  /// 원본 텍스트에서의 0-based 줄 번호(빈 줄 포함해 센 값).
  final int sourceIndex;
  final String text;

  const IndexedLyricLine({required this.sourceIndex, required this.text});
}

class LyricsLineUtils {
  LyricsLineUtils._();

  static const String emptyPlaceholder = '(가사가 없습니다)';

  /// 빈 줄을 제거한 표시용 줄 목록.
  ///
  /// 주의: 빈 줄이 빠지므로 여기서 얻은 인덱스는 원본 텍스트의 줄 번호와
  /// 일치하지 않는다. 원본 줄 번호가 필요하면 [splitLinesIndexed]를 쓴다.
  static List<String> splitLines(String lyrics) {
    final trimmed = lyrics.trim();
    if (trimmed.isEmpty) {
      return const [emptyPlaceholder];
    }
    return lyrics
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trimRight())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  /// [splitLines]와 같은 줄을 반환하되 원본 줄 번호를 함께 준다.
  ///
  /// 가사 타이밍(LRC)을 원본 텍스트 위치에 되쓰는 작업에서 쓴다.
  static List<IndexedLyricLine> splitLinesIndexed(String lyrics) {
    final trimmed = lyrics.trim();
    if (trimmed.isEmpty) {
      return const [IndexedLyricLine(sourceIndex: 0, text: emptyPlaceholder)];
    }

    final rawLines = lyrics.split(RegExp(r'\r?\n'));
    final result = <IndexedLyricLine>[];
    for (var i = 0; i < rawLines.length; i++) {
      final text = rawLines[i].trimRight();
      if (text.isEmpty) continue;
      result.add(IndexedLyricLine(sourceIndex: i, text: text));
    }
    return List.unmodifiable(result);
  }
}
