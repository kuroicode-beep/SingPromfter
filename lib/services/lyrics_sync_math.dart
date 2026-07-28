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

  /// [TimedLyrics.indexAt]이 비교하는 것과 **같은 축**의 시각.
  /// LRC 파일 자체의 `[offset:]`(= [TimedLyrics.offsetMs])까지 빼 준다.
  ///
  /// [songTimeFor]는 이 값을 빼지 않는다 — 그건 `indexAt` 안에서 처리된다.
  /// 줄 안의 진행률을 재려면 반드시 여기까지 내려와야 파일 오프셋만큼
  /// 어긋나지 않는다.
  ///
  /// [songTimeFor]와 달리 0으로 막지 **않는다**. 첫 줄이 시작되기 전(인트로)을
  /// 구분해야 하는데, 0으로 막으면 그 구간이 전부 "첫 줄의 시작"으로 뭉개진다.
  static Duration lyricsTimeFor({
    required Duration playerPosition,
    required TimedLyrics lyrics,
    int? trackStartMs,
    int lyricsOffsetMs = 0,
  }) {
    final ms =
        playerPosition.inMilliseconds -
        (trackStartMs ?? 0) -
        lyricsOffsetMs -
        lyrics.offsetMs;
    return Duration(milliseconds: ms);
  }

  /// 현재 줄 안에서의 진행률 0..1. 스윕하면 안 되는 상황에서는 null.
  ///
  /// null을 주는 경우:
  ///  - [lyricsTime]이 [start]보다 이르다 — 인트로이거나 줄이 아직 시작 전.
  ///    ([TimedLyrics.indexAt]은 첫 줄 이전에도 0을 돌려주므로, 이 가드가
  ///     없으면 인트로 내내 0번 줄을 훑는다.)
  ///  - [end]를 모른다(마지막 줄 + 곡 끝 미상).
  ///  - [end]가 [start]보다 이르거나 같다(깨진 LRC).
  static double? lineProgress({
    required Duration lyricsTime,
    required Duration start,
    Duration? end,
    Duration? maxSweep,
  }) {
    if (end == null) return null;
    if (lyricsTime < start) return null;

    var span = end - start;
    if (span <= Duration.zero) return null;
    if (maxSweep != null && maxSweep > Duration.zero && maxSweep < span) {
      span = maxSweep;
    }

    final t = (lyricsTime - start).inMicroseconds / span.inMicroseconds;
    return t.clamp(0.0, 1.0);
  }

  /// 간주 가드 — 한 줄에 배정된 시간이 글자 수에 비해 지나치게 길면
  /// 스윕 구간을 잘라낸다.
  ///
  /// LRC는 간주 앞 줄에 40초를 통째로 주는 일이 흔하다. 그 줄을 한 글자씩
  /// 기어가면 오히려 "지금 어디인지"를 잃는다. 다 훑고 나면 꽉 찬 채로 기다린다.
  static Duration sweepWindow(
    String text,
    Duration span, {
    Duration perChar = const Duration(milliseconds: 700),
    Duration min = const Duration(seconds: 2),
    Duration max = const Duration(seconds: 12),
  }) {
    if (span <= Duration.zero) return Duration.zero;
    final chars = text.trim().runes.length;
    var window = perChar * chars;
    if (window < min) window = min;
    if (window > max) window = max;
    return window < span ? window : span;
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
