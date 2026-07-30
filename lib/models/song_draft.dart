// file: lib/models/song_draft.dart
//
// 곡 등록/수정 다이얼로그가 화면에 돌려주는 임시 입력 모델.
import '../utils/music_key.dart';

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

  /// 곡 조성을 이 편집에서 다룰지. false면 기존 값을 그대로 둔다 —
  /// 조성 칸이 없는 경로(제어 API 등)가 자동 감지 결과를 지우지 않게 한다.
  final bool applyMusicalKey;

  /// [applyMusicalKey]가 true일 때 넣을 값. null이면 지운다.
  final MusicKey? musicalKey;

  /// 슬롯별 '이미 파일에 구워진' 키(반음). 조성 표시를 바로잡는 값이며
  /// 재생에는 쓰지 않는다(이중 적용 방지).
  final Map<int, int> trackBakedSemitones;

  /// 슬롯별 재생 키(반음) — 파일은 그대로 두고 재생할 때 변환하는 값.
  /// songs.json이 아니라 설정(pitchSemitonesBySong)에 저장되므로 곡 저장과
  /// 별도로 반영한다. 맵에 없는 슬롯은 건드리지 않는다는 뜻이다.
  final Map<int, int> trackPitchSemitones;

  const SongEditDraft({
    required this.title,
    this.artist = '',
    required this.lyricsText,
    required this.trackPaths,
    this.trackLabels = const {},
    this.trackStartMs = const {},
    this.trackEndMs = const {},
    this.applyMusicalKey = false,
    this.musicalKey,
    this.trackBakedSemitones = const {},
    this.trackPitchSemitones = const {},
  });
}
