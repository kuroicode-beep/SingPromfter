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

  /// Whisper 신뢰도(있으면) — 환청 필터의 근거. 서버가 word_timestamps=1일
  /// 때만 채워 준다. null이면 필터는 이 근거를 건너뛴다.
  final double? noSpeechProb;
  final double? avgLogprob;

  /// 첫 단어의 발성 시각(초). 세그먼트 시작보다 정밀하다 —
  /// Whisper 세그먼트 경계는 초 단위로 뭉툭한 일이 많다.
  final double? firstWordStartSeconds;

  const SttSegment({
    required this.startSeconds,
    required this.endSeconds,
    required this.text,
    this.noSpeechProb,
    this.avgLogprob,
    this.firstWordStartSeconds,
  });

  /// 줄 시작으로 쓸 시각 — 단어 타임스탬프가 있으면 그쪽.
  double get lineStartSeconds => firstWordStartSeconds ?? startSeconds;

  SttSegment copyWith({double? startSeconds, String? text}) => SttSegment(
    startSeconds: startSeconds ?? this.startSeconds,
    endSeconds: endSeconds,
    text: text ?? this.text,
    noSpeechProb: noSpeechProb,
    avgLogprob: avgLogprob,
    // 시작을 손봤다면 그 값이 곧 줄 시작이다 — 옛 단어 시각을 남기지 않는다.
    firstWordStartSeconds: startSeconds ?? firstWordStartSeconds,
  );
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
    final ms = (seg.lineStartSeconds * 1000).round();
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

/// 앞당김이 위 줄과 겹치지 않게 남겨 두는 최소 간격(ms).
const int lrcShiftMinGapMs = 10;

/// 표시 줄 [displayIndex]부터(시각순) 이후의 **모든 타임스탬프**를
/// [deltaMs]만큼 옮긴 LRC 원문과 실제 적용된 이동량을 돌려준다.
/// 그 앞 줄들은 건드리지 않는다 — "밑에서 맞추면 위가 틀어지는"
/// 전체 오프셋의 한계를 푸는 부분 보정.
///
/// 기준은 그 줄의 시각이다: 같은 시각 이후의 태그는 후렴 반복
/// (한 줄에 태그 여러 개)까지 포함해 전부 함께 움직인다.
///
/// **순서 보존**: 앞당김(음수)은 바로 위 줄의 시각을 넘지 못하게 잘린다 —
/// 넘어서면 파서가 시각순으로 재정렬해 줄 순서가 뒤섞이고, 하이라이트가
/// 위아래로 널뛴다(실사용 보고 "가사가 춤을 춰"). 더 못 당기면
/// appliedDeltaMs가 0이 된다. 결과 시각이 음수면 0으로 자른다.
/// 해당 줄이 없으면 null.
({String lrc, int appliedDeltaMs})? shiftLrcFromLine(
  String raw, {
  required int displayIndex,
  required int deltaMs,
}) {
  if (displayIndex < 0) return null;

  // 파서(TimedLyrics)와 같은 규약으로 표시 줄 목록을 만든다:
  // 본문 있는 줄의 타임태그 하나가 표시 줄 하나, 시각순 안정 정렬.
  final lines = raw.split('\n');
  final times = <int>[];
  for (final line in lines) {
    final match = _timeTag.firstMatch(line.trimRight());
    if (match == null) continue;
    if (match.group(2)!.trim().isEmpty) continue;
    for (final tag in _firstTag.allMatches(match.group(1)!)) {
      times.add(_tagToMs(tag));
    }
  }
  if (displayIndex >= times.length) return null;
  times.sort();
  final thresholdMs = times[displayIndex];

  var applied = deltaMs;
  if (deltaMs < 0 && displayIndex > 0) {
    // 블록의 맨 앞(=기준 줄)이 바로 위 줄보다 뒤에 남아야 순서가 지켜진다.
    final maxBelow = times[displayIndex - 1];
    final floor = maxBelow + lrcShiftMinGapMs - thresholdMs;
    if (applied < floor) applied = floor;
    if (applied > 0) applied = 0; // 위 줄과 이미 붙어 있으면 못 당긴다.
  }
  if (applied == 0) return (lrc: raw, appliedDeltaMs: 0);

  String format(int ms) {
    final clamped = ms < 0 ? 0 : ms;
    final minutes = clamped ~/ 60000;
    final seconds = (clamped % 60000) / 1000;
    return '[${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toStringAsFixed(2).padLeft(5, '0')}]';
  }

  final shifted = lines
      .map((line) {
        final match = _timeTag.firstMatch(line.trimRight());
        if (match == null) return line;
        if (match.group(2)!.trim().isEmpty) return line;
        return line.replaceAllMapped(_firstTag, (tag) {
          final ms = _tagToMs(tag);
          if (ms < thresholdMs) return tag.group(0)!;
          return format(ms + applied);
        });
      })
      .join('\n');
  return (lrc: shifted, appliedDeltaMs: applied);
}

/// 파서(LrcParser)와 같은 소수부 해석: 3자리=1/1000초, 그 외=×10.
int _tagToMs(Match tag) {
  final minutes = int.parse(tag.group(1)!);
  final seconds = int.parse(tag.group(2)!);
  final fracRaw = tag.group(3);
  var millis = 0;
  if (fracRaw != null && fracRaw.isNotEmpty) {
    final value = int.parse(fracRaw);
    millis = fracRaw.length == 3 ? value : value * 10;
  }
  return minutes * 60000 + seconds * 1000 + millis;
}

/// 표시 줄 [displayIndex]를 지운 LRC 원문과 지워진 텍스트를 돌려준다.
///
/// 노래가 끝난 뒤에도 이어지는 환청 줄(STT가 페이드아웃에서 지어낸 가사)을
/// D 단축키로 지우는 입구. 다중 태그(후렴 반복) 줄은 해당 시각의 태그
/// 하나만 지우고, 마지막 태그였으면 원문 줄 전체를 지운다.
/// 해당 줄이 없으면 null.
({String lrc, String removedText})? removeLrcLine(
  String raw, {
  required int displayIndex,
}) {
  if (displayIndex < 0) return null;
  final lines = raw.split('\n');

  // 파서(TimedLyrics)와 같은 규약: 본문 있는 줄의 태그 하나가 표시 줄 하나.
  final entries = <({int timeMs, int rawLine, int tagStart, int tagEnd})>[];
  for (var i = 0; i < lines.length; i++) {
    final match = _timeTag.firstMatch(lines[i].trimRight());
    if (match == null) continue;
    if (match.group(2)!.trim().isEmpty) continue;
    for (final tag in _firstTag.allMatches(match.group(1)!)) {
      entries.add((
        timeMs: _tagToMs(tag),
        rawLine: i,
        tagStart: tag.start,
        tagEnd: tag.end,
      ));
    }
  }
  if (displayIndex >= entries.length) return null;

  final order = List<int>.generate(entries.length, (i) => i);
  order.sort((a, b) {
    final diff = entries[a].timeMs - entries[b].timeMs;
    return diff != 0 ? diff : a - b;
  });
  final target = entries[order[displayIndex]];

  final rawLine = lines[target.rawLine];
  final match = _timeTag.firstMatch(rawLine.trimRight())!;
  final tags = match.group(1)!;
  final text = match.group(2)!.trim();
  final tagCount = _firstTag.allMatches(tags).length;

  final out = <String>[];
  for (var i = 0; i < lines.length; i++) {
    if (i != target.rawLine) {
      out.add(lines[i]);
      continue;
    }
    if (tagCount <= 1) continue; // 태그가 하나뿐이면 줄 전체 삭제
    final newTags =
        tags.substring(0, target.tagStart) + tags.substring(target.tagEnd);
    out.add('$newTags$text');
  }
  return (lrc: out.join('\n'), removedText: text);
}

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
