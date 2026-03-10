import 'dart:convert';
import 'backing_track.dart';

class Song {
  final String id;
  final String title;
  final String lyricsPath;
  final String lyricsText;
  final List<BackingTrack> backingTracks;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Song({
    required this.id,
    required this.title,
    required this.lyricsPath,
    required this.lyricsText,
    required this.backingTracks,
    required this.createdAt,
    required this.updatedAt,
  });

  String get lyrics => lyricsText;

  String? get mrFileName => trackForSlot(1)?.fileName;

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

  Song copyWith({
    String? id,
    String? title,
    String? lyricsPath,
    String? lyricsText,
    List<BackingTrack>? backingTracks,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      lyricsPath: lyricsPath ?? this.lyricsPath,
      lyricsText: lyricsText ?? this.lyricsText,
      backingTracks: backingTracks ?? this.backingTracks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'lyricsPath': lyricsPath,
        'lyricsText': lyricsText,
        'backingTracks': backingTracks.map((e) => e.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
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
      lyricsPath: json['lyricsPath'] as String? ?? '${json['id']}.txt',
      lyricsText: json['lyricsText'] as String? ?? json['lyrics'] as String? ?? '',
      backingTracks: rawTracks,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
    );
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

