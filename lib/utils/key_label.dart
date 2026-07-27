// file: lib/utils/key_label.dart
//
// 원곡 대비 키(반음) 표기. 피치 조절 UI와 연습 통계가 이 함수 하나만 공유한다.

/// 원곡 대비 반음 수를 한국어 라벨로 바꾼다.
///
/// 1키 = 반음 1개. 예: `0` → '원키', `1` → '1키 높임', `-2` → '2키 낮춤'.
String formatKeyLabel(int semitones) {
  if (semitones == 0) return '원키';
  if (semitones > 0) return '$semitones키 높임';
  return '${-semitones}키 낮춤';
}

/// 접근성 라벨용 축약 표기가 필요한 곳에서 쓰는 짧은 형태.
/// 예: `0` → '원키', `2` → '+2', `-2` → '-2'
String formatKeyShort(int semitones) {
  if (semitones == 0) return '원키';
  return semitones > 0 ? '+$semitones' : '$semitones';
}
