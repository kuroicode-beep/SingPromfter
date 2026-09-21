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

  /// 녹음을 시작한 순간의 **곡 재생 위치**(ms). 곡을 나눠 녹음한 조각들을
  /// 다시 곡 타임라인 위에 놓을 때 쓴다 — 조각 이어붙이기의 좌표다.
  ///
  /// alignOffsetMs와 다르다: 그쪽은 「반주와 합칠 때 보컬을 얼마나 늦출지」이고
  /// 2채널에서는 반주를 함께 녹음하므로 0이 된다. 이 값은 채널 수와 무관하게
  /// 「곡의 어디였는지」를 남긴다. null이면 기록 이전에 만들어진 테이크다.
  final int? songPositionMs;

  /// 독립 2채널로 받은 테이크인가. 보컬에 반주가 섞이지 않았다는 뜻이라
  /// AI 보컬 분리를 권할 이유가 없다(반주는 잘라낸 조각이 아니라 녹음본).
  final bool dualChannel;

  /// 조각 머리에 일부러 담은 **리드인** 길이(ms). 녹음 고정(상시 캡처 세션)으로
  /// 받은 조각만 값이 있다 — 스페이스를 누르기 전 최대 300ms를 함께 잘라 와서
  /// 첫 음절을 구한다. 곡 앞머리에서는 300보다 짧다(고정값으로 가정하지 말 것).
  ///
  /// 이 구간에는 시작 키 소리가 들어 있어, 이어붙이기가 「내용이 시작하는 자리」를
  /// 찾을 때 건너뛴다. null이면 리드인이 없는 테이크(R 녹음·옛 기록)다.
  final int? leadInMs;

  /// 저장된 소리의 최대 레벨(dBFS). 녹음을 끝낼 때 잰 값을 그대로 남긴다.
  ///
  /// 이어붙이기가 **무음 테이크를 빼는 데** 쓴다 — 꺼진 장치를 녹음한 디지털
  /// 무음 조각이 끼면 그 자리에 있던 멀쩡한 앞 조각의 꼬리가 잘려 나간다.
  /// null이면 재지 못했거나 기록 이전의 테이크다(그때는 파일을 직접 재서 가린다).
  final double? peakDbfs;

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
    this.dualChannel = false,
    this.songPositionMs,
    this.leadInMs,
    this.peakDbfs,
  });

  Duration get duration => Duration(milliseconds: durationMs);

  bool get hasComment => comment.trim().isNotEmpty;

  bool get isRated => rating > 0;

  bool get hasMix => (mixedFileName ?? '').isNotEmpty;

  bool get isCorrected => (correctedFrom ?? '').isNotEmpty;

  bool get hasAccompaniment => (accompanimentFileName ?? '').isNotEmpty;

  bool get hasSeparatedVocal => (separatedFileName ?? '').isNotEmpty;

  /// 곡 타임라인 위 조각으로 쓸 수 있는가(이어붙이기 대상).
  bool get hasSongPosition => songPositionMs != null;

  /// 사용자에게 **말하는** 조각 위치(ms) — 스페이스를 누른 자리.
  ///
  /// 고정 조각의 [songPositionMs]는 「누른 자리 − 리드인」이다(파일 t=0의 좌표).
  /// 그대로 보여 주면 저장 토스트(「1:23부터」)와 목록·취소 토스트(「1:22 조각」)가
  /// 1초 어긋나, 글자로 조각을 가리는 사용자가 다른 조각으로 읽는다. 리드인은 저장
  /// 사정이라 표시에서는 더해 되돌린다. 좌표가 없는 옛 테이크는 null 그대로다.
  int? get displayPositionMs {
    final at = songPositionMs;
    return at == null ? null : at + (leadInMs ?? 0);
  }

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
    bool? dualChannel,
    int? songPositionMs,
    int? leadInMs,
    double? peakDbfs,
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
      dualChannel: dualChannel ?? this.dualChannel,
      songPositionMs: songPositionMs ?? this.songPositionMs,
      leadInMs: leadInMs ?? this.leadInMs,
      peakDbfs: peakDbfs ?? this.peakDbfs,
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
    'dualChannel': dualChannel,
    'songPositionMs': songPositionMs,
    'leadInMs': leadInMs,
    // 🔴 NaN·무한대는 jsonEncode가 예외를 던진다 — 테이크 하나 때문에 목록
    // 저장이 통째로 막히면 안 된다.
    'peakDbfs': _jsonSafeDbfs(peakDbfs),
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
      dualChannel: json['dualChannel'] as bool? ?? false,
      songPositionMs: (json['songPositionMs'] as num?)?.toInt(),
      // 없는 키(옛 파일)는 null로 흡수된다 — additive.
      leadInMs: (json['leadInMs'] as num?)?.toInt(),
      peakDbfs: _jsonSafeDbfs((json['peakDbfs'] as num?)?.toDouble()),
    );
  }
}

/// dBFS 값을 JSON에 넣을 수 있는 모양으로 다듬는다.
/// NaN → null(모름), -무한대 → -100(완전 무음 — 캡처 쪽 표기와 같다), +무한대 → 0.
double? _jsonSafeDbfs(double? value) {
  if (value == null || value.isNaN) return null;
  if (value.isInfinite) return value.isNegative ? -100 : 0;
  return value;
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
