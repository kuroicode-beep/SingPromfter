// file: lib/services/lyrics_align_service.dart
//
// 싱크 가사가 실제 노래와 얼마나 어긋났는지 재서 오프셋을 제안한다.
//
// 원리: **보컬 = 원곡 − MR**. 두 파일을 위상 반전으로 섞으면 반주가 상쇄되고
// 보컬만 남는다. 사람 목소리 대역만 남겨 에너지 포락선을 뽑으면, 에너지가
// 올라오는 지점이 곧 실제로 노래가 시작되는 순간이다. 그걸 LRC 줄 시각과
// 비교해 중앙값을 취한다.
//
// 왜 필요한가: LRCLIB이 인트로 길이가 다른 판본을 물어 오는 일이 드물지 않다.
// 실측("넌 언제나")에서 LRC가 보컬보다 3.96초 늦었고, 그런 곡은 손으로
// ±0.2초씩 눌러 맞추기가 사실상 불가능하다.
//
// 중앙값을 쓰는 이유: 간주·화음·숨소리 때문에 몇 줄은 엉뚱한 지점을 잡는다.
// 평균은 그런 이상치에 끌려가지만 중앙값은 버틴다.
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../controllers/recording_controller.dart' show parseRmsLevel;
import '../models/timed_lyrics.dart';
import 'process/external_tool_locator.dart';
import 'process/process_runner.dart';

/// 포락선 프레임레이트. 44100 / 1764 = 정확히 25fps (레벨 분석과 같은 규약).
const int alignFps = 25;
const int _samplesPerFrame = 1764;

/// 사람 목소리가 주로 사는 대역. 베이스·심벌을 빼면 시작점이 훨씬 또렷해진다.
const double vocalLowHz = 250;
const double vocalHighHz = 4000;

/// 줄 시각 주변 어디까지 뒤져 실제 시작점을 찾을지.
const Duration alignSearchWindow = Duration(seconds: 4);

/// 맞춘 뒤 가사를 이만큼 더 먼저 띄운다. 읽을 시간을 준다.
const int readingLeadMs = 300;

/// 이 정도 줄에서 시작점을 못 찾으면 판정을 포기한다.
const int minAlignSamples = 5;

/// 원곡에서 MR을 빼 보컬 포락선을 뽑는 ffmpeg 인자. (순수 함수 — 테스트 대상)
///
/// `volume=-1`이 위상 반전이다. `normalize=0`을 줘야 amix가 음량을 절반으로
/// 낮추지 않아 상쇄가 제대로 일어난다.
List<String> buildVocalEnvelopeArgs({
  required String originalPath,
  required String mrPath,
}) {
  final chain =
      '[0:a]aresample=44100,aformat=channel_layouts=mono[a];'
      '[1:a]aresample=44100,aformat=channel_layouts=mono,volume=-1[b];'
      '[a][b]amix=inputs=2:normalize=0,'
      'highpass=f=$vocalLowHz,lowpass=f=$vocalHighHz,'
      'asetnsamples=n=$_samplesPerFrame,'
      'astats=metadata=1:reset=1,'
      'ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-';
  return [
    '-hide_banner',
    '-i', originalPath,
    '-i', mrPath,
    '-filter_complex', chain,
    '-f', 'null',
    '-',
  ];
}

/// [target] 주변에서 보컬 에너지가 처음 문턱을 넘는 시각. 못 찾으면 null.
///
/// 문턱은 그 구간의 하위 10%(배경)와 상위 20%(노래) 사이 중간값이다. 절대
/// dB를 쓰지 않는 이유: 곡마다 녹음 레벨이 달라 고정 문턱은 통하지 않는다.
Duration? detectOnset(
  List<double> envelope,
  Duration target, {
  Duration window = alignSearchWindow,
  int fps = alignFps,
}) {
  if (envelope.isEmpty) return null;
  final lo = ((target - window).inMilliseconds * fps / 1000).floor().clamp(
    0,
    envelope.length,
  );
  final hi = ((target + window).inMilliseconds * fps / 1000).ceil().clamp(
    0,
    envelope.length,
  );
  if (hi - lo < 3) return null;

  final segment = envelope.sublist(lo, hi);
  final sorted = [...segment]..sort();
  final quiet = sorted[(sorted.length * 0.1).floor()];
  final loud = sorted[(sorted.length * 0.8).floor()];
  // 구간 전체가 고르면(계속 노래 중이거나 계속 조용하거나) 시작점이 없다.
  if (loud - quiet < 6) return null;

  final threshold = quiet + (loud - quiet) * 0.5;
  for (var i = 0; i < segment.length; i++) {
    if (segment[i] < threshold) continue;
    // 한 프레임 튄 것과 진짜 시작을 가른다 — 연속 3프레임은 유지돼야 한다.
    final end = (i + 3).clamp(0, segment.length);
    if (segment.sublist(i, end).every((v) => v >= threshold - 3)) {
      return Duration(milliseconds: ((lo + i) * 1000 / fps).round());
    }
  }
  return null;
}

/// 측정 결과.
class LyricsAlignResult {
  /// 제안 오프셋(ms). 음수면 가사를 그만큼 먼저 띄운다는 뜻이다.
  final int offsetMs;

  /// 시작점을 찾은 줄 수.
  final int samples;

  /// 표본들의 편차(ms). 크면 측정이 흔들렸다는 뜻이라 참고용으로 보여 준다.
  final int spreadMs;

  const LyricsAlignResult({
    required this.offsetMs,
    required this.samples,
    required this.spreadMs,
  });
}

/// 포락선과 가사로 오프셋을 추정한다. (순수 함수 — 테스트 대상)
///
/// 표본이 [minAlignSamples]보다 적으면 null. 노래 없는 반주나 시작점이
/// 흐릿한 곡에서 엉뚱한 값을 밀어 넣지 않기 위해서다.
LyricsAlignResult? estimateLyricsOffset({
  required List<double> envelope,
  required TimedLyrics lyrics,
  int fps = alignFps,
  int leadMs = readingLeadMs,
}) {
  if (lyrics.isEmpty || envelope.isEmpty) return null;

  final diffs = <int>[];
  for (final line in lyrics.lines) {
    if (line.text.trim().isEmpty) continue;
    final target = line.time + Duration(milliseconds: lyrics.offsetMs);
    final onset = detectOnset(envelope, target, fps: fps);
    if (onset == null) continue;
    diffs.add((onset - target).inMilliseconds);
  }
  if (diffs.length < minAlignSamples) return null;

  diffs.sort();
  final median = diffs[diffs.length ~/ 2];
  return LyricsAlignResult(
    offsetMs: median - leadMs,
    samples: diffs.length,
    spreadMs: diffs.last - diffs.first,
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

  /// 원곡과 MR을 비교해 보컬 포락선(프레임별 dB)을 뽑는다.
  /// ffmpeg가 없거나 실패하면 빈 목록.
  Future<List<double>> vocalEnvelope({
    required String originalPath,
    required String mrPath,
  }) async {
    final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);
    if (!ffmpeg.found) return const [];
    if (!await File(originalPath).exists()) return const [];
    if (!await File(mrPath).exists()) return const [];

    final values = <double>[];
    final job = _runner.start(
      ffmpeg.path!,
      buildVocalEnvelopeArgs(originalPath: originalPath, mrPath: mrPath),
    );
    final sub = job.lines.listen((line) {
      final rms = parseRmsLevel(line);
      if (rms != null) values.add(rms);
    });
    final exitCode = await job.exitCode;
    await sub.cancel();
    if (exitCode != 0) {
      debugPrint('보컬 포락선 추출 실패 (exit $exitCode)');
      return const [];
    }
    return values;
  }

  /// 오프셋을 측정한다. 잴 수 없으면 null.
  Future<LyricsAlignResult?> measure({
    required String originalPath,
    required String mrPath,
    required TimedLyrics lyrics,
  }) async {
    final envelope = await vocalEnvelope(
      originalPath: originalPath,
      mrPath: mrPath,
    );
    if (envelope.isEmpty) return null;
    return estimateLyricsOffset(envelope: envelope, lyrics: lyrics);
  }
}
