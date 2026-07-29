// file: lib/utils/lrc_retime.dart
//
// LRC 타임스탬프를 선형 보정(t' = scale·t + offset)으로 다시 쓴다. (순수 함수)
//
// 용도: 곡과 속도가 다른 판본의 LRC. 오프셋 하나로는 못 맞추지만
// 어긋남이 선형이면(실측 「넌 언제나」: +640ms→+3740ms 직선 증가)
// scale·offset 두 값으로 전 구간을 맞출 수 있다.

final RegExp _timestamp = RegExp(r'\[(\d+):(\d{1,2}(?:\.\d{1,3})?)\]');
final RegExp _offsetTag = RegExp(r'^\s*\[offset:\s*([+-]?\d+)\s*\]\s*$');

/// LRC 본문의 모든 타임스탬프를 t' = scale·(t + 파일오프셋) + offsetMs 로
/// 다시 쓴다. `[offset:]` 태그는 계산에 반영한 뒤 **제거한다**(구워 넣음) —
/// 남겨 두면 보정이 두 번 적용된다.
///
/// 가사 텍스트·메타 태그([ti:] 등)는 건드리지 않는다.
String retimeLrcContent(
  String raw, {
  required double scale,
  required int offsetMs,
}) {
  // 파일 자체의 [offset:] — 표시 시각 = 타임스탬프 + 이 값.
  var fileOffsetMs = 0;
  final lines = raw.split(RegExp(r'\r?\n'));
  final kept = <String>[];
  for (final line in lines) {
    final tag = _offsetTag.firstMatch(line);
    if (tag != null) {
      fileOffsetMs = int.tryParse(tag.group(1)!) ?? 0;
      continue; // 태그는 결과에 남기지 않는다.
    }
    kept.add(line);
  }

  String format(int ms) {
    final clamped = ms < 0 ? 0 : ms;
    final minutes = clamped ~/ 60000;
    final seconds = (clamped % 60000) / 1000;
    return '[${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toStringAsFixed(2).padLeft(5, '0')}]';
  }

  return kept
      .map(
        (line) => line.replaceAllMapped(_timestamp, (m) {
          final minutes = int.parse(m.group(1)!);
          final seconds = double.parse(m.group(2)!);
          final ms = minutes * 60000 + (seconds * 1000).round() + fileOffsetMs;
          return format((scale * ms + offsetMs).round());
        }),
      )
      .join('\n');
}
