// file: lib/utils/recording_latency.dart
//
// 녹음 지연 보정(ms) — 값의 범위·표시, 그리고 테이크 좌표에 **부호를 거는 단 한 곳**.
//
// 왜 필요한가: 반주가 스피커·헤드폰으로 나오는 데 걸리는 시간(출력 지연)과 목소리가
// 마이크에서 파일까지 오는 시간(입력 지연)만큼, 녹음된 목소리는 곡보다 **늦게** 담긴다.
// 장치마다 달라 앱이 잴 수 없으니 사용자가 귀로 맞춘 값 C(ms)를 설정에 둔다.
//
// 부호: 테이크의 계약은 「파일 시각 t ↔ 곡 시각 songPositionMs + t」다. 목소리가 C만큼
// 늦게 담겼으면 파일 t에 든 소리는 곡 시각으로 C만큼 **이른** 자리의 것이다 → 좌표에서
// C를 **뺀다.** C = 출력 지연(outLat) + 입력 지연(inLat)일 때,
//  · 고정·복구: 마크(파일 F)를 찍고 L 뒤에 P0에서 재생이 흐르고, 가수는 그 소리를
//    outLat 뒤에 듣고 따라 부르며, 그 목소리는 inLat 뒤에 파일에 닿는다. 곡 시각 s의
//    목소리는 파일 F + L + C + (s − P0)에 있다 → 조각 t=0의 좌표는 P0 − L − C − leadIn.
//  · R 녹음: anchor는 「파일 t=0이 앱에 닿은 순간의 표시 위치」다. 그 소리가 마이크에
//    닿은 건 inLat 전이고, 그때 가수가 듣던 곡 시각은 표시 위치 − outLat → anchor − C.
// 두 길의 부호·크기가 같다. 음수 C는 반대로 좌표를 늦춘다 — 합친 곡에서 목소리가
// 앞서 들릴 때 쓴다.
//
// 🔴 뺀 결과가 0 밑으로 내려가면 **0으로 눕히지 않는다.** 눕히면 그 테이크만 모자란
// 만큼 어긋난 채 남는다(곡 처음에서 받는 가장 흔한 조각이 여기 걸린다). 대신 테이크
// **머리를 그만큼 잘라** t=0을 곡 0에 맞춘다 — v5.16.0이 P0 < L에서 하던 것과 같은 방식.
// 고정·복구는 [computeTakeSlice]가 자를 자리를 뒤로 옮기고, R 녹음은 다 쓰인 파일이라
// [planRecordedTakeTiming]이 잘라 낼 길이를 돌려준다.

/// 보정값의 허용 범위(ms). USB 마이크+블루투스 헤드폰도 300ms를 넘기 어렵다.
const int kRecordingLatencyMinMs = -300;
const int kRecordingLatencyMaxMs = 300;

/// 설정 화면 ± 버튼 한 번의 크기(ms). 귀로 가릴 수 있는 최소 단위쯤이다.
const int kRecordingLatencyStepMs = 5;

/// 머리를 자르고도 이만큼은 남아야 자른다(ms) — 0.5초 미만은 테이크로 치지 않는다.
const int kMinimumTrimmedTakeMs = 500;

/// 저장·입력값을 허용 범위로 맞춘다. 숫자가 아니면(옛 설정·깨진 값) 0이다.
int clampRecordingLatencyMs(Object? raw) {
  if (raw is! num || raw.isNaN) return 0;
  if (raw <= kRecordingLatencyMinMs) return kRecordingLatencyMinMs;
  if (raw >= kRecordingLatencyMaxMs) return kRecordingLatencyMaxMs;
  return raw.round();
}

/// ± 버튼 한 번을 누른 뒤의 값. [direction]의 부호만 본다(0이면 그대로).
///
/// 5ms 격자에 맞춘다 — 설정 파일을 손으로 고쳐 33이 들어 있어도 +는 35, −는 30이다.
/// 범위 끝에서는 멈춘다.
int stepRecordingLatencyMs(int current, int direction) {
  final from = clampRecordingLatencyMs(current);
  if (direction == 0) return from;
  const step = kRecordingLatencyStepMs;
  final onGrid = from % step == 0;
  final int next;
  if (direction > 0) {
    next = onGrid ? from + step : (from / step).ceil() * step;
  } else {
    next = onGrid ? from - step : (from / step).floor() * step;
  }
  return clampRecordingLatencyMs(next);
}

/// 설정 화면에 보이는 값 글자 — 「+35 ms」「−20 ms」「0 ms (보정 없음)」.
///
/// 상태를 색이 아니라 글자로 말한다. 범위 끝에서는 버튼이 더 먹지 않는 이유도 적는다.
String formatRecordingLatencyMs(int ms) {
  final value = clampRecordingLatencyMs(ms);
  if (value == 0) return '0 ms (보정 없음)';
  final text = value > 0 ? '+$value ms' : '−${-value} ms';
  if (value == kRecordingLatencyMaxMs) return '$text (최대)';
  if (value == kRecordingLatencyMinMs) return '$text (최소)';
  return text;
}

/// 화면 읽기 프로그램에 들려줄 값 — 기호(+·−)를 말로 푼다.
///
/// 「녹음 지연 보정」이라는 말은 넣지 않는다. 설정 패널의 글자들은 한 노드로 합쳐
/// 읽히고 이 값은 제목 바로 뒤에 온다 — 넣으면 제목을 두 번 읽는다.
String recordingLatencySemanticsLabel(int ms) {
  final value = clampRecordingLatencyMs(ms);
  if (value == 0) return '0 밀리초, 보정 없음';
  final direction = value > 0 ? '플러스' : '마이너스';
  final edge = value == kRecordingLatencyMaxMs
      ? ', 최대'
      : (value == kRecordingLatencyMinMs ? ', 최소' : '');
  return '$direction ${value.abs()} 밀리초$edge';
}

/// 🔴 **부호가 사는 단 한 곳.** 보정 전 곡 좌표를 보정값만큼 앞당긴다.
///
/// 결과는 음수일 수 있다 — 호출부는 0으로 눕히지 말고 그만큼 테이크 머리를 잘라야 한다.
int compensateSongPositionMs(int rawMs, int latencyMs) =>
    rawMs - clampRecordingLatencyMs(latencyMs);

/// 다 쓰인 녹음 파일(R 녹음) 하나의 좌표 계획.
class RecordedTakeTiming {
  const RecordedTakeTiming({
    required this.songPositionMs,
    required this.headTrimMs,
    required this.durationMs,
    required this.latencyAppliedMs,
  });

  /// (머리를 자른 뒤의) 파일 t=0의 곡 좌표(ms). 언제나 0 이상이다.
  final int songPositionMs;

  /// 파일 머리에서 잘라 내야 하는 길이(ms). 0이면 자르지 않는다.
  final int headTrimMs;

  /// 머리를 자른 뒤의 길이(ms).
  final int durationMs;

  /// 좌표에 실제로 구워진 보정값(ms). 테이크에 그대로 남긴다.
  final int latencyAppliedMs;

  @override
  String toString() =>
      'RecordedTakeTiming(song $songPositionMs, trim $headTrimMs, '
      'duration $durationMs, applied $latencyAppliedMs)';
}

/// R 녹음 한 번의 좌표를 정한다. (순수 함수 — 테스트 대상)
///
/// [anchorMs]는 프레임 줄로 역산한 「파일 t=0의 곡 좌표」(보정 전)다. null이면 녹음
/// 내내 재생이 흐르지 않아 곡과의 시간 관계가 없다 — [fallbackPositionMs](녹음을 건
/// 순간의 위치)를 그대로 쓰고 보정하지 않는다.
///
/// 🔴 **보정 때문에** 0 밑으로 내려간 만큼만(anchor ≥ 0, 최대 300ms) 머리를 자른다 —
/// [RecordedTakeTiming.headTrimMs]. 자르고 남는 길이가 [kMinimumTrimmedTakeMs]에 못
/// 미치거나 [canTrimHead]가 거짓이면(파일 가공에 실패한 뒤 다시 부르는 길) 0에 눕히고,
/// **실제로 옮겨진 만큼만** 적용값으로 적는다.
///
/// anchor 자체가 음수인 녹음(재생보다 R을 먼저 누름)은 v5.16.0 그대로 0에 눕히고
/// 보정도 걸지 않는다. 그 머리는 몇 초짜리일 수 있고 사용자가 일부러 먼저 부른 소리일
/// 수 있어, 여기서 지우지 않는다(좌표가 어긋나는 것은 보정 이전부터의 문제다).
RecordedTakeTiming planRecordedTakeTiming({
  required int? anchorMs,
  required int fallbackPositionMs,
  required int durationMs,
  required int latencyMs,
  bool canTrimHead = true,
}) {
  final duration = durationMs < 0 ? 0 : durationMs;
  RecordedTakeTiming keep(int songPositionMs, int appliedMs) =>
      RecordedTakeTiming(
        songPositionMs: songPositionMs,
        headTrimMs: 0,
        durationMs: duration,
        latencyAppliedMs: appliedMs,
      );

  if (anchorMs == null) {
    return keep(fallbackPositionMs < 0 ? 0 : fallbackPositionMs, 0);
  }
  final latency = clampRecordingLatencyMs(latencyMs);
  final target = compensateSongPositionMs(anchorMs, latency);
  if (target >= 0) return keep(target, latency);
  // 보정 이전부터 0 밑이던 좌표 — 옛 동작 그대로(위 설명).
  if (anchorMs < 0) return keep(0, 0);

  final trim = -target;
  if (canTrimHead && duration - trim >= kMinimumTrimmedTakeMs) {
    return RecordedTakeTiming(
      songPositionMs: 0,
      headTrimMs: trim,
      durationMs: duration - trim,
      latencyAppliedMs: latency,
    );
  }
  // 못 자른다 — 0에 눕힌다. anchor만큼만 앞당겨졌다.
  return keep(0, anchorMs);
}
