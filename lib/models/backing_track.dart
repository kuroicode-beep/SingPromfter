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

  /// 일부 값만 바꾼 사본을 만든다.
  ///
  /// 파일명만 바꿔 다시 만들 때 [startMs]/[endMs] 같은 필드를 빠뜨리지 않도록
  /// 새 생성자 호출 대신 이 메서드를 쓴다.
  BackingTrack copyWith({
    int? slot,
    String? fileName,
    String? label,
    int? startMs,
    int? endMs,
    bool clearStartMs = false,
    bool clearEndMs = false,
  }) {
    return BackingTrack(
      slot: slot ?? this.slot,
      fileName: fileName ?? this.fileName,
      label: label ?? this.label,
      startMs: clearStartMs ? null : (startMs ?? this.startMs),
      endMs: clearEndMs ? null : (endMs ?? this.endMs),
    );
  }

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
