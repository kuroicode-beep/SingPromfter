import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/prompter_lines.dart';
import 'package:singpromfter_app/models/timed_lyrics.dart';
import 'package:singpromfter_app/utils/lyrics_line_utils.dart';

// 무대 줄 목록 — 인덱스 어긋남을 이 함수 하나에 가둔다.
// (splitLines는 빈 줄을 버리므로 LRC 줄 목록과 섞이면 하이라이트가 밀린다)
void main() {
  const synced = TimedLyrics(
    lines: [
      TimedLyricLine(time: Duration.zero, text: '싱크 첫 줄'),
      TimedLyricLine(time: Duration(seconds: 5), text: '싱크 둘째 줄'),
    ],
  );

  test('싱크 가사가 있으면 그 줄 목록과 시각을 쓴다', () {
    final lines = buildPrompterLines(
      lyricsText: '일반 첫 줄\n일반 둘째 줄\n일반 셋째 줄',
      timedLyrics: synced,
    );

    expect(lines.length, 2);
    expect(lines.texts, ['싱크 첫 줄', '싱크 둘째 줄']);
    expect(lines.seekable, isTrue);
    expect(lines.lines[1].time, const Duration(seconds: 5));
  });

  test('싱크 가사가 없으면 일반 가사를 줄로 나눈다', () {
    final lines = buildPrompterLines(lyricsText: '첫 줄\n둘째 줄');

    expect(lines.texts, ['첫 줄', '둘째 줄']);
    expect(lines.seekable, isFalse);
    expect(lines.lines.first.time, isNull);
  });

  test('빈 싱크 가사는 일반 가사로 넘어간다', () {
    final lines = buildPrompterLines(
      lyricsText: '첫 줄',
      timedLyrics: const TimedLyrics(lines: []),
    );

    expect(lines.texts, ['첫 줄']);
    expect(lines.seekable, isFalse);
  });

  test('빈 줄은 버린다 — splitLines와 같은 규칙', () {
    final lines = buildPrompterLines(lyricsText: '첫 줄\n\n\n둘째 줄\n');
    expect(lines.texts, ['첫 줄', '둘째 줄']);
  });

  test('가사가 없으면 안내 한 줄', () {
    final lines = buildPrompterLines(lyricsText: '');
    expect(lines.length, 1);
    expect(lines.texts.first, LyricsLineUtils.emptyPlaceholder);
    expect(lines.seekable, isFalse);
  });

  // 줄 끝 시각 — 한 글자씩 스윕이 이 값 없이는 돌 수 없다.
  group('줄 끝 시각', () {
    test('다음 줄 시작이 이 줄의 끝이다', () {
      final lines = buildPrompterLines(lyricsText: '', timedLyrics: synced);
      expect(lines.lines[0].end, const Duration(seconds: 5));
    });

    test('마지막 줄은 trackEnd로 끝을 잡는다', () {
      final lines = buildPrompterLines(
        lyricsText: '',
        timedLyrics: synced,
        trackEnd: const Duration(seconds: 200),
      );
      expect(lines.lines.last.end, const Duration(seconds: 200));
    });

    test('trackEnd가 없으면 마지막 줄의 끝은 모른다', () {
      final lines = buildPrompterLines(lyricsText: '', timedLyrics: synced);
      expect(lines.lines.last.end, isNull);
    });

    test('싱크 가사가 없으면 시각도 끝도 없다', () {
      final lines = buildPrompterLines(
        lyricsText: '첫 줄\n둘째 줄',
        trackEnd: const Duration(seconds: 200),
      );
      expect(lines.lines.every((l) => l.time == null && l.end == null), isTrue);
    });
  });
}
