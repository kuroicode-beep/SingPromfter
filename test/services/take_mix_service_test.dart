import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/services/take_mix_service.dart';

void main() {
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

  group('buildDuetMixArgs', () {
    test('반주 + 두 보컬을 각자 지연으로 얹고 반주 길이에 맞춘다', () {
      final args = buildDuetMixArgs(
        backingPath: 'mr.mp3',
        vocalAPath: 'male.wav',
        vocalBPath: 'female.wav',
        outputPath: 'duet.m4a',
        alignAMs: 1200,
        alignBMs: 3400,
      );
      final filter = args[args.indexOf('-filter_complex') + 1];
      expect(filter, contains('adelay=1200|1200'));
      expect(filter, contains('adelay=3400|3400'));
      expect(filter, contains('amix=inputs=3'));
      expect(filter, contains('duration=first'));
      expect(filter, contains('normalize=0'));
      // 입력 순서: 반주(0) → 남(1) → 여(2)
      expect(args.indexOf('mr.mp3'), lessThan(args.indexOf('male.wav')));
      expect(args.indexOf('male.wav'), lessThan(args.indexOf('female.wav')));
      expect(args.last, 'duet.m4a');
    });

    test('반주가 없으면 보컬 둘만 긴 쪽 길이로 겹친다', () {
      final args = buildDuetMixArgs(
        backingPath: null,
        vocalAPath: 'a.wav',
        vocalBPath: 'b.wav',
        outputPath: 'c.m4a',
        alignAMs: -100,
        alignBMs: 0,
      );
      final filter = args[args.indexOf('-filter_complex') + 1];
      expect(filter, contains('amix=inputs=2'));
      expect(filter, contains('duration=longest'));
      expect(filter, contains('adelay=0|0'));
      expect(args, isNot(contains('mr.mp3')));
    });
  });
}
