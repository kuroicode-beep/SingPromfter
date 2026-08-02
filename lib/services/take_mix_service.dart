// file: lib/services/take_mix_service.dart
//
// 녹음(보컬)과 반주를 하나의 파일로 합친다.
// 정렬은 녹음 시작 시점의 재생 위치(alignOffsetMs)를 보컬에 지연으로 걸어 맞춘다.
import 'dart:io';

import 'process/external_tool_locator.dart';
import 'process/process_runner.dart';

/// 믹스 ffmpeg 인자를 만든다. (순수 함수 — 테스트 대상)
///
/// [alignMs]만큼 보컬을 늦춰 반주 타임라인 위에 얹는다.
/// duration=first — 반주 길이에 맞추고 남는 보컬은 자른다.
List<String> buildMixArgs({
  required String backingPath,
  required String vocalPath,
  required String outputPath,
  required int alignMs,
}) {
  final delay = alignMs < 0 ? 0 : alignMs;
  return [
    '-y',
    '-i', backingPath,
    '-i', vocalPath,
    '-filter_complex',
    '[1:a]adelay=$delay|$delay[v];'
        '[0:a][v]amix=inputs=2:duration=first:normalize=0[a]',
    '-map', '[a]',
    '-c:a', 'aac',
    '-b:a', '192k',
    outputPath,
  ];
}

/// 듀엣 합성 ffmpeg 인자. (순수 함수 — 테스트 대상)
///
/// 두 보컬(남·여 파트)을 각자의 정렬값으로 늦춰 같은 반주 타임라인에
/// 얹는다. [backingPath]가 null이면 보컬 둘만 겹친다(길이는 긴 쪽).
List<String> buildDuetMixArgs({
  required String? backingPath,
  required String vocalAPath,
  required String vocalBPath,
  required String outputPath,
  required int alignAMs,
  required int alignBMs,
}) {
  final delayA = alignAMs < 0 ? 0 : alignAMs;
  final delayB = alignBMs < 0 ? 0 : alignBMs;
  if (backingPath != null) {
    return [
      '-y',
      '-i', backingPath,
      '-i', vocalAPath,
      '-i', vocalBPath,
      '-filter_complex',
      '[1:a]adelay=$delayA|$delayA[va];'
          '[2:a]adelay=$delayB|$delayB[vb];'
          '[0:a][va][vb]amix=inputs=3:duration=first:normalize=0[a]',
      '-map', '[a]',
      '-c:a', 'aac',
      '-b:a', '192k',
      outputPath,
    ];
  }
  return [
    '-y',
    '-i', vocalAPath,
    '-i', vocalBPath,
    '-filter_complex',
    '[0:a]adelay=$delayA|$delayA[va];'
        '[1:a]adelay=$delayB|$delayB[vb];'
        '[va][vb]amix=inputs=2:duration=longest:normalize=0[a]',
    '-map', '[a]',
    '-c:a', 'aac',
    '-b:a', '192k',
    outputPath,
  ];
}

class TakeMixResult {
  final bool success;
  final String? outputPath;
  final String? message;

  const TakeMixResult._({required this.success, this.outputPath, this.message});

  const TakeMixResult.success(String path)
    : this._(success: true, outputPath: path);

  const TakeMixResult.failure(String message)
    : this._(success: false, message: message);
}

class TakeMixService {
  final ProcessRunner _runner;
  final ExternalToolLocator _locator;

  TakeMixService({
    ProcessRunner runner = const SystemProcessRunner(),
    ExternalToolLocator? locator,
  }) : _runner = runner,
       _locator = locator ?? ExternalToolLocator(runner: runner);

  Future<TakeMixResult> mix({
    required String backingPath,
    required String vocalPath,
    required String outputPath,
    required int alignMs,
  }) async {
    final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);
    if (!ffmpeg.found) {
      return const TakeMixResult.failure('합치려면 ffmpeg가 필요합니다.');
    }
    if (!await File(backingPath).exists()) {
      return const TakeMixResult.failure('반주 파일을 찾을 수 없습니다.');
    }
    if (!await File(vocalPath).exists()) {
      return const TakeMixResult.failure('녹음 파일을 찾을 수 없습니다.');
    }

    final result = await _runner.run(
      ffmpeg.path!,
      buildMixArgs(
        backingPath: backingPath,
        vocalPath: vocalPath,
        outputPath: outputPath,
        alignMs: alignMs,
      ),
    );

    if (!result.ok || !await File(outputPath).exists()) {
      // 실패한 반쪽 파일이 남지 않게 지운다.
      try {
        final partial = File(outputPath);
        if (await partial.exists()) await partial.delete();
      } catch (_) {}
      return const TakeMixResult.failure('합치기에 실패했습니다.');
    }
    return TakeMixResult.success(outputPath);
  }

  /// 남·여 파트 두 테이크를 (있으면) 반주와 함께 한 곡으로 합친다.
  Future<TakeMixResult> duet({
    required String? backingPath,
    required String vocalAPath,
    required String vocalBPath,
    required String outputPath,
    required int alignAMs,
    required int alignBMs,
  }) async {
    final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);
    if (!ffmpeg.found) {
      return const TakeMixResult.failure('합치려면 ffmpeg가 필요합니다.');
    }
    if (backingPath != null && !await File(backingPath).exists()) {
      return const TakeMixResult.failure('반주 파일을 찾을 수 없습니다.');
    }
    for (final vocal in [vocalAPath, vocalBPath]) {
      if (!await File(vocal).exists()) {
        return const TakeMixResult.failure('녹음 파일을 찾을 수 없습니다.');
      }
    }

    final result = await _runner.run(
      ffmpeg.path!,
      buildDuetMixArgs(
        backingPath: backingPath,
        vocalAPath: vocalAPath,
        vocalBPath: vocalBPath,
        outputPath: outputPath,
        alignAMs: alignAMs,
        alignBMs: alignBMs,
      ),
    );

    if (!result.ok || !await File(outputPath).exists()) {
      try {
        final partial = File(outputPath);
        if (await partial.exists()) await partial.delete();
      } catch (_) {}
      return const TakeMixResult.failure('듀엣 합성에 실패했습니다.');
    }
    return TakeMixResult.success(outputPath);
  }
}
