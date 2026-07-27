import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/practice_session.dart';
import 'package:singpromfter_app/services/practice_log_service.dart';

PracticeSession session({
  String songId = 's1',
  String title = '봄날',
  required DateTime startedAt,
  required int durationMs,
  int pitch = 0,
}) {
  return PracticeSession(
    id: 'id-$startedAt',
    songId: songId,
    songTitle: title,
    startedAt: startedAt,
    durationMs: durationMs,
    pitchSemitones: pitch,
  );
}

void main() {
  group('shouldRecord (30초 미만 미기록)', () {
    test('30초 미만은 기록하지 않는다', () {
      expect(
        PracticeSessionRules.shouldRecord(const Duration(seconds: 29)),
        isFalse,
      );
      expect(
        PracticeSessionRules.shouldRecord(const Duration(seconds: 10)),
        isFalse,
      );
    });

    test('30초 이상은 기록한다', () {
      expect(
        PracticeSessionRules.shouldRecord(const Duration(seconds: 30)),
        isTrue,
      );
      expect(
        PracticeSessionRules.shouldRecord(const Duration(minutes: 4)),
        isTrue,
      );
    });
  });

  group('shouldMerge (60초 이내 재생은 직전 세션에 병합)', () {
    final base = DateTime(2026, 7, 28, 10, 0, 0);

    test('직전 세션이 없으면 병합하지 않는다', () {
      expect(
        PracticeSessionRules.shouldMerge(
          previous: null,
          songId: 's1',
          now: base,
        ),
        isFalse,
      );
    });

    test('다른 곡이면 병합하지 않는다', () {
      final prev = session(
        songId: 's1',
        startedAt: base,
        durationMs: 60000,
      );
      expect(
        PracticeSessionRules.shouldMerge(
          previous: prev,
          songId: 's2',
          now: base.add(const Duration(minutes: 1, seconds: 10)),
        ),
        isFalse,
      );
    });

    test('종료 후 60초 이내면 병합한다', () {
      final prev = session(startedAt: base, durationMs: 60000);
      // 이전 세션 종료 시각 = base + 60초, 그로부터 30초 뒤
      expect(
        PracticeSessionRules.shouldMerge(
          previous: prev,
          songId: 's1',
          now: base.add(const Duration(seconds: 90)),
        ),
        isTrue,
      );
    });

    test('종료 후 60초를 넘으면 새 세션으로 센다', () {
      final prev = session(startedAt: base, durationMs: 60000);
      expect(
        PracticeSessionRules.shouldMerge(
          previous: prev,
          songId: 's1',
          now: base.add(const Duration(seconds: 200)),
        ),
        isFalse,
      );
    });
  });

  group('PracticeSummary.summarize', () {
    final base = DateTime(2026, 7, 28, 10, 0, 0);

    test('곡별로 횟수·총 시간을 집계한다', () {
      final list = [
        session(startedAt: base, durationMs: 60000),
        session(startedAt: base.add(const Duration(hours: 1)), durationMs: 90000),
        session(
          songId: 's2',
          title: '거리에서',
          startedAt: base.add(const Duration(hours: 2)),
          durationMs: 30000,
        ),
      ];

      final summaries = PracticeSummary.summarize(list);
      expect(summaries, hasLength(2));

      // 최근 연습일 내림차순이므로 s2가 먼저
      expect(summaries.first.songId, 's2');

      final first = summaries.firstWhere((s) => s.songId == 's1');
      expect(first.sessionCount, 2);
      expect(first.totalDurationMs, 150000);
      expect(first.lastPracticedAt, base.add(const Duration(hours: 1)));
    });

    test('가장 자주 쓴 키를 고른다', () {
      final list = [
        session(startedAt: base, durationMs: 60000, pitch: -2),
        session(
          startedAt: base.add(const Duration(minutes: 10)),
          durationMs: 60000,
          pitch: -2,
        ),
        session(
          startedAt: base.add(const Duration(minutes: 20)),
          durationMs: 60000,
          pitch: 1,
        ),
      ];

      final summary = PracticeSummary.summarize(list).single;
      expect(summary.dominantPitchSemitones, -2);
    });

    test('빈 목록은 빈 결과', () {
      expect(PracticeSummary.summarize(const []), isEmpty);
    });
  });

  group('PracticeSession JSON', () {
    test('왕복 후 값이 보존된다', () {
      final original = session(
        startedAt: DateTime(2026, 7, 28, 9, 30),
        durationMs: 123456,
        pitch: -3,
      );
      final restored = PracticeSession.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.songId, original.songId);
      expect(restored.songTitle, original.songTitle);
      expect(restored.startedAt, original.startedAt);
      expect(restored.durationMs, original.durationMs);
      expect(restored.pitchSemitones, -3);
      expect(restored.recorded, isFalse);
    });

    test('필드가 없어도 기본값으로 읽는다', () {
      final restored = PracticeSession.fromJson({'id': 'x', 'songId': 'y'});
      expect(restored.durationMs, 0);
      expect(restored.pitchSemitones, 0);
      expect(restored.backingTrackSlot, isNull);
    });
  });
}
