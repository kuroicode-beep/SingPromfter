// file: lib/models/timed_lyrics.dart
//
// 시간 정보가 있는 가사(LRC).
//
// 설계 메모: LRC는 자기 텍스트를 직접 들고 있다. LyricsLineUtils.splitLines는
// 빈 줄을 버리므로 그 인덱스에 타임스탬프를 얹으면 어긋난다. 아예 독립된
// 줄 목록을 갖게 해 인덱스 불일치 가능성을 없앤다.

/// 타임스탬프가 붙은 가사 한 줄.
class TimedLyricLine {
  final Duration time;
  final String text;

  const TimedLyricLine({required this.time, required this.text});
}

class TimedLyrics {
  /// 시간 오름차순으로 정렬된 줄 목록.
  final List<TimedLyricLine> lines;

  /// LRC 파일에 담긴 `[offset:]` 태그(밀리초). 양수면 가사를 늦춘다.
  final int offsetMs;

  final String? title;
  final String? artist;

  const TimedLyrics({
    required this.lines,
    this.offsetMs = 0,
    this.title,
    this.artist,
  });

  bool get isEmpty => lines.isEmpty;

  List<String> get plainLines =>
      lines.map((l) => l.text).toList(growable: false);

  /// 주어진 시각에 표시할 줄 번호를 찾는다. (이진 탐색)
  ///
  /// 첫 줄 시간보다 이르면 0을 반환한다.
  int indexAt(Duration position) {
    if (lines.isEmpty) return 0;
    final target = position.inMilliseconds - offsetMs;

    var low = 0;
    var high = lines.length - 1;
    var result = 0;

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (lines[mid].time.inMilliseconds <= target) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return result;
  }
}

/// LRC 텍스트 파서. 순수 함수라 파일 없이 테스트한다.
class LrcParser {
  LrcParser._();

  // [mm:ss.xx] / [mm:ss.xxx] / [mm:ss] — 한 줄에 여러 개 올 수 있다.
  static final RegExp _timeTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  static final RegExp _metaTag = RegExp(r'^\[(ti|ar|al|by|offset):(.*)\]$');

  static TimedLyrics parse(String raw) {
    if (raw.trim().isEmpty) return const TimedLyrics(lines: []);

    final lines = <TimedLyricLine>[];
    var offsetMs = 0;
    String? title;
    String? artist;

    for (final rawLine in raw.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final meta = _metaTag.firstMatch(line);
      if (meta != null) {
        final key = meta.group(1)!;
        final value = meta.group(2)!.trim();
        switch (key) {
          case 'ti':
            title = value;
          case 'ar':
            artist = value;
          case 'offset':
            offsetMs = int.tryParse(value) ?? 0;
        }
        continue;
      }

      final matches = _timeTag.allMatches(line).toList();
      if (matches.isEmpty) continue;

      // 마지막 태그 뒤가 가사 본문이다.
      final text = line.substring(matches.last.end).trim();
      if (text.isEmpty) continue;

      for (final match in matches) {
        final time = _toDuration(match);
        if (time == null) continue;
        lines.add(TimedLyricLine(time: time, text: text));
      }
    }

    lines.sort((a, b) => a.time.compareTo(b.time));
    return TimedLyrics(
      lines: List.unmodifiable(lines),
      offsetMs: offsetMs,
      title: title,
      artist: artist,
    );
  }

  static Duration? _toDuration(RegExpMatch match) {
    final minutes = int.tryParse(match.group(1) ?? '');
    final seconds = int.tryParse(match.group(2) ?? '');
    if (minutes == null || seconds == null) return null;

    final fractionRaw = match.group(3);
    var millis = 0;
    if (fractionRaw != null && fractionRaw.isNotEmpty) {
      // 2자리는 1/100초, 3자리는 1/1000초로 해석한다.
      final value = int.tryParse(fractionRaw) ?? 0;
      millis = fractionRaw.length == 3 ? value : value * 10;
    }
    return Duration(minutes: minutes, seconds: seconds, milliseconds: millis);
  }
}
