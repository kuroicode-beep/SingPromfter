// file: lib/models/recording_take.dart
//
// 녹음된 한 번의 연습(테이크).
//
// songs.json과 분리해 recordings.json에 저장한다. 테이크는 곡 하나에 여러 개
// 쌓이고, 곡을 지워도 기록은 남아야 하기 때문이다. songId는 소프트 FK이고
// 표시에는 songTitle 스냅샷을 쓴다.

class RecordingTake {
  final String id;

  /// 원본 곡 id. 곡이 삭제돼도 테이크는 남으므로 소프트 FK다.
  final String songId;

  /// 녹음 당시 곡 제목. 곡 삭제·개명에도 목록에 이름이 남는다.
  final String songTitle;

  final String fileName;
  final DateTime recordedAt;
  final int durationMs;

  /// 녹음할 때 쓴 반주 슬롯·키.
  final int? backingTrackSlot;
  final int pitchSemitones;

  /// 반주와 합칠 때 쓸 정렬 보정(ms). 녹음 시작 지연을 흡수한다.
  final int alignOffsetMs;

  final String comment;

  /// 0 = 미평가, 1~5.
  final int rating;

  /// 보관 표시. 정리할 때 지우지 않는다.
  final bool isKeep;

  /// 반주와 합친 파일명(있으면). data/recordings 안.
  final String? mixedFileName;

  /// AI 보정본이면 원본 테이크 id. null이면 생녹음이다.
  final String? correctedFrom;

  const RecordingTake({
    required this.id,
    required this.songId,
    required this.songTitle,
    required this.fileName,
    required this.recordedAt,
    required this.durationMs,
    this.backingTrackSlot,
    this.pitchSemitones = 0,
    this.alignOffsetMs = 0,
    this.comment = '',
    this.rating = 0,
    this.isKeep = false,
    this.mixedFileName,
    this.correctedFrom,
  });

  Duration get duration => Duration(milliseconds: durationMs);

  bool get hasComment => comment.trim().isNotEmpty;

  bool get isRated => rating > 0;

  bool get hasMix => (mixedFileName ?? '').isNotEmpty;

  bool get isCorrected => (correctedFrom ?? '').isNotEmpty;

  RecordingTake copyWith({
    String? mixedFileName,
    String? correctedFrom,
    String? songTitle,
    String? comment,
    int? rating,
    bool? isKeep,
    int? durationMs,
    int? alignOffsetMs,
  }) {
    return RecordingTake(
      id: id,
      songId: songId,
      songTitle: songTitle ?? this.songTitle,
      fileName: fileName,
      recordedAt: recordedAt,
      durationMs: durationMs ?? this.durationMs,
      backingTrackSlot: backingTrackSlot,
      pitchSemitones: pitchSemitones,
      alignOffsetMs: alignOffsetMs ?? this.alignOffsetMs,
      comment: comment ?? this.comment,
      rating: rating ?? this.rating,
      isKeep: isKeep ?? this.isKeep,
      mixedFileName: mixedFileName ?? this.mixedFileName,
      correctedFrom: correctedFrom ?? this.correctedFrom,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'songId': songId,
    'songTitle': songTitle,
    'fileName': fileName,
    'recordedAt': recordedAt.toIso8601String(),
    'durationMs': durationMs,
    'backingTrackSlot': backingTrackSlot,
    'pitchSemitones': pitchSemitones,
    'alignOffsetMs': alignOffsetMs,
    'comment': comment,
    'rating': rating,
    'isKeep': isKeep,
    'mixedFileName': mixedFileName,
    'correctedFrom': correctedFrom,
  };

  factory RecordingTake.fromJson(Map<String, dynamic> json) {
    return RecordingTake(
      id: json['id'] as String? ?? '',
      songId: json['songId'] as String? ?? '',
      songTitle: json['songTitle'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      recordedAt:
          DateTime.tryParse(json['recordedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      backingTrackSlot: (json['backingTrackSlot'] as num?)?.toInt(),
      pitchSemitones: (json['pitchSemitones'] as num?)?.toInt() ?? 0,
      alignOffsetMs: (json['alignOffsetMs'] as num?)?.toInt() ?? 0,
      comment: json['comment'] as String? ?? '',
      rating: ((json['rating'] as num?)?.toInt() ?? 0).clamp(0, 5),
      isKeep: json['isKeep'] as bool? ?? false,
      mixedFileName: json['mixedFileName'] as String?,
      correctedFrom: json['correctedFrom'] as String?,
    );
  }
}

/// 녹음 보관함 필터.
enum RecordingFilterMode { all, rated, commented, keep }

extension RecordingFilterModeInfo on RecordingFilterMode {
  String get label => switch (this) {
    RecordingFilterMode.all => '전체',
    RecordingFilterMode.rated => '평가함',
    RecordingFilterMode.commented => '코멘트 있음',
    RecordingFilterMode.keep => '보관',
  };
}
