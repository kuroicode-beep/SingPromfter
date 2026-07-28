// file: lib/models/song_draft.dart
//
// 곡 등록/수정 다이얼로그가 화면에 돌려주는 임시 입력 모델.
class SongDraft {
  final String title;
  final String artist;
  final Map<int, String> trackPaths;
  final Map<int, String> trackLabels;
  final Map<int, int?> trackStartMs;
  final Map<int, int?> trackEndMs;

  /// 파일에 이미 구워 넣은 키(키조절 슬롯만 0이 아니다).
  final Map<int, int> trackBakedSemitones;

  const SongDraft({
    required this.title,
    this.artist = '',
    required this.trackPaths,
    this.trackLabels = const {},
    this.trackStartMs = const {},
    this.trackEndMs = const {},
    this.trackBakedSemitones = const {},
  });
}

class SongEditDraft {
  final String title;
  final String artist;
  final String? lyricsText;
  final Map<int, String> trackPaths;
  final Map<int, String> trackLabels;
  final Map<int, int?> trackStartMs;
  final Map<int, int?> trackEndMs;

  const SongEditDraft({
    required this.title,
    this.artist = '',
    required this.lyricsText,
    required this.trackPaths,
    this.trackLabels = const {},
    this.trackStartMs = const {},
    this.trackEndMs = const {},
  });
}
