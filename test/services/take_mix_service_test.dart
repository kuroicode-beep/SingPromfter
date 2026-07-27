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
}
