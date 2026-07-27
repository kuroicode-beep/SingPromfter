// file: lib/utils/pitch_math.dart
//
// 키(반음) 변환 계산. ffmpeg rubberband 필터의 pitch 인자는 반음이 아니라
// **주파수 비율**이라 변환이 필요하다. 순수 함수라 ffmpeg 없이 테스트한다.
import 'dart:math' as math;

/// 조절 가능한 키 범위(반음). 이 이상은 음질이 급격히 나빠진다.
const int minPitchSemitones = -6;
const int maxPitchSemitones = 6;

/// 반음 수를 주파수 비율로 바꾼다. 예: +2 → 1.122462
double semitonesToRatio(int semitones) =>
    math.pow(2, semitones / 12).toDouble();

/// 범위를 벗어난 값을 잘라낸다.
int clampSemitones(int semitones) =>
    semitones.clamp(minPitchSemitones, maxPitchSemitones);

/// 캐시 파일명을 만든다. 원본 파일명과 반음이 같으면 항상 같은 이름이 나온다.
///
/// 예: `봄날_mr1.mp3`, +2 → `봄날_mr1__p+2.m4a`
String pitchVariantFileName(String sourceFileName, int semitones) {
  final dot = sourceFileName.lastIndexOf('.');
  final stem = dot > 0 ? sourceFileName.substring(0, dot) : sourceFileName;
  final sign = semitones >= 0 ? '+' : '-';
  return '${stem}__p$sign${semitones.abs()}.m4a';
}

/// rubberband 필터 인자. 소수 자릿수를 고정해 캐시 키가 흔들리지 않게 한다.
String rubberbandFilter(int semitones) {
  final ratio = semitonesToRatio(semitones).toStringAsFixed(6);
  return 'rubberband=pitch=$ratio:pitchq=quality';
}

/// rubberband가 없는 환경에서 쓰는 대체 필터. 음질이 떨어진다.
///
/// 샘플레이트를 바꿔 음을 올린 뒤 원래 속도로 되돌리는 방식이다.
String fallbackPitchFilter(int semitones, {int sampleRate = 44100}) {
  final ratio = semitonesToRatio(semitones);
  final shifted = (sampleRate * ratio).round();
  final tempo = (1 / ratio).toStringAsFixed(6);
  return 'asetrate=$shifted,aresample=$sampleRate,atempo=$tempo';
}

/// 피치 변형 ffmpeg 인자를 만든다. (순수 함수 — 프로세스를 띄우지 않는다)
List<String> buildPitchArgs({
  required String input,
  required String output,
  required int semitones,
  required bool hasRubberband,
}) {
  final filter = hasRubberband
      ? rubberbandFilter(semitones)
      : fallbackPitchFilter(semitones);
  return [
    '-y',
    '-i', input,
    '-filter:a', filter,
    '-vn',
    '-c:a', 'aac',
    '-b:a', '192k',
    '-progress', 'pipe:1',
    '-nostats',
    output,
  ];
}
