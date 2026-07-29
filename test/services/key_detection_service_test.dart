import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/services/key_detection_service.dart';
import 'package:singpromfter_app/utils/music_key.dart';

// 조성 추정의 순수 부분 — ffmpeg 인자 조립, dB→크로마, 프로파일 매칭.
void main() {
  group('pitchClassFrequencies', () {
    test('A는 옥타브마다 정확히 두 배씩', () {
      final a = pitchClassFrequencies(9);
      expect(a.length, keyHighestOctave - keyLowestOctave + 1);
      // A2=110, A3=220, A4=440, A5=880, A6=1760
      expect(a[0], closeTo(110, 0.01));
      expect(a[2], closeTo(440, 0.01));
      expect(a[4], closeTo(1760, 0.01));
    });

    test('C4는 261.63Hz 근처', () {
      final c = pitchClassFrequencies(0);
      expect(c[2], closeTo(261.63, 0.01));
    });

    test('반음 간격은 언제나 2^(1/12)배', () {
      for (var pc = 0; pc < 11; pc++) {
        final lower = pitchClassFrequencies(pc)[0];
        final upper = pitchClassFrequencies(pc + 1)[0];
        expect(upper / lower, closeTo(1.059463, 0.0001));
      }
    });
  });

  group('buildChromaArgs', () {
    test('옥타브 수만큼 asplit·bandpass·amix가 맞물린다', () {
      final args = buildChromaArgs(
        input: 'mr.mp3',
        pitchClass: 0,
        startSeconds: 12.5,
      );
      final filter = args[args.indexOf('-filter_complex') + 1];
      const bands = keyHighestOctave - keyLowestOctave + 1;

      expect(filter, contains('asplit=$bands'));
      expect(filter, contains('amix=inputs=$bands:normalize=0'));
      // 대역마다 캐스케이드 단수만큼 겹쳐 건다.
      expect(
        'bandpass='.allMatches(filter).length,
        bands * keyBandpassCascade,
      );
      // 라벨이 모두 소비돼야 필터그래프가 성립한다.
      for (var i = 0; i < bands; i++) {
        final label = String.fromCharCode(97 + i);
        expect('[$label]'.allMatches(filter).length, 2); // asplit 출력 + bandpass 입력
        expect('[${label}1]'.allMatches(filter).length, 2); // bandpass 출력 + amix 입력
      }
    });

    test('표본 구간과 입력이 인자에 반영된다', () {
      final args = buildChromaArgs(
        input: 'C:/음악/mr.mp3',
        pitchClass: 3,
        startSeconds: 48.0,
        sampleSeconds: 30,
      );
      expect(args[args.indexOf('-ss') + 1], '48.00');
      expect(args[args.indexOf('-t') + 1], '30');
      expect(args[args.indexOf('-i') + 1], 'C:/음악/mr.mp3');
      expect(args.last, '-');
      expect(args, contains('-f'));
    });

    test('반음마다 중심 주파수가 다르다', () {
      String filterOf(int pc) {
        final args = buildChromaArgs(
          input: 'a.mp3',
          pitchClass: pc,
          startSeconds: 0,
        );
        return args[args.indexOf('-filter_complex') + 1];
      }

      expect(filterOf(0), isNot(filterOf(1)));
    });
  });

  group('chromaFromDecibels', () {
    test('가장 센 반음이 1.0이 된다', () {
      final chroma = chromaFromDecibels([-30, -20, -40]);
      expect(chroma[1], closeTo(1.0, 1e-9));
      expect(chroma[0], lessThan(chroma[1]));
      expect(chroma[2], lessThan(chroma[0]));
    });

    test('20dB 차이는 진폭 10배 차이', () {
      final chroma = chromaFromDecibels([-20, 0]);
      expect(chroma[0], closeTo(0.1, 1e-9));
    });

    test('빈 입력은 빈 결과', () {
      expect(chromaFromDecibels([]), isEmpty);
    });
  });

  group('detectKeyFromChroma', () {
    /// 프로파일을 그대로 크로마로 준다 = 그 조성이 답이어야 한다.
    List<double> rotated(List<double> profile, int tonic) =>
        List<double>.generate(12, (i) => profile[(i - tonic + 12) % 12]);

    test('12개 장조를 모두 되찾는다', () {
      for (var tonic = 0; tonic < 12; tonic++) {
        final estimate = detectKeyFromChroma(rotated(majorProfile, tonic));
        expect(estimate, isNotNull);
        expect(estimate!.key, MusicKey(tonic, KeyMode.major));
        expect(estimate.confidence, closeTo(1.0, 1e-6));
        expect(estimate.isConfident, isTrue);
      }
    });

    test('12개 단조를 모두 되찾는다', () {
      for (var tonic = 0; tonic < 12; tonic++) {
        final estimate = detectKeyFromChroma(rotated(minorProfile, tonic));
        expect(estimate!.key, MusicKey(tonic, KeyMode.minor));
        expect(estimate.confidence, closeTo(1.0, 1e-6));
      }
    });

    test('C장조 3화음만 울려도 C를 고른다', () {
      final chroma = List<double>.filled(12, 0.05);
      chroma[0] = 1.0; // C
      chroma[4] = 0.8; // E
      chroma[7] = 0.9; // G
      expect(detectKeyFromChroma(chroma)!.key, const MusicKey(0, KeyMode.major));
    });

    test('A단조 3화음은 Am을 고른다', () {
      final chroma = List<double>.filled(12, 0.05);
      chroma[9] = 1.0; // A
      chroma[0] = 0.8; // C
      chroma[4] = 0.9; // E
      expect(detectKeyFromChroma(chroma)!.key, const MusicKey(9, KeyMode.minor));
    });

    test('평평한 크로마는 확신하지 못한다', () {
      final estimate = detectKeyFromChroma(List<double>.filled(12, 0.5));
      expect(estimate?.isConfident ?? false, isFalse);
    });

    test('전부 무음이면 판정하지 않는다', () {
      expect(detectKeyFromChroma(List<double>.filled(12, 0)), isNull);
    });

    test('길이가 12가 아니면 판정하지 않는다', () {
      expect(detectKeyFromChroma([1, 0, 0]), isNull);
    });
  });
}
