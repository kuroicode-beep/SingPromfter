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

  group('scrollDelta', () {
    test('속도에 비례한다', () {
      expect(
        LyricsProgressService.scrollDelta(speedLevel: 3, multiplier: 1.4),
        closeTo(4.2, 0.0001),
      );
    });

    test('속도가 0이면 움직이지 않는다', () {
      expect(
        LyricsProgressService.scrollDelta(speedLevel: 0, multiplier: 1.4),
        0,
      );
    });
  });
}
