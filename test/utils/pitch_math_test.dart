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

  // 템포 — v2.8.0. 키와 한 번에 굽는다.
  group('quantizeTempo', () {
    test('0.05 단위로 스냅한다 — 캐시 키가 흔들리지 않게', () {
      expect(quantizeTempo(0.923), closeTo(0.90, 1e-9));
      expect(quantizeTempo(0.926), closeTo(0.95, 1e-9));
    });

    test('범위를 벗어나면 자른다', () {
      expect(quantizeTempo(0.1), minTempoScale);
      expect(quantizeTempo(9), maxTempoScale);
    });

    test('1.0은 기본으로 인식한다', () {
      expect(isDefaultTempo(quantizeTempo(1.0)), isTrue);
      expect(isDefaultTempo(quantizeTempo(1.02)), isTrue);
      expect(isDefaultTempo(quantizeTempo(0.95)), isFalse);
    });
  });

  group('trackVariantFileName', () {
    test('키도 템포도 기본이면 null — 원본을 그대로 쓴다', () {
      expect(trackVariantFileName('a_mr1.mp3'), isNull);
      expect(
        trackVariantFileName('a_mr1.mp3', semitones: 0, tempoScale: 1),
        isNull,
      );
    });

    // 이게 깨지면 이미 렌더해 둔 v2.7.0 키 변형본을 전부 버리게 된다.
    test('템포가 1.0이면 v2.7.0과 완전히 같은 이름', () {
      expect(
        trackVariantFileName('봄날_mr1.mp3', semitones: 2),
        '봄날_mr1__p+2.m4a',
      );
      expect(
        trackVariantFileName('봄날_mr1.mp3', semitones: -3),
        '봄날_mr1__p-3.m4a',
      );
    });

    test('템포가 있으면 뒤에 붙는다', () {
      expect(
        trackVariantFileName('봄날_mr1.mp3', semitones: 2, tempoScale: 0.9),
        '봄날_mr1__p+2_t090.m4a',
      );
      expect(
        trackVariantFileName('봄날_mr1.mp3', tempoScale: 1.25),
        '봄날_mr1__p+0_t125.m4a',
      );
    });

    // TrackAssetService가 prefix로 캐시를 지우므로 이 규약이 깨지면
    // 반주를 교체해도 옛 변형본이 남는다.
    test('언제나 <stem>__p 로 시작한다 — 캐시 무효화 규약', () {
      for (final semitones in [-6, 0, 6]) {
        for (final tempo in [0.5, 1.0, 1.5]) {
          final name = trackVariantFileName(
            'a_mr1.mp3',
            semitones: semitones,
            tempoScale: tempo,
          );
          if (name == null) continue;
          expect(name.startsWith('a_mr1__p'), isTrue, reason: name);
        }
      }
    });
  });

  group('rubberbandFilter', () {
    test('tempo와 pitch를 한 인스턴스로 건다', () {
      final filter = rubberbandFilter(2, tempoScale: 0.9);
      expect(filter, contains('tempo=0.900000'));
      expect(filter, contains('pitch=1.122462'));
      expect('rubberband'.allMatches(filter).length, 1);
    });
  });

  group('atempoChain', () {
    test('0.5~2.0은 한 단으로 끝낸다', () {
      expect('atempo'.allMatches(atempoChain(0.9)).length, 1);
    });

    test('범위를 벗어나면 두 단으로 겹친다', () {
      final chain = atempoChain(0.25);
      expect('atempo'.allMatches(chain).length, 2);
      expect(chain, contains('0.500000'));
    });
  });
}
