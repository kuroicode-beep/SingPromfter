// file: lib/services/lyrics_sync_math.dart
//
// 재생 위치 ↔ 가사 시각 변환. 순수 함수만 둔다.
//
// 부호 규약을 여기 한 곳에만 둔다. v2.5.0까지 컨트롤러는 오프셋을 더하고
// TimedLyrics.indexAt은 빼서, "음수 = 가사 먼저"라는 UI 약속과 반대로
// 가사가 늦게 뜨는 결함이 있었다.
//
// 규약: lyricsOffsetMs가 음수면 가사가 **먼저** 나온다.
//   songTime = playerPosition - trackStartMs - lyricsOffsetMs
// 즉 offset -1000ms면 songTime이 1초 앞서 계산돼 다음 줄로 일찍 넘어간다.
import '../models/timed_lyrics.dart';

class LyricsSyncMath {
  LyricsSyncMath._();

  /// 재생 위치를 가사 기준 시각으로 바꾼다. 음수면 0으로 막는다.
  static Duration songTimeFor({
    required Duration playerPosition,
    int? trackStartMs,
    int lyricsOffsetMs = 0,
  }) {
    final ms =
        playerPosition.inMilliseconds - (trackStartMs ?? 0) - lyricsOffsetMs;
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  /// [songTimeFor]의 역함수 — 특정 줄로 이동할 재생 위치를 구한다.
  ///
  /// LRC 자체 오프셋(`lyrics.offsetMs`)까지 되돌려야 `indexAt`과 왕복이 맞는다.
  static Duration playerPositionForLine({
    required TimedLyrics lyrics,
    required int index,
    int? trackStartMs,
    int lyricsOffsetMs = 0,
  }) {
    if (lyrics.isEmpty) return Duration.zero;
    final clamped = index.clamp(0, lyrics.lines.length - 1);
    final ms =
        lyrics.lines[clamped].time.inMilliseconds +
        lyrics.offsetMs +
        (trackStartMs ?? 0) +
        lyricsOffsetMs;
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  /// 트림 구간·곡 길이 안으로 재생 위치를 가둔다.
  static Duration clampToTrim(
    Duration target, {
    int? startMs,
    int? endMs,
    Duration? duration,
  }) {
    var ms = target.inMilliseconds;
    final lower = startMs ?? 0;
    if (ms < lower) ms = lower;

    final upperCandidates = <int>[
      ?endMs,
      if (duration != null && duration > Duration.zero)
        duration.inMilliseconds,
    ];
    if (upperCandidates.isNotEmpty) {
      final upper = upperCandidates.reduce((a, b) => a < b ? a : b);
      // 상한이 하한보다 작은 뒤집힌 설정에서는 하한을 지킨다.
      if (upper > lower && ms > upper) ms = upper;
    }
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }
}
