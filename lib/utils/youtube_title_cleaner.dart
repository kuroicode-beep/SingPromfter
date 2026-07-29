// file: lib/utils/youtube_title_cleaner.dart
//
// 유튜브 영상 제목에서 MR/노래방/키 표기 같은 노이즈를 걷어내고,
// "가수 - 제목" 패턴이면 가수와 제목을 분리한다. (순수 함수)
//
// 정제된 제목은 곡 등록과 LRCLIB 가사 검색 양쪽에 쓰인다 —
// 노이즈가 남으면 가사 적중률이 크게 떨어진다.

/// 정제 결과. [artist]는 분리에 성공했을 때만 채워진다.
class CleanedSongName {
  final String title;
  final String? artist;

  const CleanedSongName({required this.title, this.artist});
}

/// 괄호 안 내용이 "노이즈"인지 판정하는 패턴들.
/// (feat. …) 같은 의미 있는 괄호는 여기 걸리지 않아 보존된다.
final List<RegExp> _noisePatterns = [
  RegExp(r'^mr$', caseSensitive: false),
  RegExp(r'^inst\.?$', caseSensitive: false),
  RegExp(r'^instrumental$', caseSensitive: false),
  RegExp(
    r'^official\s*(audio|video|mv|m/v|lyric\s*video|lyrics)?$',
    caseSensitive: false,
  ),
  RegExp(r'^(audio|lyrics|lyric\s*video)$', caseSensitive: false),
  RegExp(r'노래방'),
  RegExp(r'코인\s*노래방'),
  RegExp(r'^karaoke(\s*version)?$', caseSensitive: false),
  RegExp(r'^(ky|tj)\s*\.?\s*\d*$', caseSensitive: false),
  RegExp(r'멜로디\s*(제거|포함)'),
  // 키 표기: "-2키", "+1 key", "여자키", "남자키", "원키"
  RegExp(r'^[-+]?\d+\s*(키|key)$', caseSensitive: false),
  RegExp(r'^(여자|남자|원)\s*키$'),
  RegExp(r'^(커버|cover)(\s*by\s*.+)?$', caseSensitive: false),
  // 가사 영상 계열: "(가사첨부)", "(한글 가사)", "[가사/번역]", "(자막)".
  // 실제 사고: "윤후 - 선물(가사첨부)"의 (가사첨부)가 남아 곡 제목이 되고,
  // 그 제목으로는 LRCLIB 검색이 실패했다.
  RegExp(r'^(한글|한국어)?\s*가사(\s*(첨부|포함|자막|번역|비디오|영상))?$'),
  RegExp(r'^(한글|한국어)?\s*자막$'),
  RegExp(r'^번역$'),
  RegExp(r'^(고음질\s*)?음원(\s*첨부)?$'),
  RegExp(r'^고음질$'),
  RegExp(r'^(mv|m/v|pv|뮤직비디오)$', caseSensitive: false),
  RegExp(r'^(hd|hq|4k|8k|2160p|1440p|1080p|720p)$', caseSensitive: false),
  RegExp(r'^full\s*(audio|ver\.?|version)?$', caseSensitive: false),
  RegExp(r'^color\s*coded(\s*lyrics)?$', caseSensitive: false),
  RegExp(r'^(eng|kor|han|rom)\s*subs?$', caseSensitive: false),
];

/// 복합 괄호 내용용: 내용 전체가 노이즈 토큰들의 나열이면 노이즈로 본다.
/// 예: "MR/Instrumental", "노래방 MR", "TJ 12345 여자키"
bool _isNoiseContent(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return true;
  if (_noisePatterns.any((p) => p.hasMatch(trimmed))) return true;

  // 구분자로 쪼개 전 조각이 노이즈면 전체를 노이즈로 판단한다.
  final parts = trimmed
      .split(RegExp(r'[/,·\s]+'))
      .where((p) => p.isNotEmpty)
      .toList(growable: false);
  if (parts.length < 2) return false;
  return parts.every((p) => _noisePatterns.any((r) => r.hasMatch(p)));
}

/// 괄호 블록([]/()/【】)을 찾아 노이즈만 제거한다.
String _stripNoiseBrackets(String input) {
  final bracket = RegExp(r'\[([^\[\]]*)\]|\(([^()]*)\)|【([^【】]*)】');
  var result = input;
  // 중첩 없는 단순 괄호를 반복 처리한다.
  for (var i = 0; i < 3; i++) {
    var changed = false;
    result = result.replaceAllMapped(bracket, (m) {
      final content = m[1] ?? m[2] ?? m[3] ?? '';
      if (_isNoiseContent(content)) {
        changed = true;
        return '';
      }
      return m[0]!;
    });
    if (!changed) break;
  }
  return result;
}

/// 괄호 밖에 남은 노이즈 토큰(MR, 노래방, 키 표기)을 앞뒤에서 제거한다.
String _stripBareNoiseTokens(String input) {
  final bare = RegExp(
    r'(^|\s)(mr|inst\.?|instrumental|karaoke|노래방|코인노래방|'
    r'[-+]?\d+\s*(?:키|key)|(?:여자|남자|원)\s*키)(?=\s|$)',
    caseSensitive: false,
  );
  return input.replaceAll(bare, ' ');
}

String _collapseSpaces(String input) =>
    input.replaceAll(RegExp(r'\s+'), ' ').trim();

/// 앞뒤에 남은 구분자 찌꺼기(" - ", "|" 등)를 정리한다.
String _trimSeparators(String input) {
  return input
      .replaceAll(RegExp(r'^[\s\-–—|/·]+'), '')
      .replaceAll(RegExp(r'[\s\-–—|/·]+$'), '')
      .trim();
}

/// "가수 - 제목" 분리 시도. 정확히 2조각일 때만 성공으로 본다.
({String artist, String title})? _splitArtistTitle(
  String cleaned, {
  String uploader = '',
}) {
  for (final sep in const ['-', '–', '—', '|']) {
    // 구분자 앞뒤에 공백이 있는 경우만 인정한다 — "Semi-Final" 같은 단어 보호.
    final parts = cleaned.split(' $sep ');
    if (parts.length != 2) continue;
    final left = _trimSeparators(parts[0]);
    final right = _trimSeparators(parts[1]);
    if (left.isEmpty || right.isEmpty) return null;

    // 업로더(채널명)와 비슷한 쪽이 있으면 그쪽이 가수일 가능성이 높다.
    final up = uploader.trim().toLowerCase();
    if (up.isNotEmpty) {
      final l = left.toLowerCase();
      final r = right.toLowerCase();
      if (r.contains(up) || up.contains(r)) {
        return (artist: right, title: left);
      }
      if (l.contains(up) || up.contains(l)) {
        return (artist: left, title: right);
      }
    }
    // 관례상 "가수 - 제목" 순서가 압도적으로 많다.
    return (artist: left, title: right);
  }
  return null;
}

/// 유튜브 제목을 곡 등록용으로 정제한다.
///
/// 전부 지워지는 극단적 입력은 원제를 그대로 돌려준다(방어).
CleanedSongName cleanYoutubeSongName(String rawTitle, {String uploader = ''}) {
  final original = rawTitle.trim();
  if (original.isEmpty) return const CleanedSongName(title: '');

  var cleaned = _stripNoiseBrackets(original);
  cleaned = _stripBareNoiseTokens(cleaned);
  cleaned = _collapseSpaces(_trimSeparators(cleaned));

  if (cleaned.isEmpty) return CleanedSongName(title: original);

  final split = _splitArtistTitle(cleaned, uploader: uploader);
  if (split == null) return CleanedSongName(title: cleaned);
  return CleanedSongName(title: split.title, artist: split.artist);
}
