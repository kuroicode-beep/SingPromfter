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
}
