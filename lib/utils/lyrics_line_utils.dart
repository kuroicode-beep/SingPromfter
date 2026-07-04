// file: lib/utils/lyrics_line_utils.dart
//
// 가사 텍스트를 줄 단위로 분리한다.
class LyricsLineUtils {
  LyricsLineUtils._();

  static List<String> splitLines(String lyrics) {
    final trimmed = lyrics.trim();
    if (trimmed.isEmpty) {
      return const ['(가사가 없습니다)'];
    }
    return lyrics
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trimRight())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }
}
