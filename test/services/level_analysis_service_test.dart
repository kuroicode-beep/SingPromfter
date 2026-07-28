import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/track_levels.dart';
import 'package:singpromfter_app/services/level_analysis_service.dart';

// EQ 미터용 밴드 레벨 분석 — 순수 함수와 캐시 포맷.
void main() {
  group('buildBandAnalysisArgs', () {
    test('최저 밴드는 lowpass만 건다', () {
      final args = buildBandAnalysisArgs(input: 'in.mp3', highHz: 150);
      final af = args[args.indexOf('-af') + 1];
      expect(af, contains('lowpass=f=150'));
      expect(af, isNot(contains('highpass')));
      expect(af, contains('asetnsamples=n=1764'));
      expect(af, contains('RMS_level'));
    });

    test('최고 밴드는 highpass만 건다', () {
      final args = buildBandAnalysisArgs(input: 'in.mp3', lowHz: 6000);
      final af = args[args.indexOf('-af') + 1];
      expect(af, contains('highpass=f=6000'));
      expect(af, isNot(contains('lowpass')));
    });

    test('중간 밴드는 양쪽을 건다', () {
      final args = buildBandAnalysisArgs(
        input: 'in.mp3',
        lowHz: 400,
        highHz: 1000,
      );
      final af = args[args.indexOf('-af') + 1];
      expect(af, contains('highpass=f=400'));
      expect(af, contains('lowpass=f=1000'));
    });

    test('디코드 출력은 버린다 (-f null)', () {
      final args = buildBandAnalysisArgs(input: 'in.mp3');
      expect(args, containsAllInOrder(['-f', 'null', '-']));
    });
  });

  group('quantizeLevel', () {
    test('-60dB 이하는 0', () {
      expect(quantizeLevel(-60), 0);
      expect(quantizeLevel(-100), 0);
    });

    test('0dB 이상은 100', () {
      expect(quantizeLevel(0), 100);
      expect(quantizeLevel(3), 100);
    });

    test('-30dB는 중간값 50', () {
      expect(quantizeLevel(-30), 50);
    });
  });

  group('assembleLevels', () {
    test('밴드별 길이가 다르면 최단에 맞춘다', () {
      final levels = assembleLevels([
        [10, 20, 30],
        [40, 50],
      ]);
      expect(levels.frames, hasLength(2));
      expect(levels.frames[0], [10, 40]);
      expect(levels.frames[1], [20, 50]);
      expect(levels.bandCount, 2);
    });

    test('빈 입력은 빈 결과', () {
      expect(assembleLevels([]).isEmpty, isTrue);
    });
  });

  group('TrackLevels 직렬화', () {
    test('encode/decode 왕복', () {
      final original = assembleLevels([
        [1, 2],
        [3, 4],
      ]);
      final decoded = TrackLevels.decode(original.encode());
      expect(decoded, isNotNull);
      expect(decoded!.fps, levelAnalysisFps);
      expect(decoded.bandCount, 2);
      expect(decoded.frames, original.frames);
    });

    test('상위 스키마 버전은 거부한다', () {
      expect(
        TrackLevels.decode('{"version":99,"fps":25,"bands":6,"frames":[]}'),
        isNull,
      );
    });

    test('깨진 JSON은 null', () {
      expect(TrackLevels.decode('{broken'), isNull);
    });
  });

  group('TrackLevels.frameAt', () {
    TrackLevels levels() => TrackLevels(
      fps: 25,
      bandCount: 1,
      // 프레임 하나 = 40ms.
      frames: List.generate(25, (i) => [i]),
    );

    test('위치를 프레임으로 환산한다', () {
      expect(levels().frameAt(Duration.zero), [0]);
      expect(levels().frameAt(const Duration(milliseconds: 40)), [1]);
      expect(levels().frameAt(const Duration(milliseconds: 999)), [24]);
    });

    test('범위 밖은 null', () {
      expect(levels().frameAt(const Duration(seconds: 1)), isNull);
      expect(levels().frameAt(const Duration(milliseconds: -1)), isNull);
    });

    test('빈 프레임은 항상 null', () {
      const empty = TrackLevels(fps: 25, bandCount: 0, frames: []);
      expect(empty.frameAt(Duration.zero), isNull);
    });
  });
}
