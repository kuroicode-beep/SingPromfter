import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/services/lyrics_progress_service.dart';

// 싱크 가사가 없는 곡의 줄 진행 추정.
//
// v2.8.0에서 speedLevel(가사 스크롤 속도 배수)을 없앴다. 속도는 이제 음악
// 템포 하나뿐이고, 가사는 언제나 곡 길이에 비례해 고르게 넘어간다.
void main() {
  int indexAt({
    required Duration position,
    Duration duration = Duration.zero,
    int lineCount = 10,
  }) {
    return LyricsProgressService.estimatedLineIndex(
      position: position,
      duration: duration,
      lineCount: lineCount,
    );
  }

  group('반주 길이를 아는 경우', () {
    const duration = Duration(seconds: 100);

    test('길이에 비례해 줄이 넘어간다', () {
      expect(indexAt(position: Duration.zero, duration: duration), 0);
      expect(
        indexAt(position: const Duration(seconds: 50), duration: duration),
        5,
      );
      expect(
        indexAt(position: const Duration(seconds: 99), duration: duration),
        9,
      );
    });

    test('단조 증가한다 — 되돌아가지 않는다', () {
      var previous = -1;
      for (var s = 0; s <= 100; s++) {
        final index = indexAt(
          position: Duration(seconds: s),
          duration: duration,
        );
        expect(index, greaterThanOrEqualTo(previous), reason: '$s초');
        previous = index;
      }
    });

    test('끝을 넘어가도 마지막 줄로 제한된다', () {
      expect(
        indexAt(
          position: const Duration(seconds: 500),
          duration: duration,
          lineCount: 10,
        ),
        9,
      );
    });
  });

  group('반주 길이를 모르는 경우 (가사 전용)', () {
    test('경과 시간으로 진행한다 — 약 6초에 한 줄', () {
      expect(indexAt(position: const Duration(seconds: 12), lineCount: 50), 1);
      expect(indexAt(position: const Duration(seconds: 60), lineCount: 50), 9);
    });

    test('시작 전에는 첫 줄', () {
      expect(indexAt(position: Duration.zero, lineCount: 50), 0);
    });
  });

  group('경계', () {
    test('줄이 하나뿐이면 언제나 0', () {
      expect(
        indexAt(
          position: const Duration(seconds: 50),
          duration: const Duration(seconds: 100),
          lineCount: 1,
        ),
        0,
      );
    });

    test('음수 위치는 0', () {
      expect(indexAt(position: const Duration(seconds: -5)), 0);
    });
  });

  group('positionForLineIndex', () {
    const duration = Duration(seconds: 100);

    test('estimatedLineIndex와 왕복이 맞는다', () {
      for (var i = 0; i < 10; i++) {
        final position = LyricsProgressService.positionForLineIndex(
          index: i,
          duration: duration,
          lineCount: 10,
        );
        expect(position, isNotNull, reason: '줄 $i');
        expect(
          indexAt(position: position!, duration: duration),
          i,
          reason: '줄 $i',
        );
      }
    });

    test('첫 줄은 0초', () {
      expect(
        LyricsProgressService.positionForLineIndex(
          index: 0,
          duration: duration,
          lineCount: 10,
        ),
        Duration.zero,
      );
    });

    test('길이를 모르면 null — 이동할 자리를 알 수 없다', () {
      expect(
        LyricsProgressService.positionForLineIndex(
          index: 3,
          duration: Duration.zero,
          lineCount: 10,
        ),
        isNull,
      );
    });

    test('줄이 하나뿐이면 null', () {
      expect(
        LyricsProgressService.positionForLineIndex(
          index: 0,
          duration: duration,
          lineCount: 1,
        ),
        isNull,
      );
    });
  });

  // 줄 안 진행률 — 예전에는 floor()로 버리던 소수부.
  group('estimatedLineProgress', () {
    LineProgress at(int seconds, {int lines = 4, int total = 40}) =>
        LyricsProgressService.estimatedLineProgress(
          position: Duration(seconds: seconds),
          duration: Duration(seconds: total),
          lineCount: lines,
        );

    test('줄 경계에서 진행률이 0이다', () {
      expect(at(10).index, 1);
      expect(at(10).fraction, closeTo(0, 1e-9));
    });

    test('줄 한가운데서 0.5', () {
      expect(at(15).index, 1);
      expect(at(15).fraction, closeTo(0.5, 1e-9));
    });

    test('다음 줄 직전에는 1에 가깝다', () {
      final p = at(19);
      expect(p.index, 1);
      expect(p.fraction, greaterThan(0.85));
      expect(p.fraction, lessThan(1.0));
    });

    test('진행률은 0 이상 1 이하다', () {
      for (var s = 0; s <= 40; s++) {
        expect(at(s).fraction, inInclusiveRange(0.0, 1.0), reason: '$s초');
      }
    });

    test('마지막 줄에 닿으면 1로 고정된다 — 되돌아가지 않게', () {
      expect(at(35).index, 3);
      expect(at(35).fraction, 1.0);
      expect(at(40).fraction, 1.0);
    });

    test('줄이 하나뿐이면 진행하지 않는다', () {
      expect(at(20, lines: 1).index, 0);
      expect(at(20, lines: 1).fraction, 0);
    });

    test('index는 estimatedLineIndex와 언제나 같다', () {
      for (var s = 0; s <= 40; s += 3) {
        expect(
          at(s).index,
          indexAt(
            position: Duration(seconds: s),
            duration: const Duration(seconds: 40),
            lineCount: 4,
          ),
          reason: '$s초',
        );
      }
    });
  });
}
