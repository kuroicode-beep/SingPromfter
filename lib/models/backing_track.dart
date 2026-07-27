class BackingTrack {
  final int slot;
  final String fileName;
  final String label;
  final int? startMs;
  final int? endMs;

  /// 이 반주에 맞춘 가사 오프셋(밀리초).
  /// 음수면 가사를 먼저 띄운다(읽을 시간 확보 — 프롬프터 기본 방향).
  final int lyricsOffsetMs;

  const BackingTrack({
    required this.slot,
    required this.fileName,
    required this.label,
    this.startMs,
    this.endMs,
    this.lyricsOffsetMs = 0,
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
    int? lyricsOffsetMs,
    bool clearStartMs = false,
    bool clearEndMs = false,
  }) {
    return BackingTrack(
      slot: slot ?? this.slot,
      fileName: fileName ?? this.fileName,
      label: label ?? this.label,
      startMs: clearStartMs ? null : (startMs ?? this.startMs),
      endMs: clearEndMs ? null : (endMs ?? this.endMs),
      lyricsOffsetMs: lyricsOffsetMs ?? this.lyricsOffsetMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'slot': slot,
    'fileName': fileName,
    'label': label,
    'startMs': startMs,
    'endMs': endMs,
    'lyricsOffsetMs': lyricsOffsetMs,
  };

  factory BackingTrack.fromJson(Map<String, dynamic> json) => BackingTrack(
    slot: (json['slot'] as num?)?.toInt() ?? 1,
    fileName: json['fileName'] as String? ?? '',
    label: json['label'] as String? ?? 'MR',
    startMs: (json['startMs'] as num?)?.toInt(),
    endMs: (json['endMs'] as num?)?.toInt(),
    lyricsOffsetMs: (json['lyricsOffsetMs'] as num?)?.toInt() ?? 0,
  );
}
