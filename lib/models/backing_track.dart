class BackingTrack {
  final int slot;
  final String fileName;
  final String label;
  final int? startMs;
  final int? endMs;

  const BackingTrack({
    required this.slot,
    required this.fileName,
    required this.label,
    this.startMs,
    this.endMs,
  });

  Map<String, dynamic> toJson() => {
    'slot': slot,
    'fileName': fileName,
    'label': label,
    'startMs': startMs,
    'endMs': endMs,
  };

  factory BackingTrack.fromJson(Map<String, dynamic> json) => BackingTrack(
    slot: (json['slot'] as num?)?.toInt() ?? 1,
    fileName: json['fileName'] as String? ?? '',
    label: json['label'] as String? ?? 'MR',
    startMs: (json['startMs'] as num?)?.toInt(),
    endMs: (json['endMs'] as num?)?.toInt(),
  );
}
