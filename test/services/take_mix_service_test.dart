import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/recording_take.dart';
import 'package:singpromfter_app/services/take_mix_service.dart';

void main() {
  group('mixGains — 밸런스→게인', () {
    test('0.5는 양쪽 1.0 (현행 동작 유지)', () {
      final g = mixGains(0.5);
      expect(g.acc, closeTo(1.0, 1e-9));
      expect(g.vocal, closeTo(1.0, 1e-9));
    });

    test('보컬 쪽 극단은 1.6으로 제한하고 반주는 0으로', () {
      final g = mixGains(1.0);
      expect(g.vocal, closeTo(1.6, 1e-9));
      expect(g.acc, closeTo(0.0, 1e-9));
    });

    test('범위 밖 입력은 0~1로 잘라 계산한다', () {
      expect(mixGains(-3).vocal, 0);
      expect(mixGains(9).acc, 0);
    });
  });

  group('buildAccompanimentCutArgs — 반주 조각 잘라내기', () {
    test('시작·길이를 초 단위 소수 3자리로 변환한다', () {
      final args = buildAccompanimentCutArgs(
        sourcePath: 'mr.mp3',
        outputPath: 'acc.m4a',
        startMs: 2500,
        durationMs: 61234,
      );
      expect(args[args.indexOf('-ss') + 1], '2.500');
      expect(args[args.indexOf('-t') + 1], '61.234');
      expect(args.last, 'acc.m4a');
      expect(args, containsAllInOrder(['-c:a', 'aac']));
    });

    test('음수 시작은 0으로 막는다', () {
      final args = buildAccompanimentCutArgs(
        sourcePath: 's',
        outputPath: 'o',
        startMs: -100,
        durationMs: 1000,
      );
      expect(args[args.indexOf('-ss') + 1], '0.000');
    });
  });

  group('buildMixArgs — 이펙트 체인', () {
    String filterOf(List<String> args) =>
        args[args.indexOf('-filter_complex') + 1];

    test('기본 설정은 볼륨 1.0/1.0에 이펙트 없음', () {
      final filter = filterOf(
        buildMixArgs(
          backingPath: 'a',
          vocalPath: 'b',
          outputPath: 'c',
          alignMs: 0,
        ),
      );
      expect(filter, contains('[0:a]volume=1.00[b]'));
      expect(filter, contains('adelay=0|0,volume=1.00[v]'));
      expect(filter, isNot(contains('afftdn')));
      expect(filter, isNot(contains('aecho')));
    });

    test('보컬 체인 순서: adelay → 노이즈 → 리버브 → 볼륨', () {
      final filter = filterOf(
        buildMixArgs(
          backingPath: 'a',
          vocalPath: 'b',
          outputPath: 'c',
          alignMs: 100,
          mixBalance: 0.8,
          reverbPreset: ReverbPreset.karaoke,
          noiseReduction: true,
        ),
      );
      final delayAt = filter.indexOf('adelay');
      final noiseAt = filter.indexOf('afftdn');
      final echoAt = filter.indexOf('aecho');
      final volumeAt = filter.indexOf('volume=1.60');
      expect(delayAt, lessThan(noiseAt));
      expect(noiseAt, lessThan(echoAt));
      expect(echoAt, lessThan(volumeAt));
      // 반주 게인은 (1-0.8)*2 = 0.4
      expect(filter, contains('[0:a]volume=0.40[b]'));
    });

    test('리버브 프리셋 파라미터', () {
      expect(reverbFilter(ReverbPreset.none), isNull);
      expect(reverbFilter(ReverbPreset.karaoke), 'aecho=0.8:0.85:60:0.35');
      expect(reverbFilter(ReverbPreset.hall), 'aecho=0.8:0.88:220:0.4');
      expect(reverbFilter(ReverbPreset.studio), 'aecho=0.7:0.8:40:0.25');
    });
  });

  group('buildMixArgs', () {
    test('보컬에 정렬 지연을 걸고 반주 길이에 맞춘다', () {
      final args = buildMixArgs(
        backingPath: 'mr.mp3',
        vocalPath: 'vocal.wav',
        outputPath: 'out.m4a',
        alignMs: 2500,
      );
      final filter = args[args.indexOf('-filter_complex') + 1];
      expect(filter, contains('adelay=2500|2500'));
      expect(filter, contains('duration=first'));
      expect(args.last, 'out.m4a');
      // 입력 순서: 반주(0) → 보컬(1)
      expect(args.indexOf('mr.mp3'), lessThan(args.indexOf('vocal.wav')));
    });

    test('음수 정렬값은 0으로 막는다', () {
      final args = buildMixArgs(
        backingPath: 'a',
        vocalPath: 'b',
        outputPath: 'c',
        alignMs: -300,
      );
      final filter = args[args.indexOf('-filter_complex') + 1];
      expect(filter, contains('adelay=0|0'));
    });

    test('정렬 0이면 지연 없이 섞는다', () {
      final args = buildMixArgs(
        backingPath: 'a',
        vocalPath: 'b',
        outputPath: 'c',
        alignMs: 0,
      );
      expect(args[args.indexOf('-filter_complex') + 1], contains('adelay=0|0'));
    });

    test('볼륨 정규화를 끈다 (amix 기본 감쇠 방지)', () {
      final args = buildMixArgs(
        backingPath: 'a',
        vocalPath: 'b',
        outputPath: 'c',
        alignMs: 100,
      );
      expect(args[args.indexOf('-filter_complex') + 1], contains('normalize=0'));
    });
  });
}
