// file: lib/models/recording_take.dart
//
// 녹음된 한 번의 연습(테이크).
//
// songs.json과 분리해 recordings.json에 저장한다. 테이크는 곡 하나에 여러 개
// 쌓이고, 곡을 지워도 기록은 남아야 하기 때문이다. songId는 소프트 FK이고
// 표시에는 songTitle 스냅샷을 쓴다.
//
// v2(스키마): 반주 조각·믹스 설정·분리 보컬·AI 보정(correctedFrom) 필드 추가 —
// 전부 additive라 v1 파일은 기본값으로 자연 흡수된다.

/// 믹스 시 보컬에 거는 리버브 프리셋.
enum ReverbPreset { none, karaoke, hall, studio }

extension ReverbPresetInfo on ReverbPreset {
  String get label => switch (this) {
    ReverbPreset.none => '없음',
    ReverbPreset.karaoke => '노래방',
    ReverbPreset.hall => '홀',
    ReverbPreset.studio => '스튜디오',
  };

  String get storageValue => name;

  static ReverbPreset fromStorage(String? raw) {
    for (final p in ReverbPreset.values) {
      if (p.name == raw) return p;
    }
    return ReverbPreset.none;
  }
}

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

  /// 녹음 당시 실제 재생 파일(키/템포 변형본 포함) 절대경로.
  /// 반주 조각을 다시 잘라야 할 때(캐시 잔존 시) 쓴다.
  final String? sourceAudioPath;

  /// 녹음 당시 템포(배). 메타 표시·재컷용.
  final double tempoScale;

  /// 잘라낸 반주 조각 파일명(`<id>_acc.m4a`). data/recordings 안.
  final String? accompanimentFileName;

  /// 믹스 밸런스(0=반주만, 1=보컬만, 0.5=동등).
  final double mixBalance;

  /// 믹스 시 보컬 리버브 프리셋.
  final ReverbPreset reverbPreset;

  /// 믹스 시 보컬 노이즈 제거(afftdn) 적용.
  final bool noiseReduction;

  /// 분리 서버로 정리한 순수 보컬 파일명(`<id>_sep.wav`). data/recordings 안.
  final String? separatedFileName;

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
    this.sourceAudioPath,
    this.tempoScale = 1.0,
    this.accompanimentFileName,
    this.mixBalance = 0.5,
    this.reverbPreset = ReverbPreset.none,
    this.noiseReduction = false,
    this.separatedFileName,
  });

  Duration get duration => Duration(milliseconds: durationMs);

  bool get hasComment => comment.trim().isNotEmpty;

  bool get isRated => rating > 0;

  bool get hasMix => (mixedFileName ?? '').isNotEmpty;

  bool get isCorrected => (correctedFrom ?? '').isNotEmpty;

  bool get hasAccompaniment => (accompanimentFileName ?? '').isNotEmpty;

  bool get hasSeparatedVocal => (separatedFileName ?? '').isNotEmpty;

  RecordingTake copyWith({
    String? mixedFileName,
    String? correctedFrom,
    String? songTitle,
    String? comment,
    int? rating,
    bool? isKeep,
    int? durationMs,
    int? alignOffsetMs,
    String? sourceAudioPath,
    double? tempoScale,
    String? accompanimentFileName,
    double? mixBalance,
    ReverbPreset? reverbPreset,
    bool? noiseReduction,
    String? separatedFileName,
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
      sourceAudioPath: sourceAudioPath ?? this.sourceAudioPath,
      tempoScale: tempoScale ?? this.tempoScale,
      accompanimentFileName:
          accompanimentFileName ?? this.accompanimentFileName,
      mixBalance: mixBalance ?? this.mixBalance,
      reverbPreset: reverbPreset ?? this.reverbPreset,
      noiseReduction: noiseReduction ?? this.noiseReduction,
      separatedFileName: separatedFileName ?? this.separatedFileName,
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
    'sourceAudioPath': sourceAudioPath,
    'tempoScale': tempoScale,
    'accompanimentFileName': accompanimentFileName,
    'mixBalance': mixBalance,
    'reverbPreset': reverbPreset.storageValue,
    'noiseReduction': noiseReduction,
    'separatedFileName': separatedFileName,
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
      sourceAudioPath: json['sourceAudioPath'] as String?,
      tempoScale: (json['tempoScale'] as num?)?.toDouble() ?? 1.0,
      accompanimentFileName: json['accompanimentFileName'] as String?,
      mixBalance:
          ((json['mixBalance'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0),
      reverbPreset: ReverbPresetInfo.fromStorage(
        json['reverbPreset'] as String?,
      ),
      noiseReduction: json['noiseReduction'] as bool? ?? false,
      separatedFileName: json['separatedFileName'] as String?,
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
