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

  /// 다음 줄이 시작되는 시각 = 이 줄이 끝나는 시각.
  /// 마지막 줄은 곡 끝을 알 때만 채워진다. 모르면 null이고 스윕하지 않는다 —
  /// 끝점을 지어낸 스윕은 없느니만 못하다.
  final Duration? end;

  const PrompterLine({required this.text, this.time, this.end});
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
///
/// [trackEnd]는 **마지막 줄의 끝**을 정하는 데만 쓴다(트림 끝 또는 곡 길이,
/// 가사와 같은 원본 시간축). 주지 않으면 마지막 줄은 끝을 모르는 채로 둔다.
PrompterLines buildPrompterLines({
  required String lyricsText,
  TimedLyrics? timedLyrics,
  Duration? trackEnd,
}) {
  final synced = timedLyrics;
  if (synced != null && !synced.isEmpty) {
    final source = synced.lines;
    return PrompterLines(
      lines: [
        for (var i = 0; i < source.length; i++)
          PrompterLine(
            text: source[i].text,
            time: source[i].time,
            end: i + 1 < source.length ? source[i + 1].time : trackEnd,
          ),
      ],
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
