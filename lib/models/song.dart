import 'dart:convert';

class Song {
  final String id;
  final String title;
  final String lyrics;
  final String? mrFileName;

  const Song({
    required this.id,
    required this.title,
    required this.lyrics,
    this.mrFileName,
  });

  bool get hasMr => mrFileName != null && mrFileName!.isNotEmpty;

  Song copyWith({
    String? id,
    String? title,
    String? lyrics,
    String? mrFileName,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      lyrics: lyrics ?? this.lyrics,
      mrFileName: mrFileName ?? this.mrFileName,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'lyrics': lyrics,
        'mrFileName': mrFileName,
      };

  factory Song.fromJson(Map<String, dynamic> json) => Song(
        id: json['id'] as String,
        title: json['title'] as String,
        lyrics: json['lyrics'] as String? ?? '',
        mrFileName: json['mrFileName'] as String?,
      );

  static String encodeList(List<Song> songs) =>
      jsonEncode(songs.map((s) => s.toJson()).toList());

  static List<Song> decodeList(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
  }
}
