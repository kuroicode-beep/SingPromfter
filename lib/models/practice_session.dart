// file: lib/models/practice_session.dart
//
// 연습 세션 1건. 날짜·곡·연습시간·원곡 대비 키를 기록해 트레이닝 데이터로 쓴다.

/// 한 번의 연습(곡 재생) 기록.
///
/// 곡이 삭제되거나 제목이 바뀌어도 기록은 남아야 하므로
/// [songId]는 소프트 FK로만 두고 표시는 [songTitle] 스냅샷을 쓴다.
class PracticeSession {
  final String id;
  final String songId;
  final String songTitle;
  final DateTime startedAt;

  /// 실제 재생 시간(일시정지 구간 제외).
  final int durationMs;

  /// 원곡 대비 반음. 0 = 원키. (피치 조절 도입 전까지 0)
  final int pitchSemitones;

  final int? backingTrackSlot;

  /// 녹음을 동반한 연습인지. (녹음 기능 도입 전까지 false)
  final bool recorded;

  const PracticeSession({
    required this.id,
    required this.songId,
    required this.songTitle,
    required this.startedAt,
    required this.durationMs,
    this.pitchSemitones = 0,
    this.backingTrackSlot,
    this.recorded = false,
  });

  Duration get duration => Duration(milliseconds: durationMs);

  PracticeSession copyWith({
    String? id,
    String? songId,
    String? songTitle,
    DateTime? startedAt,
    int? durationMs,
    int? pitchSemitones,
    int? backingTrackSlot,
    bool clearBackingTrackSlot = false,
    bool? recorded,
  }) {
    return PracticeSession(
      id: id ?? this.id,
      songId: songId ?? this.songId,
      songTitle: songTitle ?? this.songTitle,
      startedAt: startedAt ?? this.startedAt,
      durationMs: durationMs ?? this.durationMs,
      pitchSemitones: pitchSemitones ?? this.pitchSemitones,
      backingTrackSlot: clearBackingTrackSlot
          ? null
          : (backingTrackSlot ?? this.backingTrackSlot),
      recorded: recorded ?? this.recorded,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'songId': songId,
    'songTitle': songTitle,
    'startedAt': startedAt.toIso8601String(),
    'durationMs': durationMs,
    'pitchSemitones': pitchSemitones,
    'backingTrackSlot': backingTrackSlot,
    'recorded': recorded,
  };

  factory PracticeSession.fromJson(Map<String, dynamic> json) {
    return PracticeSession(
      id: json['id'] as String? ?? '',
      songId: json['songId'] as String? ?? '',
      songTitle: json['songTitle'] as String? ?? '',
      startedAt:
          DateTime.tryParse(json['startedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      pitchSemitones: (json['pitchSemitones'] as num?)?.toInt() ?? 0,
      backingTrackSlot: (json['backingTrackSlot'] as num?)?.toInt(),
      recorded: json['recorded'] as bool? ?? false,
    );
  }
}

/// 곡별 연습 누적 집계. 설정의 "연습 기록" 목록과 이후 통계 화면이 공유한다.
class PracticeSummary {
  final String songId;
  final String songTitle;
  final int sessionCount;
  final int totalDurationMs;
  final DateTime lastPracticedAt;

  /// 가장 자주 사용한 키(원곡 대비 반음).
  final int dominantPitchSemitones;

  const PracticeSummary({
    required this.songId,
    required this.songTitle,
    required this.sessionCount,
    required this.totalDurationMs,
    required this.lastPracticedAt,
    required this.dominantPitchSemitones,
  });

  Duration get totalDuration => Duration(milliseconds: totalDurationMs);

  /// 세션 목록을 곡별로 집계한다. 최근 연습일 내림차순으로 정렬해 반환한다.
  static List<PracticeSummary> summarize(List<PracticeSession> sessions) {
    final grouped = <String, List<PracticeSession>>{};
    for (final session in sessions) {
      grouped.putIfAbsent(session.songId, () => []).add(session);
    }

    final summaries = grouped.entries.map((entry) {
      final items = entry.value;
      var totalMs = 0;
      var lastAt = items.first.startedAt;
      final pitchCounts = <int, int>{};

      for (final item in items) {
        totalMs += item.durationMs;
        if (item.startedAt.isAfter(lastAt)) lastAt = item.startedAt;
        pitchCounts[item.pitchSemitones] =
            (pitchCounts[item.pitchSemitones] ?? 0) + 1;
      }

      var dominantPitch = 0;
      var dominantCount = -1;
      for (final pitch in pitchCounts.entries) {
        // 동률이면 원키에 가까운 쪽을 택해 표기가 흔들리지 않게 한다.
        final isBetter =
            pitch.value > dominantCount ||
            (pitch.value == dominantCount &&
                pitch.key.abs() < dominantPitch.abs());
        if (isBetter) {
          dominantPitch = pitch.key;
          dominantCount = pitch.value;
        }
      }

      return PracticeSummary(
        songId: entry.key,
        songTitle: items.last.songTitle,
        sessionCount: items.length,
        totalDurationMs: totalMs,
        lastPracticedAt: lastAt,
        dominantPitchSemitones: dominantPitch,
      );
    }).toList();

    summaries.sort((a, b) => b.lastPracticedAt.compareTo(a.lastPracticedAt));
    return List.unmodifiable(summaries);
  }
}
