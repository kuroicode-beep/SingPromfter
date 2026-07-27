// file: lib/models/mr_source_mode.dart
//
// 유튜브에서 가져온 오디오를 반주로 쓸 때의 처리 방식.

enum MrSourceMode {
  /// 영상 오디오를 그대로 쓴다. MR·노래방 영상용으로 음질이 가장 좋다.
  asIs,

  /// 원곡을 그대로 두고 가이드 보컬과 함께 부른다. (처리 없음)
  original,

  /// ffmpeg 센터채널 제거로 보컬을 줄인다. 실험적이고 음질이 떨어진다.
  reduceVocal,
}

extension MrSourceModeInfo on MrSourceMode {
  String get label => switch (this) {
    MrSourceMode.asIs => 'MR 영상 그대로',
    MrSourceMode.original => '원곡 그대로',
    MrSourceMode.reduceVocal => '보컬 줄이기 (실험적)',
  };

  String get description => switch (this) {
    MrSourceMode.asIs => '이미 반주만 있는 영상을 링크했을 때. 음질이 가장 좋습니다.',
    MrSourceMode.original => '가이드 보컬이 들어간 채로 연습합니다.',
    MrSourceMode.reduceVocal => '가운데 소리를 빼 보컬을 줄입니다. 반주 음질도 함께 떨어집니다.',
  };

  String get storageValue => name;

  static MrSourceMode fromStorage(String? raw) {
    return MrSourceMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => MrSourceMode.asIs,
    );
  }
}
