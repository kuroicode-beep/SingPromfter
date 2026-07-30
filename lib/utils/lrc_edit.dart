// file: lib/utils/lrc_edit.dart
//
// LRC 원문 편집 순수 함수 — STT 세그먼트로 LRC 만들기, 한 줄 텍스트 교체.
//
// 파일 전체를 파서 모델로 왕복시키지 않고 원문 문자열을 직접 다룬다 —
// 태그·주석·순서 등 우리가 모르는 정보를 잃지 않기 위해서다.
// (드리프트 재타이밍 lrc_retime.dart와 같은 원칙)

/// STT 한 구간.
class SttSegment {
  final double startSeconds;
  final double endSeconds;
  final String text;

  const SttSegment({
    required this.startSeconds,
    required this.endSeconds,
    required this.text,
  });
}

/// STT 세그먼트를 줄 단위 LRC로 만든다.
///
/// [duration]을 알면 곡 길이 밖에서 시작하는 세그먼트를 버린다 —
/// Whisper가 페이드아웃 잔향에서 존재하지 않는 가사를 지어내는 일이
/// 실측으로 확인됐다(「너를 사랑하고도」 256초 곡에서 261초 가사).
String lrcFromSttSegments(
  List<SttSegment> segments, {
  String? title,
  String? artist,
  Duration? duration,
}) {
  final buffer = StringBuffer();
  if (title != null && title.trim().isNotEmpty) {
    buffer.writeln('[ti:${title.trim()}]');
  }
  if (artist != null && artist.trim().isNotEmpty) {
    buffer.writeln('[ar:${artist.trim()}]');
  }
  final limit = duration?.inMilliseconds;
  for (final seg in segments) {
    final text = seg.text.trim();
    if (text.isEmpty) continue;
    final ms = (seg.startSeconds * 1000).round();
    if (ms < 0) continue;
    if (limit != null && ms >= limit) continue;
    buffer.writeln('[${_formatTag(ms)}]$text');
  }
  return buffer.toString();
}

String _formatTag(int ms) {
  final minutes = ms ~/ 60000;
  final seconds = (ms % 60000) / 1000;
  final secStr = seconds.toStringAsFixed(2).padLeft(5, '0');
  return '${minutes.toString().padLeft(2, '0')}:$secStr';
}

final _timeTag = RegExp(r'^((?:\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\])+)(.*)$');
final _firstTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

/// 표시 줄 [displayIndex]의 텍스트를 [newText]로 바꾼 LRC 원문을 돌려준다.
///
/// 표시 줄 순서는 파서(TimedLyrics)와 같은 규약 — **시각순 정렬** 후의
/// 인덱스다(파일 나열 순서가 아니라). 타임스탬프·메타 태그는 건드리지
/// 않는다. 해당 줄을 못 찾으면 null.
String? replaceLrcLineText(
  String raw, {
  required int displayIndex,
  required String newText,
}) {
  if (displayIndex < 0) return null;
  final lines = raw.split('\n');

  // 타임태그가 붙은 원문 줄들을 (시각, 원문 줄 번호)로 모은다.
  final entries = <({int timeMs, int rawLine})>[];
  for (var i = 0; i < lines.length; i++) {
    final match = _timeTag.firstMatch(lines[i].trimRight());
    if (match == null) continue;
    final tag = _firstTag.firstMatch(match.group(1)!);
    if (tag == null) continue;
    final minutes = int.parse(tag.group(1)!);
    final seconds = int.parse(tag.group(2)!);
    final fracRaw = tag.group(3) ?? '0';
    final fracMs = switch (fracRaw.length) {
      1 => int.parse(fracRaw) * 100,
      2 => int.parse(fracRaw) * 10,
      _ => int.parse(fracRaw.substring(0, 3)),
    };
    entries.add((
      timeMs: minutes * 60000 + seconds * 1000 + fracMs,
      rawLine: i,
    ));
  }
  if (displayIndex >= entries.length) return null;

  // 파서와 같은 시각순(안정 정렬)으로 표시 인덱스를 원문 줄로 되돌린다.
  final order = List<int>.generate(entries.length, (i) => i);
  order.sort((a, b) {
    final diff = entries[a].timeMs - entries[b].timeMs;
    return diff != 0 ? diff : a - b;
  });
  final rawLine = entries[order[displayIndex]].rawLine;

  final match = _timeTag.firstMatch(lines[rawLine].trimRight())!;
  lines[rawLine] = '${match.group(1)}${newText.trim()}';
  return lines.join('\n');
}
