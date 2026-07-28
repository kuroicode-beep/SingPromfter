// file: lib/services/pitch_variant_service.dart
//
// 키를 바꾼 반주 파일을 미리 만들어 캐시한다.
//
// 실시간 피치 변조 대신 오프라인 렌더링을 쓰는 이유:
// audioplayers에 피치 API가 없고, 무대에서는 키를 미리 정해두는 편이 안전하며,
// 오디오 엔진을 통째로 바꾸는 것보다 위험이 훨씬 작다.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/pitch_math.dart';
import 'process/external_tool_locator.dart';
import 'process/process_runner.dart';
import 'process/tool_progress_parsers.dart';

class PitchRenderResult {
  final bool success;
  final String? path;
  final String? message;

  const PitchRenderResult._({required this.success, this.path, this.message});

  const PitchRenderResult.success(String path)
    : this._(success: true, path: path);

  const PitchRenderResult.failure(String message)
    : this._(success: false, message: message);
}

class PitchVariantService {
  final ProcessRunner _runner;
  final ExternalToolLocator _locator;

  bool? _hasRubberband;

  PitchVariantService({
    ProcessRunner runner = const SystemProcessRunner(),
    ExternalToolLocator? locator,
  }) : _runner = runner,
       _locator = locator ?? ExternalToolLocator(runner: runner);

  Future<Directory> get cacheDir async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/data/cache/pitch');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// ffmpeg에 rubberband 필터가 있는지 한 번만 확인하고 캐시한다.
  Future<bool> hasRubberband() async {
    if (_hasRubberband != null) return _hasRubberband!;
    final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);
    if (!ffmpeg.found) {
      _hasRubberband = false;
      return false;
    }
    final result = await _runner.run(ffmpeg.path!, ['-hide_banner', '-filters']);
    _hasRubberband = result.ok && result.stdout.contains('rubberband');
    return _hasRubberband!;
  }

  /// 이미 만들어 둔 변형본이 있으면 경로를 준다.
  Future<String?> cachedPath({
    required String sourceFileName,
    required int semitones,
  }) async {
    if (semitones == 0) return null;
    final name = pitchVariantFileName(sourceFileName, semitones);
    final file = File('${(await cacheDir).path}/$name');
    return await file.exists() ? file.path : null;
  }

  /// 변형본을 만든다(있으면 그대로 재사용).
  Future<PitchRenderResult> render({
    required String sourcePath,
    required String sourceFileName,
    required int semitones,
    Duration? total,
    void Function(JobProgress progress)? onProgress,
  }) async {
    final clamped = clampSemitones(semitones);
    if (clamped == 0) return PitchRenderResult.success(sourcePath);

    final existing = await cachedPath(
      sourceFileName: sourceFileName,
      semitones: clamped,
    );
    if (existing != null) return PitchRenderResult.success(existing);

    final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);
    if (!ffmpeg.found) {
      return const PitchRenderResult.failure(
        '키를 바꾸려면 ffmpeg가 필요합니다. 설치한 뒤 다시 시도해 주세요.',
      );
    }

    final rubberband = await hasRubberband();
    final outputName = pitchVariantFileName(sourceFileName, clamped);
    final outputPath = '${(await cacheDir).path}/$outputName';

    final args = buildVariantArgs(
      input: sourcePath,
      output: outputPath,
      semitones: clamped,
      hasRubberband: rubberband,
    );

    final job = _runner.start(ffmpeg.path!, args);
    final sub = job.lines.listen((line) {
      final progress = FfmpegProgressParser.parse(line, total: total);
      if (progress != null) onProgress?.call(progress);
    });
    final exitCode = await job.exitCode;
    await sub.cancel();

    if (exitCode != 0 || !await File(outputPath).exists()) {
      // 반쯤 만들어진 파일은 지워 다음 시도에서 캐시로 오인되지 않게 한다.
      try {
        final partial = File(outputPath);
        if (await partial.exists()) await partial.delete();
      } catch (_) {}
      return const PitchRenderResult.failure('키 변경에 실패했습니다.');
    }

    return PitchRenderResult.success(outputPath);
  }

  /// 캐시 총 용량(바이트).
  Future<int> cacheSize() async {
    var total = 0;
    try {
      await for (final entity in (await cacheDir).list()) {
        if (entity is File) total += await entity.length();
      }
    } catch (e) {
      debugPrint('피치 캐시 용량 계산 실패: $e');
    }
    return total;
  }

  Future<void> clearCache() async {
    try {
      final dir = await cacheDir;
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('피치 캐시 삭제 실패: $e');
    }
  }
}
