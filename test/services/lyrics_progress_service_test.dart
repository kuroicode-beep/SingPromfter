import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/services/lyrics_progress_service.dart';

void main() {
  int indexAt({
    required Duration position,
    Duration duration = Duration.zero,
    int lineCount = 10,
    double speedLevel = LyricsProgressService.neutralSpeedLevel,
  }) {
    return LyricsProgressService.estimatedLineIndex(
      position: position,
      duration: duration,
      lineCount: lineCount,
      speedLevel: speedLevel,
    );
  }

  group('반주 길이를 아는 경우', () {
    const duration = Duration(seconds: 100);

    test('기준 속도에서는 길이에 비례해 줄이 넘어간다', () {
      expect(indexAt(position: Duration.zero, duration: duration), 0);
      expect(indexAt(position: const Duration(seconds: 50), duration: duration), 5);
      expect(indexAt(position: const Duration(seconds: 99), duration: duration), 9);
    });

    test('속도를 올리면 가사가 앞서 나간다 (선행 표시)', () {
      final normal = indexAt(
        position: const Duration(seconds: 40),
        duration: duration,
        speedLevel: 2,
      );
      final faster = indexAt(
        position: const Duration(seconds: 40),
        duration: duration,
        speedLevel: 4,
      );
      expect(faster, greaterThan(normal));
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
    test('경과 시간과 속도로 진행한다', () {
      // speedLevel 2 → 초당 0.166줄 ≈ 6초에 한 줄
      expect(indexAt(position: const Duration(seconds: 12), lineCount: 50), 1);
      expect(indexAt(position: const Duration(seconds: 60), lineCount: 50), 9);
    });

    test('속도를 올리면 더 빨리 넘어간다', () {
      final slow = indexAt(
        position: const Duration(seconds: 60),
        lineCount: 50,
        speedLevel: 2,
      );
      final fast = indexAt(
        position: const Duration(seconds: 60),
        lineCount: 50,
        speedLevel: 8,
      );
      expect(fast, greaterThan(slow));
    });
  });

  group('경계 조건', () {
    test('속도가 0이면 진행하지 않는다 (기존 버그: 속도 무시하고 넘어감)', () {
      expect(
        indexAt(
          position: const Duration(seconds: 90),
          duration: const Duration(seconds: 100),
          speedLevel: 0,
        ),
        0,
      );
    });

    test('줄이 1개 이하면 항상 0', () {
      expect(
        indexAt(position: const Duration(seconds: 50), lineCount: 1),
        0,
      );
      expect(
        indexAt(position: const Duration(seconds: 50), lineCount: 0),
        0,
      );
    });

    test('위치가 0 이하면 0', () {
      expect(indexAt(position: Duration.zero), 0);
      expect(indexAt(position: const Duration(seconds: -5)), 0);
    });

    test('위치가 커질수록 줄 번호는 줄지 않는다 (단조 증가)', () {
      const duration = Duration(seconds: 100);
      var previous = 0;
      for (var s = 0; s <= 100; s += 5) {
        final current = indexAt(
          position: Duration(seconds: s),
          duration: duration,
          lineCount: 20,
        );
        expect(current, greaterThanOrEqualTo(previous));
        previous = current;
      }
    });
  });

  // scrollDelta 그룹은 v2.6.0에서 삭제했다. 매 프레임 픽셀을 굴리던
  // 자동 스크롤이 "현재 줄 센터링"으로 바뀌면서 함수 자체가 사라졌다.

  group('positionForLineIndex (estimatedLineIndex의 역함수)', () {
    const duration = Duration(minutes: 4);
    const lineCount = 40;

    test('구한 위치를 되돌리면 같은 줄이 나온다', () {
      for (var i = 0; i < lineCount; i++) {
        final position = LyricsProgressService.positionForLineIndex(
          index: i,
          duration: duration,
          lineCount: lineCount,
          speedLevel: 2,
        );
        expect(position, isNotNull, reason: '줄 $i');
        final back = LyricsProgressService.estimatedLineIndex(
          position: position!,
          duration: duration,
          lineCount: lineCount,
          speedLevel: 2,
        );
        expect(back, i, reason: '줄 $i 왕복');
      }
    });

    test('첫 줄은 0초', () {
      expect(
        LyricsProgressService.positionForLineIndex(
          index: 0,
          duration: duration,
          lineCount: lineCount,
          speedLevel: 2,
        ),
        Duration.zero,
      );
    });

    test('속도를 올리면 같은 줄에 더 일찍 닿는다', () {
      final slow = LyricsProgressService.positionForLineIndex(
        index: 20,
        duration: duration,
        lineCount: lineCount,
        speedLevel: 2,
      )!;
      final fast = LyricsProgressService.positionForLineIndex(
        index: 20,
        duration: duration,
        lineCount: lineCount,
        speedLevel: 4,
      )!;
      expect(fast, lessThan(slow));
    });

    test('계산할 수 없으면 null — 길이 모름·속도 0·줄 1개', () {
      expect(
        LyricsProgressService.positionForLineIndex(
          index: 3,
          duration: Duration.zero,
          lineCount: lineCount,
          speedLevel: 2,
        ),
        isNull,
      );
      expect(
        LyricsProgressService.positionForLineIndex(
          index: 3,
          duration: duration,
          lineCount: lineCount,
          speedLevel: 0,
        ),
        isNull,
      );
      expect(
        LyricsProgressService.positionForLineIndex(
          index: 0,
          duration: duration,
          lineCount: 1,
          speedLevel: 2,
        ),
        isNull,
      );
    });

    test('곡 길이를 넘지 않는다', () {
      final position = LyricsProgressService.positionForLineIndex(
        index: lineCount - 1,
        duration: duration,
        lineCount: lineCount,
        speedLevel: 6,
      )!;
      expect(position, lessThanOrEqualTo(duration));
    });
  });

  // 줄 안 진행률 — 예전에는 floor()로 버리던 소수부.
  group('estimatedLineProgress', () {
    LineProgress at(int seconds, {int lines = 4, int total = 40}) =>
        LyricsProgressService.estimatedLineProgress(
          position: Duration(seconds: seconds),
          duration: Duration(seconds: total),
          lineCount: lines,
          speedLevel: LyricsProgressService.neutralSpeedLevel,
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
        final p = at(s);
        expect(p.fraction, inInclusiveRange(0.0, 1.0), reason: '$s초');
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
          LyricsProgressService.estimatedLineIndex(
            position: Duration(seconds: s),
            duration: const Duration(seconds: 40),
            lineCount: 4,
            speedLevel: LyricsProgressService.neutralSpeedLevel,
          ),
          reason: '$s초',
        );
      }
    });
  });
}
