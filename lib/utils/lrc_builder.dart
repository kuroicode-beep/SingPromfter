// file: lib/utils/lrc_builder.dart
//
// 가사를 곡 길이에 맞춰 균등 배치한 LRC를 만든다. (순수 함수 — 테스트 대상)
//
// AI 생성곡은 LRCLIB에 싱크 가사가 없으므로, 줄을 시간축에 고르게 깔고
// 이후 DSP 정렬(autoAlignLyrics)로 전체 오프셋을 보정하는 방식으로
// "대략 맞는" 싱크 가사를 얻는다. 완벽하진 않지만 연습에는 충분하다.

/// [verse]/[chorus] 같은 구조 태그 줄인지.
bool isStructureTagLine(String line) =>
    RegExp(r'^\s*\[[a-zA-Z ]+\]\s*$').hasMatch(line);

/// 가사에서 노래할 줄만 뽑는다(빈 줄·구조 태그 제외).
List<String> singableLines(String lyrics) => lyrics
    .split(RegExp(r'\r?\n'))
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty && !isStructureTagLine(l))
    .toList(growable: false);

/// 균등 배치 LRC. 줄이 없거나 길이가 너무 짧으면 null.
///
/// 첫 줄은 전주를 감안해 길이의 8%(최대 15초) 지점에서 시작하고,
/// 마지막 줄은 96% 지점 전에 끝난다.
String? buildEvenlySpacedLrc(String lyrics, {required int durationSec}) {
  final lines = singableLines(lyrics);
  if (lines.isEmpty || durationSec < 30) return null;

  final startSec = (durationSec * 0.08).clamp(3.0, 15.0);
  final endSec = durationSec * 0.96;
  if (endSec <= startSec) return null;

  final step =
      lines.length == 1 ? 0.0 : (endSec - startSec) / (lines.length - 1);

  final buffer = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    final t = startSec + step * i;
    final minutes = (t ~/ 60).toString().padLeft(2, '0');
    final seconds = (t % 60).floor().toString().padLeft(2, '0');
    final centis = (((t % 1) * 100).floor()).toString().padLeft(2, '0');
    buffer.writeln('[$minutes:$seconds.$centis]${lines[i]}');
  }
  return buffer.toString();
}
