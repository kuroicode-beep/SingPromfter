import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/timed_lyrics.dart';
import 'package:singpromfter_app/services/lyrics_sync_math.dart';

// 오프셋 부호 규약을 고정한다.
// v2.5.0까지 컨트롤러가 오프셋을 더하고 TimedLyrics.indexAt은 빼서,
// "음수 = 가사 먼저"라는 UI 약속과 반대로 가사가 늦게 떴다.
void main() {
  TimedLyrics lyrics({int offsetMs = 0}) => TimedLyrics(
    lines: const [
      TimedLyricLine(time: Duration.zero, text: '첫 줄'),
      TimedLyricLine(time: Duration(seconds: 10), text: '둘째 줄'),
      TimedLyricLine(time: Duration(seconds: 20), text: '셋째 줄'),
      TimedLyricLine(time: Duration(seconds: 30), text: '넷째 줄'),
    ],
    offsetMs: offsetMs,
  );

  group('songTimeFor', () {
    test('오프셋이 0이면 재생 위치 그대로', () {
      expect(
        LyricsSyncMath.songTimeFor(
          playerPosition: const Duration(seconds: 12),
        ),
        const Duration(seconds: 12),
      );
    });

    test('음수 오프셋 = 가사 먼저 → 곡 시각이 앞선다', () {
      final t = LyricsSyncMath.songTimeFor(
        playerPosition: const Duration(seconds: 12),
        lyricsOffsetMs: -1000,
      );
      expect(t, const Duration(seconds: 13));
    });

    test('양수 오프셋 = 가사 늦게 → 곡 시각이 뒤진다', () {
      final t = LyricsSyncMath.songTimeFor(
        playerPosition: const Duration(seconds: 12),
        lyricsOffsetMs: 1000,
      );
      expect(t, const Duration(seconds: 11));
    });

    test('트림 시작점을 뺀다', () {
      expect(
        LyricsSyncMath.songTimeFor(
          playerPosition: const Duration(seconds: 12),
          trackStartMs: 5000,
        ),
        const Duration(seconds: 7),
      );
    });

    test('음수로 내려가지 않는다', () {
      expect(
        LyricsSyncMath.songTimeFor(
          playerPosition: const Duration(seconds: 1),
          trackStartMs: 5000,
        ),
        Duration.zero,
      );
    });
  });

  group('playerPositionForLine ↔ indexAt 왕복', () {
    test('오프셋·트림이 없을 때', () {
      final l = lyrics();
      for (var i = 0; i < l.lines.length; i++) {
        final pos = LyricsSyncMath.playerPositionForLine(lyrics: l, index: i);
        final back = l.indexAt(
          LyricsSyncMath.songTimeFor(playerPosition: pos),
        );
        expect(back, i, reason: '줄 $i');
      }
    });

    test('가사 선행 오프셋 + 트림이 있어도 같은 줄로 돌아온다', () {
      final l = lyrics();
      const startMs = 3000;
      const offsetMs = -1500;
      for (var i = 0; i < l.lines.length; i++) {
        final pos = LyricsSyncMath.playerPositionForLine(
          lyrics: l,
          index: i,
          trackStartMs: startMs,
          lyricsOffsetMs: offsetMs,
        );
        final back = l.indexAt(
          LyricsSyncMath.songTimeFor(
            playerPosition: pos,
            trackStartMs: startMs,
            lyricsOffsetMs: offsetMs,
          ),
        );
        expect(back, i, reason: '줄 $i');
      }
    });

    test('LRC 자체 오프셋 태그가 있어도 왕복한다', () {
      final l = lyrics(offsetMs: -800);
      for (var i = 0; i < l.lines.length; i++) {
        final pos = LyricsSyncMath.playerPositionForLine(lyrics: l, index: i);
        final back = l.indexAt(
          LyricsSyncMath.songTimeFor(playerPosition: pos),
        );
        expect(back, i, reason: '줄 $i');
      }
    });

    test('범위 밖 인덱스는 양끝으로 잘린다', () {
      final l = lyrics();
      expect(
        LyricsSyncMath.playerPositionForLine(lyrics: l, index: -5),
        Duration.zero,
      );
      expect(
        LyricsSyncMath.playerPositionForLine(lyrics: l, index: 99),
        const Duration(seconds: 30),
      );
    });
  });

  group('clampToTrim', () {
    test('시작 지점보다 앞으로 가지 않는다', () {
      expect(
        LyricsSyncMath.clampToTrim(
          const Duration(seconds: 2),
          startMs: 5000,
        ),
        const Duration(seconds: 5),
      );
    });

    test('끝 지점을 넘지 않는다', () {
      expect(
        LyricsSyncMath.clampToTrim(
          const Duration(seconds: 90),
          endMs: 60000,
        ),
        const Duration(seconds: 60),
      );
    });

    test('곡 길이를 넘지 않는다', () {
      expect(
        LyricsSyncMath.clampToTrim(
          const Duration(seconds: 90),
          duration: const Duration(seconds: 70),
        ),
        const Duration(seconds: 70),
      );
    });

    test('끝 지점과 곡 길이 중 더 이른 쪽을 쓴다', () {
      expect(
        LyricsSyncMath.clampToTrim(
          const Duration(seconds: 90),
          endMs: 50000,
          duration: const Duration(seconds: 70),
        ),
        const Duration(seconds: 50),
      );
    });

    test('상한이 하한보다 작은 뒤집힌 설정에서는 하한을 지킨다', () {
      expect(
        LyricsSyncMath.clampToTrim(
          const Duration(seconds: 30),
          startMs: 40000,
          endMs: 10000,
        ),
        const Duration(seconds: 40),
      );
    });

    test('제한이 없으면 그대로', () {
      expect(
        LyricsSyncMath.clampToTrim(const Duration(seconds: 30)),
        const Duration(seconds: 30),
      );
    });
  });

  // 줄 안 진행률 — 한 글자씩 스윕이 이 위에 올라간다.
  group('lyricsTimeFor', () {
    const lyrics = TimedLyrics(
      lines: [TimedLyricLine(time: Duration(seconds: 10), text: '가')],
      offsetMs: 400,
    );

    test('LRC 파일 자체 오프셋까지 뺀다 — songTimeFor는 빼지 않는다', () {
      const position = Duration(seconds: 10);
      final lyricsTime = LyricsSyncMath.lyricsTimeFor(
        playerPosition: position,
        lyrics: lyrics,
      );
      final songTime = LyricsSyncMath.songTimeFor(playerPosition: position);

      expect(lyricsTime, const Duration(milliseconds: 9600));
      expect(songTime, const Duration(seconds: 10));
      expect(songTime - lyricsTime, const Duration(milliseconds: 400));
    });

    test('트림 시작과 사용자 오프셋도 함께 뺀다', () {
      expect(
        LyricsSyncMath.lyricsTimeFor(
          playerPosition: const Duration(seconds: 30),
          lyrics: lyrics,
          trackStartMs: 5000,
          lyricsOffsetMs: -1000,
        ),
        const Duration(milliseconds: 25600),
      );
    });

    test('인트로를 구분해야 하므로 음수를 0으로 막지 않는다', () {
      final t = LyricsSyncMath.lyricsTimeFor(
        playerPosition: Duration.zero,
        lyrics: lyrics,
      );
      expect(t.isNegative, isTrue);
    });
  });

  group('lineProgress', () {
    const start = Duration(seconds: 10);
    const end = Duration(seconds: 14);

    test('줄 시작 전이면 null — 인트로 내내 첫 줄을 훑지 않게', () {
      expect(
        LyricsSyncMath.lineProgress(
          lyricsTime: const Duration(seconds: 9),
          start: start,
          end: end,
        ),
        isNull,
      );
    });

    test('줄 시작에서 0', () {
      expect(
        LyricsSyncMath.lineProgress(lyricsTime: start, start: start, end: end),
        0.0,
      );
    });

    test('중간에서 0.5', () {
      expect(
        LyricsSyncMath.lineProgress(
          lyricsTime: const Duration(seconds: 12),
          start: start,
          end: end,
        ),
        closeTo(0.5, 1e-9),
      );
    });

    test('끝을 지나면 1을 넘지 않는다', () {
      expect(
        LyricsSyncMath.lineProgress(
          lyricsTime: const Duration(seconds: 20),
          start: start,
          end: end,
        ),
        1.0,
      );
    });

    test('끝을 모르면 null — 지어낸 끝점으로 스윕하지 않는다', () {
      expect(
        LyricsSyncMath.lineProgress(lyricsTime: start, start: start),
        isNull,
      );
    });

    test('끝이 시작보다 이른 깨진 LRC면 null', () {
      expect(
        LyricsSyncMath.lineProgress(
          lyricsTime: start,
          start: start,
          end: const Duration(seconds: 5),
        ),
        isNull,
      );
    });

    test('maxSweep이 있으면 그 구간 안에서 다 훑는다', () {
      // 4초짜리 줄이지만 1초 만에 끝까지 훑고 대기한다.
      expect(
        LyricsSyncMath.lineProgress(
          lyricsTime: const Duration(seconds: 11),
          start: start,
          end: end,
          maxSweep: const Duration(seconds: 1),
        ),
        1.0,
      );
      expect(
        LyricsSyncMath.lineProgress(
          lyricsTime: const Duration(milliseconds: 10500),
          start: start,
          end: end,
          maxSweep: const Duration(seconds: 1),
        ),
        closeTo(0.5, 1e-9),
      );
    });
  });

  group('sweepWindow', () {
    test('짧은 줄은 최소 시간을 지킨다', () {
      expect(
        LyricsSyncMath.sweepWindow('가', const Duration(seconds: 30)),
        const Duration(seconds: 2),
      );
    });

    test('글자 수에 비례한다', () {
      expect(
        LyricsSyncMath.sweepWindow('가나다라마바', const Duration(seconds: 30)),
        const Duration(milliseconds: 4200),
      );
    });

    test('간주처럼 긴 구간은 상한에서 잘린다', () {
      expect(
        LyricsSyncMath.sweepWindow(
          '가나다라마바사아자차카타파하가나다라마바사아',
          const Duration(seconds: 40),
        ),
        const Duration(seconds: 12),
      );
    });

    test('줄 길이보다 길게 잡지 않는다', () {
      expect(
        LyricsSyncMath.sweepWindow('가나다라마바', const Duration(seconds: 1)),
        const Duration(seconds: 1),
      );
    });

    test('구간이 0이면 0', () {
      expect(LyricsSyncMath.sweepWindow('가나다', Duration.zero), Duration.zero);
    });
  });
}
