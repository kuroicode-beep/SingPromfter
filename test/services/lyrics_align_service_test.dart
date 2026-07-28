import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/timed_lyrics.dart';
import 'package:singpromfter_app/services/lyrics_align_service.dart';

// 가사 싱크 자동 맞춤 — 보컬 = 원곡 − MR.
void main() {
  /// [onsets]에 적힌 시각마다 노래가 시작되는 가짜 포락선을 만든다.
  /// 배경 -50dB, 노래 -20dB.
  List<double> envelopeWith(List<int> onsetMs, {int lengthMs = 200000}) {
    final frames = List<double>.filled(lengthMs * alignFps ~/ 1000, -50);
    for (final ms in onsetMs) {
      final start = ms * alignFps ~/ 1000;
      // 한 줄이 3초쯤 이어진다고 본다.
      for (var i = start; i < start + alignFps * 3 && i < frames.length; i++) {
        frames[i] = -20;
      }
    }
    return frames;
  }

  group('buildVocalEnvelopeArgs', () {
    String chainOf(List<String> args) =>
        args[args.indexOf('-filter_complex') + 1];

    test('MR을 위상 반전해 섞는다 — 이게 보컬만 남기는 핵심', () {
      final chain = chainOf(
        buildVocalEnvelopeArgs(originalPath: 'a.mp3', mrPath: 'b.mp3'),
      );
      expect(chain, contains('volume=-1'));
      expect(chain, contains('amix=inputs=2:normalize=0'));
    });

    test('normalize=0이어야 한다 — 켜면 음량이 절반이 돼 상쇄가 깨진다', () {
      final chain = chainOf(
        buildVocalEnvelopeArgs(originalPath: 'a.mp3', mrPath: 'b.mp3'),
      );
      expect(chain, isNot(contains('normalize=1')));
    });

    test('사람 목소리 대역만 남긴다', () {
      final chain = chainOf(
        buildVocalEnvelopeArgs(originalPath: 'a.mp3', mrPath: 'b.mp3'),
      );
      expect(chain, contains('highpass=f=$vocalLowHz'));
      expect(chain, contains('lowpass=f=$vocalHighHz'));
    });

    test('25fps를 유지한다', () {
      final chain = chainOf(
        buildVocalEnvelopeArgs(originalPath: 'a.mp3', mrPath: 'b.mp3'),
      );
      expect(chain, contains('asetnsamples=n=1764'));
    });

    test('두 입력을 순서대로 넘긴다 — 원곡이 먼저여야 부호가 맞는다', () {
      final args = buildVocalEnvelopeArgs(
        originalPath: r'C:\음악\원곡.mp3',
        mrPath: r'C:\음악\mr.mp3',
      );
      final first = args.indexOf('-i');
      expect(args[first + 1], r'C:\음악\원곡.mp3');
      expect(args[args.lastIndexOf('-i') + 1], r'C:\음악\mr.mp3');
    });
  });

  group('detectOnset', () {
    test('노래가 시작되는 지점을 찾는다', () {
      final env = envelopeWith([40000]);
      final onset = detectOnset(env, const Duration(milliseconds: 41000));
      expect(onset, isNotNull);
      expect((onset! - const Duration(seconds: 40)).inMilliseconds.abs(),
          lessThan(100));
    });

    test('탐색 창 밖의 시작점은 잡지 않는다', () {
      final env = envelopeWith([40000]);
      // 60초 근처에는 아무 일도 없다.
      expect(detectOnset(env, const Duration(seconds: 60)), isNull);
    });

    test('계속 조용하면 null — 시작점이 없다', () {
      final env = List<double>.filled(5000, -50);
      expect(detectOnset(env, const Duration(seconds: 40)), isNull);
    });

    test('계속 노래 중이어도 null — 구분할 경계가 없다', () {
      final env = List<double>.filled(5000, -20);
      expect(detectOnset(env, const Duration(seconds: 40)), isNull);
    });

    test('빈 포락선은 null', () {
      expect(detectOnset(const [], const Duration(seconds: 10)), isNull);
    });

    test('한 프레임만 튄 것은 시작으로 보지 않는다', () {
      final env = List<double>.filled(5000, -50);
      env[1000] = -20; // 스파이크 하나
      for (var i = 2000; i < 2100; i++) {
        env[i] = -20; // 진짜 시작
      }
      final onset = detectOnset(env, const Duration(milliseconds: 80000));
      expect(onset, isNotNull);
      expect(onset!.inMilliseconds, greaterThan(70000));
    });
  });

  group('estimateLyricsOffset', () {
    /// LRC가 [lateBy]ms 늦은 상황을 만든다.
    ({List<double> env, TimedLyrics lyrics}) scenario(int lateBy) {
      const starts = [40000, 48000, 56000, 64000, 72000, 80000];
      return (
        env: envelopeWith(starts),
        lyrics: TimedLyrics(
          lines: [
            for (final s in starts)
              TimedLyricLine(
                time: Duration(milliseconds: s + lateBy),
                text: '한 줄',
              ),
          ],
        ),
      );
    }

    test('LRC가 늦은 만큼 음수 오프셋을 제안한다', () {
      final s = scenario(2000);
      final result = estimateLyricsOffset(
        envelope: s.env,
        lyrics: s.lyrics,
        leadMs: 0,
      );
      expect(result, isNotNull);
      expect(result!.offsetMs, closeTo(-2000, 120));
      expect(result.samples, 6);
    });

    test('읽을 시간만큼 더 앞당긴다', () {
      final s = scenario(2000);
      final withLead = estimateLyricsOffset(envelope: s.env, lyrics: s.lyrics)!;
      final without = estimateLyricsOffset(
        envelope: s.env,
        lyrics: s.lyrics,
        leadMs: 0,
      )!;
      expect(without.offsetMs - withLead.offsetMs, readingLeadMs);
    });

    test('이미 맞는 곡은 0 근처를 준다', () {
      final s = scenario(0);
      final result = estimateLyricsOffset(
        envelope: s.env,
        lyrics: s.lyrics,
        leadMs: 0,
      );
      expect(result!.offsetMs.abs(), lessThan(120));
    });

    test('표본이 모자라면 null — 엉뚱한 값을 밀어 넣지 않는다', () {
      final env = envelopeWith([40000]);
      const lyrics = TimedLyrics(
        lines: [TimedLyricLine(time: Duration(seconds: 40), text: '한 줄')],
      );
      expect(estimateLyricsOffset(envelope: env, lyrics: lyrics), isNull);
    });

    test('이상치 몇 줄에 끌려가지 않는다 — 중앙값을 쓰는 이유', () {
      const starts = [40000, 48000, 56000, 64000, 72000, 80000];
      // 한 줄만 엉뚱하게 30초 뒤로 적혀 있다.
      final times = [...starts.map((s) => s + 2000)];
      times[2] = 150000;
      final result = estimateLyricsOffset(
        envelope: envelopeWith(starts),
        lyrics: TimedLyrics(
          lines: [
            for (final t in times)
              TimedLyricLine(time: Duration(milliseconds: t), text: '한 줄'),
          ],
        ),
        leadMs: 0,
      );
      expect(result!.offsetMs, closeTo(-2000, 200));
    });

    test('가사가 없으면 null', () {
      expect(
        estimateLyricsOffset(
          envelope: envelopeWith([40000]),
          lyrics: const TimedLyrics(lines: []),
        ),
        isNull,
      );
    });

    test('포락선이 없으면 null', () {
      expect(
        estimateLyricsOffset(
          envelope: const [],
          lyrics: const TimedLyrics(
            lines: [TimedLyricLine(time: Duration(seconds: 1), text: 'a')],
          ),
        ),
        isNull,
      );
    });
  });
}
