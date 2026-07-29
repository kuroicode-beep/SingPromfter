// file: lib/services/lyrics_align_service.dart
//
// 싱크 가사가 실제 노래와 얼마나 어긋났는지 재서 오프셋을 제안한다.
//
// ── 신호를 어떻게 만드나 ─────────────────────────────────────
// 원곡에서 MR을 **빼지 않는다**. 처음엔 위상 반전으로 빼서 보컬만 남기려
// 했는데, 실측해 보니 두 파일이 위상·게인이 맞지 않아 상쇄가 전혀 일어나지
// 않았다(가사 없는 구간의 차이 신호가 원곡만큼 컸다). demucs로 분리한 MR을
// mp3로 다시 인코딩한 파일이라 샘플 단위로 정렬돼 있지 않다.
//
// 대신 **두 파일의 음량 포락선을 각각 재서 뺀다**: 원곡dB − MRdB.
// 보컬이 있는 구간에서만 원곡이 MR보다 크게 나오므로, 위상이 안 맞아도
// 무관하다. 실측에서 반주 구간은 차이 0.3dB, 노래 구간은 4.4dB로 또렷했다.
//
// ── 어떤 줄만 쓰나 ──────────────────────────────────────────
// **앞이 조용했던 줄만** 쓴다. 노래가 이어지는 구간에서는 "이 줄이 시작되는
// 지점"을 소리만으로 찾을 수 없다 — 이미 계속 소리가 나고 있기 때문이다.
// 이 가드가 없으면 탐색 창의 시작점을 시작점으로 착각해 전부 같은 값이
// 나온다(v2.8.1의 버그가 정확히 이것이었다).
//
// ── 언제 포기하나 ──────────────────────────────────────────
// 표본이 적거나 **표본끼리 크게 흩어지면 값을 내지 않는다.** LRC가 곡과 속도가
// 다른 판본이면 어긋남이 곡이 갈수록 커지는데(실측 +640ms → +3740ms),
// 그런 곡은 오프셋 하나로 맞출 수 없다. 억지로 중앙값을 밀어 넣으면 어디에도
// 맞지 않는다. 못 맞추면 못 맞춘다고 말하는 편이 낫다.
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../controllers/recording_controller.dart' show parseRmsLevel;
import '../models/timed_lyrics.dart';
import 'process/external_tool_locator.dart';
import 'process/process_runner.dart';

/// 포락선 프레임레이트. 44100 / 1764 = 정확히 25fps (레벨 분석과 같은 규약).
const int alignFps = 25;
const int _samplesPerFrame = 1764;

/// 사람 목소리가 주로 사는 대역. 베이스·심벌을 빼면 차이가 훨씬 또렷해진다.
const double vocalLowHz = 250;
const double vocalHighHz = 4000;

/// 줄 시각 앞뒤로 어디까지 뒤져 실제 시작점을 찾을지.
const Duration alignSearchWindow = Duration(seconds: 5);

/// 시작으로 인정하려면 앞이 이만큼 조용해야 한다.
const Duration alignSilenceBefore = Duration(milliseconds: 1500);

/// 켜진 뒤 이만큼은 유지돼야 한다(한 프레임 튄 것과 구분).
const Duration alignHold = Duration(milliseconds: 400);

/// 이만큼은 표본이 있어야 판정한다.
const int minAlignSamples = 4;

/// 표본이 이보다 흩어지면 한 값으로 맞출 수 없는 곡으로 본다.
const int maxAlignSpreadMs = 1500;

/// 파일 하나의 음량 포락선을 재는 ffmpeg 인자. (순수 함수 — 테스트 대상)
List<String> buildEnvelopeArgs(String input) {
  final chain = <String>[
    'aresample=44100',
    'aformat=channel_layouts=mono',
    'highpass=f=$vocalLowHz',
    'lowpass=f=$vocalHighHz',
    'asetnsamples=n=$_samplesPerFrame',
    'astats=metadata=1:reset=1',
    'ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-',
  ].join(',');
  return ['-hide_banner', '-i', input, '-af', chain, '-f', 'null', '-'];
}

/// 보컬 존재도 = 원곡이 MR보다 얼마나 큰가(dB). (순수 함수 — 테스트 대상)
///
/// 샘플 단위 뺄셈이 아니라 **포락선끼리의 뺄셈**이라 두 파일의 위상·게인이
/// 맞지 않아도 성립한다. 잔떨림은 3프레임 이동평균으로 눌러 둔다.
List<double> vocalPresence(List<double> original, List<double> mr) {
  final n = original.length < mr.length ? original.length : mr.length;
  if (n == 0) return const [];
  final raw = [for (var i = 0; i < n; i++) original[i] - mr[i]];
  return [
    for (var i = 0; i < n; i++)
      _mean(raw.sublist(i == 0 ? 0 : i - 1, i + 2 > n ? n : i + 2)),
  ];
}

double _mean(List<double> xs) =>
    xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

/// 노래가 적은 곡에서도 무너지지 않도록 최소 이만큼은 커야 "보컬 있음"으로 본다.
const double minVocalGainDb = 1.5;

/// 보컬이 "있다"고 볼 문턱.
///
/// 절대 dB를 쓰지 않는다 — 곡마다 보컬 비중과 분리 품질이 달라 고정 문턱은
/// 통하지 않는다. 대신 바닥(하위 20%)에서 봉우리(상위 2%) 쪽으로 40% 올린 자리.
///
/// 상위 85%를 봉우리로 쓰면 **노래가 전체의 15%도 안 되는 곡에서 무너진다** —
/// 바닥과 봉우리가 같아져 문턱이 0이 되고 모든 프레임이 "보컬 있음"이 된다.
/// 상위 2%는 노래가 드물어도 실제 봉우리를 짚는다.
double vocalThreshold(List<double> presence) {
  if (presence.isEmpty) return 0;
  final sorted = [...presence]..sort();
  final floorDb = sorted[(sorted.length * 0.20).floor()];
  final peakDb = sorted[((sorted.length - 1) * 0.98).floor()];
  final gain = (peakDb - floorDb) * 0.4;
  return floorDb + (gain < minVocalGainDb ? minVocalGainDb : gain);
}

/// 측정 결과.
class LyricsAlignResult {
  /// 제안 오프셋(ms). 양수면 가사를 그만큼 늦춘다.
  final int offsetMs;

  /// 쓸 수 있었던 표본 수(앞이 조용했던 줄).
  final int samples;

  /// 표본들이 흩어진 폭(ms). 크면 한 값으로 맞출 수 없다는 뜻이다.
  final int spreadMs;

  const LyricsAlignResult({
    required this.offsetMs,
    required this.samples,
    required this.spreadMs,
  });
}

/// 판정할 수 없는 이유.
enum LyricsAlignFailure {
  /// 소리를 재지 못했다.
  noSignal,

  /// 앞이 조용한 줄이 너무 적어 근거가 부족하다.
  notEnoughSamples,

  /// 어긋남이 곡마다 달라 한 값으로 맞출 수 없다(속도가 다른 LRC 판본).
  inconsistent,
}

/// 성공이거나 실패 이유.
class LyricsAlignOutcome {
  final LyricsAlignResult? result;
  final LyricsAlignFailure? failure;

  /// 실패해도 참고용으로 남기는 표본(사용자에게 상황을 설명할 때 쓴다).
  final int samples;
  final int spreadMs;

  const LyricsAlignOutcome.success(LyricsAlignResult this.result)
    : failure = null,
      samples = 0,
      spreadMs = 0;

  const LyricsAlignOutcome.failed(
    LyricsAlignFailure this.failure, {
    this.samples = 0,
    this.spreadMs = 0,
  }) : result = null;

  bool get ok => result != null;
}

/// 포락선과 가사로 오프셋을 추정한다. (순수 함수 — 테스트 대상)
LyricsAlignOutcome estimateLyricsOffset({
  required List<double> presence,
  required TimedLyrics lyrics,
  int fps = alignFps,
}) {
  if (presence.isEmpty || lyrics.isEmpty) {
    return const LyricsAlignOutcome.failed(LyricsAlignFailure.noSignal);
  }

  final threshold = vocalThreshold(presence);
  final active = [for (final v in presence) v >= threshold];
  final silence = alignSilenceBefore.inMilliseconds * fps ~/ 1000;
  final hold = alignHold.inMilliseconds * fps ~/ 1000;
  final search = alignSearchWindow.inMilliseconds * fps ~/ 1000;

  final diffs = <int>[];
  final usedOnsets = <int>{};

  for (final line in lyrics.lines) {
    if (line.text.trim().isEmpty) continue;
    final target =
        (line.time.inMilliseconds + lyrics.offsetMs) * fps ~/ 1000;
    final from = (target - search).clamp(0, active.length);
    final to = (target + search).clamp(0, active.length);

    for (var i = from; i < to - hold; i++) {
      if (!active.sublist(i, i + hold).every((v) => v)) continue;
      // 앞이 조용했어야 진짜 "시작"이다.
      if (i - silence < 0) break;
      if (active.sublist(i - silence, i).any((v) => v)) continue;
      // 같은 시작점에 여러 줄이 붙으면 첫 줄만 센다.
      if (!usedOnsets.add(i)) break;
      diffs.add((i * 1000 ~/ fps) - (line.time.inMilliseconds + lyrics.offsetMs));
      break;
    }
  }

  if (diffs.length < minAlignSamples) {
    return LyricsAlignOutcome.failed(
      LyricsAlignFailure.notEnoughSamples,
      samples: diffs.length,
    );
  }

  diffs.sort();
  final spread = diffs.last - diffs.first;
  if (spread > maxAlignSpreadMs) {
    return LyricsAlignOutcome.failed(
      LyricsAlignFailure.inconsistent,
      samples: diffs.length,
      spreadMs: spread,
    );
  }

  return LyricsAlignOutcome.success(
    LyricsAlignResult(
      offsetMs: diffs[diffs.length ~/ 2],
      samples: diffs.length,
      spreadMs: spread,
    ),
  );
}

class LyricsAlignService {
  final ProcessRunner _runner;
  final ExternalToolLocator _locator;

  LyricsAlignService({
    ProcessRunner runner = const SystemProcessRunner(),
    ExternalToolLocator? locator,
  }) : _runner = runner,
       _locator = locator ?? ExternalToolLocator(runner: runner);

  /// 파일 하나의 음량 포락선(프레임별 dB). 실패하면 빈 목록.
  Future<List<double>> envelope(String path) async {
    final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);
    if (!ffmpeg.found) return const [];
    if (!await File(path).exists()) return const [];

    final values = <double>[];
    final job = _runner.start(ffmpeg.path!, buildEnvelopeArgs(path));
    final sub = job.lines.listen((line) {
      final rms = parseRmsLevel(line);
      if (rms != null) values.add(rms);
    });
    final exitCode = await job.exitCode;
    await sub.cancel();
    if (exitCode != 0) {
      debugPrint('포락선 추출 실패 (exit $exitCode): $path');
      return const [];
    }
    return values;
  }

  /// 오프셋을 측정한다.
  Future<LyricsAlignOutcome> measure({
    required String originalPath,
    required String mrPath,
    required TimedLyrics lyrics,
  }) async {
    final original = await envelope(originalPath);
    final mr = await envelope(mrPath);
    if (original.isEmpty || mr.isEmpty) {
      return const LyricsAlignOutcome.failed(LyricsAlignFailure.noSignal);
    }
    return estimateLyricsOffset(
      presence: vocalPresence(original, mr),
      lyrics: lyrics,
    );
  }
}
