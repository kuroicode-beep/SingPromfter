// file: lib/models/track_variant.dart
//
// 반주 슬롯의 용도. 저장 스키마를 바꾸지 않는다 —
// BackingTrack.label은 자유 문자열 그대로이고, 이 enum은 기본 라벨과
// 기본 슬롯 배치를 제안하는 데만 쓴다. 기존 곡·백업과 100% 호환된다.
enum TrackVariant {
  /// 내려받은 원본 오디오(가이드 보컬 포함).
  original,

  /// AI 보컬 분리 결과(반주만).
  mr,

  /// MR을 기준으로 키를 바꿔 구워 둔 반주.
  pitch,

  /// 별도 링크로 가져온 노래방 버전.
  karaoke,
}

extension TrackVariantInfo on TrackVariant {
  String get label => switch (this) {
    TrackVariant.original => '원곡',
    TrackVariant.mr => 'MR',
    TrackVariant.pitch => '키조절',
    TrackVariant.karaoke => '노래방',
  };

  String get description => switch (this) {
    TrackVariant.original => '가이드 보컬이 들어간 원본 그대로',
    TrackVariant.mr => 'AI로 보컬을 뺀 반주',
    TrackVariant.pitch => 'MR을 기준으로 키를 바꿔 구운 반주',
    TrackVariant.karaoke => '다른 링크로 가져온 노래방 버전',
  };

  /// 비어 있으면 이 슬롯에 넣는다. 차 있으면 가장 낮은 빈 슬롯으로 간다.
  int get preferredSlot => switch (this) {
    TrackVariant.original => 1,
    TrackVariant.mr => 2,
    TrackVariant.pitch => 3,
    TrackVariant.karaoke => 4,
  };
}

/// 가사 싱크를 함께 쓰는 슬롯 묶음.
///
/// 1·2·3번은 **같은 녹음**에서 나온다(원곡 → 보컬 분리 → 키조절 렌더). 같은
/// 음악적 순간이 같은 시각에 있으므로 싱크를 한 번 맞추면 셋 다 맞는다.
/// 4번(노래방)은 다른 링크로 가져온 **다른 녹음**이라 전주 길이부터 다르다 —
/// 같은 값을 쓰면 반드시 어긋난다. 그래서 따로 저장한다.
///
/// (순수 함수 — 테스트 대상)
List<int> lyricsSyncSlotGroup(int slot) {
  const sameRecording = [1, 2, 3];
  return sameRecording.contains(slot) ? sameRecording : [slot];
}
