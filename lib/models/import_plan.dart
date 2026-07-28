// file: lib/models/import_plan.dart
//
// 링크 하나에서 몇 종류의 반주를 만들지, 어느 슬롯에 넣을지 정한다.
// 순수 함수라 파일·네트워크 없이 전 경우를 테스트한다.
import '../constants/app_constants.dart';
import 'track_variant.dart';

/// 가져오기 한 건이 만들 반주 구성.
class ImportPlan {
  /// 내려받은 원본을 슬롯으로 남길지.
  final bool makeOriginal;

  /// AI 분리 결과(반주만)를 슬롯으로 남길지.
  final bool makeInstrumental;

  /// 키조절본을 만들 반음. null이면 만들지 않는다.
  final int? pitchSemitones;

  const ImportPlan({
    this.makeOriginal = false,
    this.makeInstrumental = true,
    this.pitchSemitones,
  });

  /// v2.5.0까지의 동작 — 반주 한 개만 만든다.
  const ImportPlan.single()
    : makeOriginal = false,
      makeInstrumental = true,
      pitchSemitones = null;

  /// 요구된 기본 구성 — 원곡 + MR + MR 기준 키조절.
  const ImportPlan.full({int semitones = -2})
    : makeOriginal = true,
      makeInstrumental = true,
      pitchSemitones = semitones;

  bool get wantsPitch => pitchSemitones != null && pitchSemitones != 0;

  Map<String, dynamic> toJson() => {
    'makeOriginal': makeOriginal,
    'makeInstrumental': makeInstrumental,
    'pitchSemitones': pitchSemitones,
  };

  factory ImportPlan.fromJson(Map<String, dynamic> json) => ImportPlan(
    makeOriginal: json['makeOriginal'] as bool? ?? false,
    makeInstrumental: json['makeInstrumental'] as bool? ?? true,
    pitchSemitones: (json['pitchSemitones'] as num?)?.toInt(),
  );
}

/// 슬롯이 정해진 반주 하나.
class PlannedTrack {
  final TrackVariant variant;
  final int slot;
  final String label;

  /// 파일에 이미 구워 넣을 반음(키조절본만 0이 아니다).
  final int bakedSemitones;

  const PlannedTrack({
    required this.variant,
    required this.slot,
    required this.label,
    this.bakedSemitones = 0,
  });
}

class ImportPlanResult {
  final List<PlannedTrack> tracks;

  /// 슬롯이 모자라 빠진 것들. UI가 이유를 알려 줄 수 있게 남긴다.
  final List<TrackVariant> dropped;

  const ImportPlanResult({required this.tracks, required this.dropped});

  PlannedTrack? forVariant(TrackVariant variant) {
    for (final t in tracks) {
      if (t.variant == variant) return t;
    }
    return null;
  }
}

/// 계획을 실제 슬롯 배치로 바꾼다.
///
/// 우선순위는 원곡 → MR → 키조절 → 노래방. 각 종류는 자기 기본 슬롯이
/// 비어 있으면 거기로, 아니면 남은 가장 낮은 슬롯으로 간다.
ImportPlanResult resolveImportPlan({
  required ImportPlan plan,
  Set<int> occupiedSlots = const {},
  int maxSlots = AppConstants.maxBackingTrackSlots,
  String? pitchLabel,
}) {
  final wanted = <TrackVariant>[
    if (plan.makeOriginal) TrackVariant.original,
    if (plan.makeInstrumental) TrackVariant.mr,
    if (plan.wantsPitch) TrackVariant.pitch,
  ];

  final taken = <int>{...occupiedSlots};
  final tracks = <PlannedTrack>[];
  final dropped = <TrackVariant>[];

  for (final variant in wanted) {
    final slot = _pickSlot(variant, taken, maxSlots);
    if (slot == null) {
      dropped.add(variant);
      continue;
    }
    taken.add(slot);
    tracks.add(
      PlannedTrack(
        variant: variant,
        slot: slot,
        label: variant == TrackVariant.pitch
            ? (pitchLabel ?? variant.label)
            : variant.label,
        bakedSemitones: variant == TrackVariant.pitch
            ? (plan.pitchSemitones ?? 0)
            : 0,
      ),
    );
  }

  tracks.sort((a, b) => a.slot.compareTo(b.slot));
  return ImportPlanResult(tracks: tracks, dropped: dropped);
}

int? _pickSlot(TrackVariant variant, Set<int> taken, int maxSlots) {
  final preferred = variant.preferredSlot;
  if (preferred <= maxSlots && !taken.contains(preferred)) return preferred;
  for (var slot = 1; slot <= maxSlots; slot++) {
    if (!taken.contains(slot)) return slot;
  }
  return null;
}
