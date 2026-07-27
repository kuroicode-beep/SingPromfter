// file: lib/services/practice_log_service.dart
//
// 연습 세션 적재 규칙과 집계를 담당한다. 판정 규칙은 순수 함수로 분리해
// 테스트 가능하게 두고, 이 클래스는 저장·집계만 조율한다.
import 'package:uuid/uuid.dart';

import '../controllers/playback_controller.dart';
import '../models/practice_session.dart';
import '../repository/practice_log_store.dart';

/// 세션 기록 여부·병합 여부를 판단하는 순수 규칙.
class PracticeSessionRules {
  PracticeSessionRules._();

  /// 이보다 짧게 재생하면 연습으로 세지 않는다(곡 훑어보기로 로그가 오염되는 것 방지).
  static const Duration minimumDuration = Duration(seconds: 30);

  /// 같은 곡을 이 시간 안에 다시 재생하면 직전 세션에 합친다
  /// (일시정지·되감기를 별도 연습으로 세지 않기 위해).
  static const Duration mergeWindow = Duration(seconds: 60);

  static bool shouldRecord(Duration played) => played >= minimumDuration;

  /// [previous]에 이어붙일 수 있으면 true.
  static bool shouldMerge({
    required PracticeSession? previous,
    required String songId,
    required DateTime now,
  }) {
    if (previous == null) return false;
    if (previous.songId != songId) return false;
    final since = now.difference(
      previous.startedAt.add(previous.duration),
    );
    return !since.isNegative && since <= mergeWindow;
  }
}

class PracticeLogService {
  final PracticeLogStore _store;
  final Uuid _uuid;

  List<PracticeSession> _sessions = [];

  PracticeLogService({PracticeLogStore? store, Uuid? uuid})
    : _store = store ?? PracticeLogStore(),
      _uuid = uuid ?? const Uuid();

  List<PracticeSession> get sessions => List.unmodifiable(_sessions);

  /// 곡별 누적(횟수·총 시간·최근 연습일·주 사용 키).
  List<PracticeSummary> get summaries => PracticeSummary.summarize(_sessions);

  Future<void> load() async {
    _sessions = await _store.load();
  }

  /// 재생이 끝난 시점에 호출한다. 규칙에 맞으면 기록하거나 직전 세션에 합친다.
  Future<void> record({
    required PlaybackSnapshot snapshot,
    required Duration played,
    DateTime? now,
  }) async {
    final song = snapshot.song;
    if (song == null) return;
    if (!PracticeSessionRules.shouldRecord(played)) return;

    final at = now ?? DateTime.now();
    final previous = _lastSessionFor(song.id);

    if (PracticeSessionRules.shouldMerge(
      previous: previous,
      songId: song.id,
      now: at,
    )) {
      final index = _sessions.lastIndexOf(previous!);
      _sessions[index] = previous.copyWith(
        durationMs: previous.durationMs + played.inMilliseconds,
      );
    } else {
      _sessions.add(
        PracticeSession(
          id: _uuid.v4(),
          songId: song.id,
          songTitle: song.title,
          startedAt: at.subtract(played),
          durationMs: played.inMilliseconds,
          // 피치 조절 도입 전까지 원키로 기록한다.
          pitchSemitones: 0,
          backingTrackSlot: snapshot.trackSlot,
        ),
      );
    }

    await _store.save(_sessions);
  }

  PracticeSession? _lastSessionFor(String songId) {
    for (var i = _sessions.length - 1; i >= 0; i--) {
      if (_sessions[i].songId == songId) return _sessions[i];
    }
    return null;
  }
}
