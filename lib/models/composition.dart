// file: lib/models/composition.dart
//
// AI가 생성한 곡 하나의 메타. 오디오는 data/compose/<id>.mp3|wav에 두고
// 목록은 data/compose/compositions.json(schemaVersion 1)에 저장한다.

/// 생성 모드 — BGM(반주만, MusicGen 8766) | 보컬곡(ACE-Step 1.5 터보 8774).
enum ComposeMode { bgm, vocal }

extension ComposeModeInfo on ComposeMode {
  String get label => switch (this) {
    ComposeMode.bgm => 'BGM',
    ComposeMode.vocal => '보컬곡',
  };

  String get storageValue => name;

  static ComposeMode fromStorage(String? raw) =>
      raw == 'vocal' ? ComposeMode.vocal : ComposeMode.bgm;
}

class Composition {
  final String id;
  final String title;
  final ComposeMode mode;

  /// 사용자가 입력한 한국어 스타일 설명(원문).
  final String stylePromptKo;

  /// Ollama가 다듬은(또는 사용자가 고친) 영어 프롬프트. 비어 있으면 원문 사용.
  final String stylePromptEn;

  final String lyrics;

  /// 보컬 타입 — female | male | duet | choir | '' (지정 안 함).
  final String vocalType;

  /// 추가 장르 태그(영문).
  final String genre;
  final String chords; // 코드 진행 (락 기록)
  final String singer; // 전속 가수 참조 — 'auto' | 'off' (발행 표기용 기록)

  final int? bpm;
  final int durationSec;
  final int seed;

  /// data/compose 안의 오디오 파일명.
  final String fileName;

  final DateTime createdAt;
  final double genTimeSec;

  /// 곡으로 등록됐으면 그 곡 id.
  final String? registeredSongId;

  /// seed 변주 묶음 id. 단독 생성이면 null.
  final String? batchId;

  const Composition({
    required this.id,
    required this.title,
    required this.mode,
    this.stylePromptKo = '',
    this.stylePromptEn = '',
    this.lyrics = '',
    this.vocalType = '',
    this.genre = '',
    this.chords = '',
    this.singer = 'auto',
    this.bpm,
    required this.durationSec,
    this.seed = -1,
    required this.fileName,
    required this.createdAt,
    this.genTimeSec = 0,
    this.registeredSongId,
    this.batchId,
  });

  bool get isRegistered => (registeredSongId ?? '').isNotEmpty;

  /// 생성에 실제로 보낼 프롬프트 — 다듬은 영문이 있으면 그것, 없으면 원문.
  String get effectivePrompt =>
      stylePromptEn.trim().isNotEmpty ? stylePromptEn.trim() : stylePromptKo.trim();

  Composition copyWith({
    String? title,
    String? stylePromptEn,
    String? fileName,
    double? genTimeSec,
    int? seed,
    String? registeredSongId,
  }) {
    return Composition(
      id: id,
      title: title ?? this.title,
      mode: mode,
      stylePromptKo: stylePromptKo,
      stylePromptEn: stylePromptEn ?? this.stylePromptEn,
      lyrics: lyrics,
      vocalType: vocalType,
      genre: genre,
      chords: chords,
      singer: singer,
      bpm: bpm,
      durationSec: durationSec,
      seed: seed ?? this.seed,
      fileName: fileName ?? this.fileName,
      createdAt: createdAt,
      genTimeSec: genTimeSec ?? this.genTimeSec,
      registeredSongId: registeredSongId ?? this.registeredSongId,
      batchId: batchId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'mode': mode.storageValue,
    'stylePromptKo': stylePromptKo,
    'stylePromptEn': stylePromptEn,
    'lyrics': lyrics,
    'vocalType': vocalType,
    'genre': genre,
    'chords': chords,
    'singer': singer,
    'bpm': bpm,
    'durationSec': durationSec,
    'seed': seed,
    'fileName': fileName,
    'createdAt': createdAt.toIso8601String(),
    'genTimeSec': genTimeSec,
    'registeredSongId': registeredSongId,
    'batchId': batchId,
  };

  factory Composition.fromJson(Map<String, dynamic> json) {
    return Composition(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      mode: ComposeModeInfo.fromStorage(json['mode'] as String?),
      stylePromptKo: json['stylePromptKo'] as String? ?? '',
      stylePromptEn: json['stylePromptEn'] as String? ?? '',
      lyrics: json['lyrics'] as String? ?? '',
      vocalType: json['vocalType'] as String? ?? '',
      genre: json['genre'] as String? ?? '',
      chords: json['chords'] as String? ?? '',
      singer: json['singer'] as String? ?? 'auto',
      bpm: (json['bpm'] as num?)?.toInt(),
      durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
      seed: (json['seed'] as num?)?.toInt() ?? -1,
      fileName: json['fileName'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      genTimeSec: (json['genTimeSec'] as num?)?.toDouble() ?? 0,
      registeredSongId: json['registeredSongId'] as String?,
      batchId: json['batchId'] as String?,
    );
  }
}
