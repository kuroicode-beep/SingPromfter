// file: lib/models/prompter_lines.dart
//
// 무대에 그릴 가사 줄 목록. 순수 함수로 만든다.
//
// 줄 목록이 두 곳(LRC의 plainLines vs splitLines)에서 따로 만들어지면
// 인덱스가 어긋난다 — splitLines는 빈 줄을 버리기 때문이다. 그 위험을
// 이 파일 하나에 가둬 두고, 화면과 컨트롤러가 같은 목록을 보게 한다.
import '../models/timed_lyrics.dart';
import '../utils/lyrics_line_utils.dart';

class PrompterLine {
  final String text;

  /// 이 줄이 시작되는 곡 시각. 싱크 가사가 없으면 null.
  final Duration? time;

  const PrompterLine({required this.text, this.time});
}

class PrompterLines {
  final List<PrompterLine> lines;

  /// 줄을 눌렀을 때 반주를 그 지점으로 옮길 수 있는지(= LRC가 있는지).
  final bool seekable;

  const PrompterLines({required this.lines, required this.seekable});

  bool get isEmpty => lines.isEmpty;
  int get length => lines.length;

  List<String> get texts =>
      lines.map((l) => l.text).toList(growable: false);
}

/// 무대에 그릴 줄 목록을 만든다.
///
/// 싱크 가사가 있으면 그 줄 목록을 그대로 쓴다(시각 포함). 없으면 일반
/// 가사를 줄 단위로 나눈다. 가사가 아예 없으면 안내 한 줄을 돌려준다.
PrompterLines buildPrompterLines({
  required String lyricsText,
  TimedLyrics? timedLyrics,
}) {
  final synced = timedLyrics;
  if (synced != null && !synced.isEmpty) {
    return PrompterLines(
      lines: synced.lines
          .map((l) => PrompterLine(text: l.text, time: l.time))
          .toList(growable: false),
      seekable: true,
    );
  }

  final plain = LyricsLineUtils.splitLines(lyricsText);
  if (plain.isEmpty) {
    return const PrompterLines(
      lines: [PrompterLine(text: LyricsLineUtils.emptyPlaceholder)],
      seekable: false,
    );
  }
  return PrompterLines(
    lines: plain.map((t) => PrompterLine(text: t)).toList(growable: false),
    seekable: false,
  );
}
