import 'dart:convert';

import '../utils/music_key.dart';
import 'backing_track.dart';
import 'track_variant.dart';

class Song {
  final String id;
  final String title;
  final String artist;
  final String lyricsPath;
  final String lyricsText;
  final List<BackingTrack> backingTracks;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isFavorite;

  /// 싱크 가사 파일명(data/lrc 안). 없으면 null.
  final String? lrcFileName;

  /// 곡의 조성(원곡 기준). 자동 감지하거나 사용자가 지정한다.
  /// 실제로 들리는 조성은 여기에 구운 키·사용자 키를 더한 값이다.
  final MusicKey? musicalKey;

  /// 싱크 잠금(L 토글). 켜져 있으면 싱크 조절 동작 전부가 거부된다 —
  /// 다 맞춘 싱크를 노래 중 오타로 망가뜨리지 않기 위한 자물쇠.
  final bool syncLocked;

  const Song({
    required this.id,
    required this.title,
    this.artist = '',
    required this.lyricsPath,
    required this.lyricsText,
    required this.backingTracks,
    required this.createdAt,
    required this.updatedAt,
    this.isFavorite = false,
    this.lrcFileName,
    this.musicalKey,
    this.syncLocked = false,
  });

  String get lyrics => lyricsText;

  bool get hasMr => backingTracks.isNotEmpty;

  List<int> get availableTrackSlots {
    final slots = backingTracks.map((e) => e.slot).toList()..sort();
    return slots;
  }

  BackingTrack? trackForSlot(int slot) {
    for (final track in backingTracks) {
      if (track.slot == slot) return track;
    }
    return null;
  }

  /// 가사 싱크 오프셋을 [slot]과 **같은 녹음을 쓰는 슬롯들**에 함께 적용한다.
  ///
  /// 1·2·3번(원곡·MR·키조절)은 같은 녹음이라 한 번 맞추면 셋 다 맞고, 4번
  /// (노래방)은 다른 녹음이라 자기 값만 갖는다 — 규약은 [lyricsSyncSlotGroup].
  /// 그래서 슬롯을 바꿔 가며 불러도 맞춰 둔 싱크가 유지된다.
  ///
  /// [slot]이 없는 곡이면 아무것도 바꾸지 않고 자기 자신을 돌려준다.
  Song withLyricsOffsetForSlot(int slot, int offsetMs) {
    if (trackForSlot(slot) == null) return this;
    final group = lyricsSyncSlotGroup(slot);
    return copyWith(
      backingTracks: backingTracks
          .map(
            (t) => group.contains(t.slot)
                ? t.copyWith(lyricsOffsetMs: offsetMs)
                : t,
          )
          .toList(growable: false),
      updatedAt: DateTime.now(),
    );
  }

  Song copyWith({
    String? id,
    String? title,
    String? artist,
    String? lyricsPath,
    String? lyricsText,
    List<BackingTrack>? backingTracks,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isFavorite,
    String? lrcFileName,
    MusicKey? musicalKey,
    bool? syncLocked,
    bool clearLrcFileName = false,
    bool clearMusicalKey = false,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      lyricsPath: lyricsPath ?? this.lyricsPath,
      lyricsText: lyricsText ?? this.lyricsText,
      backingTracks: backingTracks ?? this.backingTracks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      lrcFileName: clearLrcFileName
          ? null
          : (lrcFileName ?? this.lrcFileName),
      musicalKey: clearMusicalKey
          ? null
          : (musicalKey ?? this.musicalKey),
      syncLocked: syncLocked ?? this.syncLocked,
    );
  }

  /// 가사 본문까지 포함한 전체 직렬화.
  ///
  /// [toMetaJson]을 그대로 확장하므로 새 필드는 [toMetaJson]에만 추가하면 된다.
  /// (두 직렬화기가 갈려 필드가 조용히 누락되던 문제를 구조적으로 차단)
  Map<String, dynamic> toJson() => {...toMetaJson(), 'lyricsText': lyricsText};

  /// songs.json·백업에 저장되는 메타데이터. 가사 본문은 별도 txt 파일에 둔다.
  Map<String, dynamic> toMetaJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'lyricsPath': lyricsPath,
    'backingTracks': backingTracks.map((e) => e.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'isFavorite': isFavorite,
    'lrcFileName': lrcFileName,
    'musicalKey': musicalKey?.storageValue,
    'syncLocked': syncLocked,
  };

  factory Song.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final rawTracks = (json['backingTracks'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(BackingTrack.fromJson)
        .toList();

    final legacyMr = (json['mrFileName'] as String?)?.trim();
    if (rawTracks.isEmpty && legacyMr != null && legacyMr.isNotEmpty) {
      rawTracks.add(BackingTrack(slot: 1, fileName: legacyMr, label: 'MR1'));
    }

    rawTracks.sort((a, b) => a.slot.compareTo(b.slot));

    return Song(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      lyricsPath: json['lyricsPath'] as String? ?? '${json['id']}.txt',
      lyricsText:
          json['lyricsText'] as String? ?? json['lyrics'] as String? ?? '',
      backingTracks: rawTracks,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
      isFavorite: json['isFavorite'] as bool? ?? false,
      lrcFileName: json['lrcFileName'] as String?,
      musicalKey: MusicKey.fromStorage(json['musicalKey'] as String?),
      syncLocked: json['syncLocked'] as bool? ?? false,
    );
  }

  factory Song.fromMetaJson(
    Map<String, dynamic> json, {
    String lyricsText = '',
  }) {
    return Song.fromJson({...json, 'lyricsText': lyricsText});
  }

  static String encodeList(List<Song> songs) =>
      jsonEncode(songs.map((s) => s.toJson()).toList());

  static List<Song> decodeList(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Song.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }
}
