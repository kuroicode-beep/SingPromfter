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

    // v2.7.0까지는 "상위 버전만" 거부해서, 밴드 수를 바꿔도 이미 재생해 본
    // 곡은 영영 옛 캐시를 돌려줬다. 이제 정확히 일치할 때만 받아들인다.
    test('상위 스키마 버전은 거부한다', () {
      expect(
        TrackLevels.decode('{"version":99,"fps":25,"bands":6,"frames":[]}'),
        isNull,
      );
    });

    test('하위 스키마 버전도 거부한다 — 밴드 수가 바뀌어도 알아채야 한다', () {
      expect(
        TrackLevels.decode('{"version":1,"fps":25,"bands":6,"frames":[]}'),
        isNull,
      );
    });

    test('프레임 폭이 밴드 수와 어긋나면 거부한다', () {
      expect(
        TrackLevels.decode(
          '{"version":${TrackLevels.schemaVersion},"fps":25,"bands":6,'
          '"frames":[[1,2,3]]}',
        ),
        isNull,
      );
    });

    test('프레임 길이가 들쭉날쭉해도 거부한다', () {
      expect(
        TrackLevels.decode(
          '{"version":${TrackLevels.schemaVersion},"fps":25,"bands":2,'
          '"frames":[[1,2],[3]]}',
        ),
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

  // 25fps 데이터를 60Hz로 그리면 프레임이 2.4번씩 반복돼 계단이 보인다.
  group('TrackLevels.sampleAt', () {
    const levels = TrackLevels(
      fps: 25,
      bandCount: 2,
      frames: [
        [0, 100],
        [100, 0],
      ],
    );

    test('프레임 정각에서는 frameAt과 같은 값(0..1)', () {
      expect(levels.sampleAt(Duration.zero), [0.0, 1.0]);
      expect(levels.sampleAt(const Duration(milliseconds: 40)), [1.0, 0.0]);
    });

    test('프레임 사이는 선형 보간한다', () {
      final mid = levels.sampleAt(const Duration(milliseconds: 20))!;
      expect(mid[0], closeTo(0.5, 1e-9));
      expect(mid[1], closeTo(0.5, 1e-9));
    });

    test('마지막 프레임을 넘어가지 않는다', () {
      expect(levels.sampleAt(const Duration(milliseconds: 50)), [1.0, 0.0]);
    });

    test('범위 밖이면 null', () {
      expect(levels.sampleAt(const Duration(seconds: 10)), isNull);
      expect(levels.sampleAt(const Duration(milliseconds: -10)), isNull);
    });

    test('프레임이 없으면 null', () {
      const empty = TrackLevels(fps: 25, bandCount: 6, frames: []);
      expect(empty.sampleAt(Duration.zero), isNull);
    });
  });
}
