class BackingTrack {
  final int slot;
  final String fileName;
  final String label;

  const BackingTrack({
    required this.slot,
    required this.fileName,
    required this.label,
  });

  Map<String, dynamic> toJson() => {
        'slot': slot,
        'fileName': fileName,
        'label': label,
      };

  factory BackingTrack.fromJson(Map<String, dynamic> json) => BackingTrack(
        slot: (json['slot'] as num?)?.toInt() ?? 1,
        fileName: json['fileName'] as String? ?? '',
        label: json['label'] as String? ?? 'MR',
      );
}

