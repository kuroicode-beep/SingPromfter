import 'dart:convert';

class QueueItem {
  final String songId;
  final int? selectedTrackSlot;
  final DateTime queuedAt;

  const QueueItem({
    required this.songId,
    this.selectedTrackSlot,
    required this.queuedAt,
  });

  Map<String, dynamic> toJson() => {
        'songId': songId,
        'selectedTrackSlot': selectedTrackSlot,
        'queuedAt': queuedAt.toIso8601String(),
      };

  factory QueueItem.fromJson(Map<String, dynamic> json) => QueueItem(
        songId: json['songId'] as String,
        selectedTrackSlot: (json['selectedTrackSlot'] as num?)?.toInt(),
        queuedAt: DateTime.tryParse(json['queuedAt'] as String? ?? '') ?? DateTime.now(),
      );

  static String encodeList(List<QueueItem> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  static List<QueueItem> decodeList(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => QueueItem.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }
}

