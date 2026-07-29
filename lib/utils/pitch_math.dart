// file: lib/utils/pitch_math.dart
//
// 키(반음)·템포 변환 계산. ffmpeg rubberband 필터의 pitch 인자는 반음이 아니라
// **주파수 비율**이라 변환이 필요하다. 순수 함수라 ffmpeg 없이 테스트한다.
//
// rubberband는 tempo와 pitch를 한 인스턴스에서 독립 처리한다. 두 번 걸면
// 아티팩트와 렌더 시간이 둘 다 두 배가 되므로 언제나 한 번에 건다.
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

/// 조절 가능한 템포 범위(배). 0.5배는 절반 속도, 1.5배는 1.5배 속도다.
const double minTempoScale = 0.5;
const double maxTempoScale = 1.5;

/// 템포 조절 한 칸.
const double tempoStep = 0.05;

/// 캐시 키가 흔들리지 않도록 0.05 단위로 스냅한 뒤 범위로 자른다.
double quantizeTempo(double scale) {
  // 0.05 배수를 곱셈으로 만들면 0.8500000000000001 같은 값이 나온다.
  // 저장 파일과 제어 API에 그대로 실리므로 소수 둘째 자리에서 끊는다.
  final steps = (scale / tempoStep).round();
  final snapped = (steps * tempoStep * 100).round() / 100;
  return snapped.clamp(minTempoScale, maxTempoScale);
}

bool isDefaultTempo(double scale) => (scale - 1).abs() < tempoStep / 2;

/// 변형본 캐시 파일명. 키도 템포도 기본이면 null(원본 그대로 재생).
///
/// **호환 규약**: 템포가 1.0이면 v2.7.0과 완전히 같은 이름(`<stem>__p+2.m4a`)을
/// 낸다 — 이미 렌더해 둔 키 변형본을 버리지 않기 위해서다. 템포가 1.0이 아니면
/// `<stem>__p+2_t090.m4a`. 어느 경우든 `<stem>__p`로 시작하므로
/// TrackAssetService의 prefix 무효화 규약이 그대로 맞는다.
String? trackVariantFileName(
  String sourceFileName, {
  int semitones = 0,
  double tempoScale = 1,
}) {
  final pitch = clampSemitones(semitones);
  final tempo = quantizeTempo(tempoScale);
  if (pitch == 0 && isDefaultTempo(tempo)) return null;

  final dot = sourceFileName.lastIndexOf('.');
  final stem = dot > 0 ? sourceFileName.substring(0, dot) : sourceFileName;
  final sign = pitch >= 0 ? '+' : '-';
  final base = '${stem}__p$sign${pitch.abs()}';
  if (isDefaultTempo(tempo)) return '$base.m4a';
  // 0.90 → t090. 소수점을 빼 파일명에 점이 하나만 남게 한다.
  final t = (tempo * 100).round().toString().padLeft(3, '0');
  return '${base}_t$t.m4a';
}

/// 예전 이름(키 전용). v2.7.0까지의 캐시와 같은 이름을 낸다.
String pitchVariantFileName(String sourceFileName, int semitones) =>
    trackVariantFileName(sourceFileName, semitones: semitones) ??
    trackVariantFileName(sourceFileName, semitones: 1)!;

/// rubberband 필터 인자. 소수 자릿수를 고정해 캐시 키가 흔들리지 않게 한다.
/// tempo와 pitch는 서로 독립이라 한 인스턴스로 둘 다 처리한다.
String rubberbandFilter(int semitones, {double tempoScale = 1}) {
  final ratio = semitonesToRatio(semitones).toStringAsFixed(6);
  final tempo = quantizeTempo(tempoScale).toStringAsFixed(6);
  return 'rubberband=tempo=$tempo:pitch=$ratio:pitchq=quality';
}

/// atempo는 한 번에 0.5~2.0만 받는다. 범위를 벗어나면 제곱근으로 두 단 겹친다.
String atempoChain(double tempo) {
  if (tempo >= 0.5 && tempo <= 2.0) {
    return 'atempo=${tempo.toStringAsFixed(6)}';
  }
  final half = math.sqrt(tempo).toStringAsFixed(6);
  return 'atempo=$half,atempo=$half';
}

/// rubberband가 없는 환경에서 쓰는 대체 필터. 음질이 떨어진다.
///
/// 샘플레이트를 바꿔 음을 올린 뒤 원래 속도로 되돌리는 방식이라,
/// 템포 조절도 같은 atempo 단계에 합쳐 한 번만 건다.
String fallbackVariantFilter(
  int semitones, {
  double tempoScale = 1,
  int sampleRate = 44100,
}) {
  final ratio = semitonesToRatio(semitones);
  final shifted = (sampleRate * ratio).round();
  // 피치 보정용 1/ratio 와 요청 템포를 곱해 한 번에 처리한다.
  final tempo = quantizeTempo(tempoScale) / ratio;
  return 'asetrate=$shifted,aresample=$sampleRate,${atempoChain(tempo)}';
}

/// 변형본 ffmpeg 인자를 만든다. (순수 함수 — 프로세스를 띄우지 않는다)
List<String> buildVariantArgs({
  required String input,
  required String output,
  int semitones = 0,
  double tempoScale = 1,
  required bool hasRubberband,
}) {
  final filter = hasRubberband
      ? rubberbandFilter(semitones, tempoScale: tempoScale)
      : fallbackVariantFilter(semitones, tempoScale: tempoScale);
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
