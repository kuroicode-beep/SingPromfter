// file: lib/services/practice_log_service.dart
//
// 연습 세션 적재 규칙과 집계를 담당한다. 판정 규칙은 순수 함수로 분리해
// 테스트 가능하게 두고, 이 클래스는 저장·집계만 조율한다.
//
// 🔴 v5.17.0: 메모리 목록을 통째로 저장하지 않는다. 이 목록은 부팅 때 한 번 읽은
// 것이라 그사이 폰 동기화·백업 가져오기가 디스크에 합친 세션을 모른다 — 통째로
// 쓰면 그 세션들을 덮는다. **바뀐 세션만** 디스크 기록에 합치고, 합친 결과를 되받는다.
import 'package:uuid/uuid.dart';

import '../controllers/playback_controller.dart';
import '../models/practice_session.dart';
import '../repository/practice_log_store.dart';
import 'atomic_json_file.dart';

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

  /// 디스크에 아직 못 닿은 세션(id → 세션). 다음 기록 때 함께 싣는다.
  final Map<String, PracticeSession> _unsaved = {};

  PracticeLogService({PracticeLogStore? store, Uuid? uuid})
    : _store = store ?? PracticeLogStore(),
      _uuid = uuid ?? const Uuid();

  List<PracticeSession> get sessions => List.unmodifiable(_sessions);

  /// 곡별 누적(횟수·총 시간·최근 연습일·주 사용 키).
  List<PracticeSummary> get summaries => PracticeSummary.summarize(_sessions);

  /// 마지막 [load]가 기록을 어디서 읽었는지(정본·백업·읽지 못함).
  AtomicLoadState get loadState => _store.lastLoadState;

  Future<void> load() async {
    _sessions = await _store.load();
  }

  /// 재생이 끝난 시점에 호출한다. 규칙에 맞으면 기록하거나 직전 세션에 합친다.
  /// 디스크에 닿았으면 true(기록할 게 없었던 경우 포함).
  Future<bool> record({
    required PlaybackSnapshot snapshot,
    required Duration played,
    DateTime? now,
  }) async {
    final song = snapshot.song;
    if (song == null) return true;
    if (!PracticeSessionRules.shouldRecord(played)) return true;

    final at = now ?? DateTime.now();
    final previous = _lastSessionFor(song.id);

    final PracticeSession changed;
    if (previous != null &&
        previous.id.isNotEmpty &&
        PracticeSessionRules.shouldMerge(
          previous: previous,
          songId: song.id,
          now: at,
        )) {
      changed = previous.copyWith(
        durationMs: previous.durationMs + played.inMilliseconds,
      );
    } else {
      changed = PracticeSession(
        id: _uuid.v4(),
        songId: song.id,
        songTitle: song.title,
        startedAt: at.subtract(played),
        durationMs: played.inMilliseconds,
        // 피치 조절 도입 전까지 원키로 기록한다.
        pitchSemitones: 0,
        backingTrackSlot: snapshot.trackSlot,
      );
    }

    // 화면이 곧바로 보도록 메모리부터 바꾼다.
    _sessions = mergePracticeSessions(_sessions, [changed], incomingWins: true);
    _unsaved[changed.id] = changed;

    // 🔴 목록을 통째로 쓰지 않는다 — 바뀐 세션만 **지금 디스크의 기록**에 합친다.
    final sent = _unsaved.values.toList(growable: false);
    final merged = await _store.merge(sent, incomingWins: true);
    // 못 썼으면 _unsaved에 남는다 — 다음 기록 때 함께 실린다.
    if (merged == null) return false;
    for (final session in sent) {
      if (identical(_unsaved[session.id], session)) _unsaved.remove(session.id);
    }
    // 디스크에는 폰·백업이 합친 세션도 있다 — 받아들이되, 기다리는 사이 메모리에서
    // 더 바뀐 세션은 메모리 쪽이 이긴다(이어 붙인 시간이 되돌아가지 않게).
    _sessions = mergePracticeSessions(
      merged,
      _unsaved.values.toList(growable: false),
      incomingWins: true,
    );
    return true;
  }

  /// 그 곡의 세션 가운데 **가장 늦게 끝난 것**. 목록에는 폰·백업에서 합쳐진 세션이
  /// 뒤에 붙어 있을 수 있어, 목록 순서가 곧 시간 순서는 아니다.
  PracticeSession? _lastSessionFor(String songId) {
    PracticeSession? latest;
    for (final session in _sessions) {
      if (session.songId != songId) continue;
      if (latest == null ||
          !session.startedAt
              .add(session.duration)
              .isBefore(latest.startedAt.add(latest.duration))) {
        latest = session;
      }
    }
    return latest;
  }
}
