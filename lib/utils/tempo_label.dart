// file: lib/utils/tempo_label.dart
//
// 템포 배율을 사람이 읽는 말로 바꾼다. (순수 함수 — 테스트 대상)
//
// key_label과 같은 규칙: 색이 아니라 **말**로 상태를 드러낸다.
// "0.90x"보다 "10% 느리게"가 무대에서 훨씬 빨리 읽힌다.
import 'pitch_math.dart';

/// '원속도' / '10% 느리게' / '5% 빠르게'.
String formatTempoLabel(double scale) {
  final tempo = quantizeTempo(scale);
  if (isDefaultTempo(tempo)) return '원속도';
  final percent = ((tempo - 1) * 100).round().abs();
  return tempo < 1 ? '$percent% 느리게' : '$percent% 빠르게';
}

/// 스크린 리더용 조금 더 긴 설명.
String tempoSemanticLabel(double scale) =>
    '재생 템포 ${formatTempoLabel(scale)}';
