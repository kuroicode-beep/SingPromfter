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

  group('buildLevelBands', () {
    test('요청한 개수만큼 만든다', () {
      expect(buildLevelBands(count: 24), hasLength(24));
      expect(levelBands, hasLength(levelBandCount));
    });

    test('첫 밴드는 하한이, 마지막 밴드는 상한이 없다', () {
      final bands = buildLevelBands();
      expect(bands.first.lowHz, isNull);
      expect(bands.last.highHz, isNull);
    });

    test('경계가 이어진다 — 사이에 빈 구간이 없다', () {
      final bands = buildLevelBands();
      for (var i = 0; i < bands.length - 1; i++) {
        expect(bands[i].highHz, bands[i + 1].lowHz, reason: '밴드 $i');
      }
    });

    test('로그 등간격이라 밴드마다 주파수 비가 같다', () {
      final bands = buildLevelBands();
      final ratios = <double>[];
      for (var i = 1; i < bands.length - 1; i++) {
        ratios.add(bands[i].highHz! / bands[i].lowHz!);
      }
      for (final r in ratios) {
        expect(r, closeTo(ratios.first, 1e-9));
      }
    });

    test('요청 범위를 벗어나지 않는다', () {
      final bands = buildLevelBands();
      expect(bands[1].lowHz, greaterThan(levelBandLowHz));
      expect(bands[bands.length - 2].highHz, lessThan(levelBandHighHz + 1));
    });

    test('개수가 0이면 빈 목록', () {
      expect(buildLevelBands(count: 0), isEmpty);
    });
  });

  group('buildAllBandAnalysisArgs', () {
    String filterOf(List<String> args) =>
        args[args.indexOf('-filter_complex') + 1];

    test('asplit·amerge 개수가 밴드 수와 맞는다', () {
      final filter = filterOf(buildAllBandAnalysisArgs(input: 'a.mp3'));
      expect(filter, contains('asplit=$levelBandCount'));
      expect(filter, contains('amerge=inputs=$levelBandCount'));
    });

    test('라벨이 모두 소비된다 — 필터그래프가 성립해야 한다', () {
      final filter = filterOf(buildAllBandAnalysisArgs(input: 'a.mp3'));
      for (var i = 0; i < levelBandCount; i++) {
        expect('[b$i]'.allMatches(filter).length, 2, reason: 'b$i');
        expect('[c$i]'.allMatches(filter).length, 2, reason: 'c$i');
      }
    });

    test('밴드마다 캐스케이드 단수만큼 필터를 겹친다', () {
      final filter = filterOf(buildAllBandAnalysisArgs(input: 'a.mp3'));
      // 첫 밴드는 lowpass만, 마지막은 highpass만, 나머지는 둘 다.
      final expected = (levelBandCount - 2) * 2 * levelBandCascade +
          levelBandCascade * 2;
      final actual = 'highpass='.allMatches(filter).length +
          'lowpass='.allMatches(filter).length;
      expect(actual, expected);
    });

    test('채널별 RMS만 남긴다 — 안 그러면 프레임마다 수백 줄이 쏟아진다', () {
      final filter = filterOf(buildAllBandAnalysisArgs(input: 'a.mp3'));
      expect(filter, contains('measure_perchannel=RMS_level'));
      expect(filter, contains('measure_overall=none'));
    });

    test('25fps를 유지한다', () {
      final filter = filterOf(buildAllBandAnalysisArgs(input: 'a.mp3'));
      expect(filter, contains('asetnsamples=n=1764'));
    });

    test('입력 경로를 그대로 넘긴다', () {
      final args = buildAllBandAnalysisArgs(input: r'C:\음악\mr.mp3');
      expect(args[args.indexOf('-i') + 1], r'C:\음악\mr.mp3');
    });
  });

  group('parseBandRmsLevel', () {
    test('채널 번호를 0-based 밴드로 바꾼다', () {
      final hit = parseBandRmsLevel('lavfi.astats.1.RMS_level=-31.25');
      expect(hit!.band, 0);
      expect(hit.dbfs, closeTo(-31.25, 1e-9));
    });

    test('24번 채널은 23번 밴드', () {
      expect(parseBandRmsLevel('lavfi.astats.24.RMS_level=-5')!.band, 23);
    });

    test('무음(-inf)은 -100으로 본다', () {
      expect(parseBandRmsLevel('lavfi.astats.3.RMS_level=-inf')!.dbfs, -100.0);
    });

    test('nan도 -100', () {
      expect(parseBandRmsLevel('lavfi.astats.3.RMS_level=nan')!.dbfs, -100.0);
    });

    test('Overall 줄은 무시한다', () {
      expect(parseBandRmsLevel('lavfi.astats.Overall.RMS_level=-20'), isNull);
    });

    test('관계없는 줄은 null', () {
      expect(parseBandRmsLevel('frame:12 pts:1764'), isNull);
      expect(parseBandRmsLevel(''), isNull);
    });
  });
}
