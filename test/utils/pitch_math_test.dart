import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/utils/pitch_math.dart';

void main() {
  group('semitonesToRatio', () {
    test('원키는 비율 1', () {
      expect(semitonesToRatio(0), 1.0);
    });

    test('한 옥타브 위/아래는 2배·절반', () {
      expect(semitonesToRatio(12), closeTo(2.0, 1e-9));
      expect(semitonesToRatio(-12), closeTo(0.5, 1e-9));
    });

    test('+2 반음은 약 1.1225', () {
      expect(semitonesToRatio(2), closeTo(1.122462, 1e-6));
    });

    test('올리면 커지고 내리면 작아진다', () {
      expect(semitonesToRatio(1), greaterThan(1));
      expect(semitonesToRatio(-1), lessThan(1));
    });
  });

  group('clampSemitones', () {
    test('범위를 벗어나면 자른다', () {
      expect(clampSemitones(99), maxPitchSemitones);
      expect(clampSemitones(-99), minPitchSemitones);
    });

    test('범위 안은 그대로', () {
      expect(clampSemitones(0), 0);
      expect(clampSemitones(3), 3);
      expect(clampSemitones(-6), -6);
    });
  });

  group('pitchVariantFileName', () {
    test('부호와 반음이 파일명에 들어간다', () {
      expect(pitchVariantFileName('봄날_mr1.mp3', 2), '봄날_mr1__p+2.m4a');
      expect(pitchVariantFileName('봄날_mr1.mp3', -3), '봄날_mr1__p-3.m4a');
    });

    test('같은 입력이면 항상 같은 이름 (캐시 키 안정성)', () {
      expect(
        pitchVariantFileName('a.mp3', 1),
        pitchVariantFileName('a.mp3', 1),
      );
    });

    test('반음이 다르면 이름도 다르다', () {
      expect(
        pitchVariantFileName('a.mp3', 1),
        isNot(pitchVariantFileName('a.mp3', -1)),
      );
    });

    test('확장자가 없어도 처리한다', () {
      expect(pitchVariantFileName('noext', 1), 'noext__p+1.m4a');
    });
  });

  group('buildVariantArgs', () {
    test('rubberband가 있으면 그 필터를 쓴다', () {
      final args = buildVariantArgs(
        input: 'in.mp3',
        output: 'out.m4a',
        semitones: 2,
        hasRubberband: true,
      );
      final filterIndex = args.indexOf('-filter:a');
      expect(filterIndex, greaterThan(-1));
      // rubberband의 pitch 인자는 반음이 아니라 비율이다
      expect(args[filterIndex + 1], contains('rubberband=tempo=1.000000:pitch=1.122462'));
      expect(args, contains('in.mp3'));
      expect(args.last, 'out.m4a');
    });

    test('rubberband가 없으면 대체 필터를 쓴다', () {
      final args = buildVariantArgs(
        input: 'in.mp3',
        output: 'out.m4a',
        semitones: 2,
        hasRubberband: false,
      );
      final filter = args[args.indexOf('-filter:a') + 1];
      expect(filter, contains('asetrate='));
      expect(filter, contains('atempo='));
      expect(filter, isNot(contains('rubberband')));
    });

    test('진행률 출력을 켠다', () {
      final args = buildVariantArgs(
        input: 'a',
        output: 'b',
        semitones: 1,
        hasRubberband: true,
      );
      expect(args, containsAllInOrder(['-progress', 'pipe:1']));
      expect(args, contains('-nostats'));
    });
  });
}
