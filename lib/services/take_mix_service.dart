// file: lib/services/take_mix_service.dart
//
// 녹음(보컬)과 반주를 하나의 파일로 합치고, 재생하던 반주 파일에서
// 녹음 구간과 같은 조각을 잘라낸다.
//
// 정렬: 반주 조각(acc)이 있으면 둘 다 t=0에서 시작하므로 지연이 필요 없다.
// 조각이 없는 구 테이크는 녹음 시작 시점의 재생 위치(alignOffsetMs)를
// 보컬에 지연으로 걸어 맞춘다.
import 'dart:io';

import '../models/recording_take.dart';
import 'process/external_tool_locator.dart';
import 'process/process_runner.dart';

/// 밀리초를 ffmpeg 초 표기(소수 3자리)로 바꾼다. (순수 함수)
String ffmpegSeconds(int ms) => (ms / 1000).toStringAsFixed(3);

/// 믹스 밸런스(0=반주만, 1=보컬만)를 반주/보컬 게인 쌍으로 바꾼다.
/// 0.5에서 둘 다 1.0(현행 동작 유지), 극단으로 갈수록 반대쪽이 줄고
/// 같은 쪽은 1.6배까지만 키운다(클리핑 방지). (순수 함수 — 테스트 대상)
({double acc, double vocal}) mixGains(double balance) {
  final b = balance.clamp(0.0, 1.0);
  double clampGain(double v) => v.clamp(0.0, 1.6);
  return (acc: clampGain((1 - b) * 2), vocal: clampGain(b * 2));
}

/// 리버브 프리셋의 aecho 필터 문자열. none이면 null. (순수 함수)
String? reverbFilter(ReverbPreset preset) => switch (preset) {
  ReverbPreset.none => null,
  ReverbPreset.karaoke => 'aecho=0.8:0.85:60:0.35',
  ReverbPreset.hall => 'aecho=0.8:0.88:220:0.4',
  ReverbPreset.studio => 'aecho=0.7:0.8:40:0.25',
};

/// 믹스 ffmpeg 인자를 만든다. (순수 함수 — 테스트 대상)
///
/// [alignMs]만큼 보컬을 늦춰 반주 타임라인 위에 얹는다.
/// duration=first — 반주 길이에 맞추고 남는 보컬은 자른다.
/// 보컬 체인 순서: adelay → 노이즈 제거 → 리버브 → 볼륨.
List<String> buildMixArgs({
  required String backingPath,
  required String vocalPath,
  required String outputPath,
  required int alignMs,
  double mixBalance = 0.5,
  ReverbPreset reverbPreset = ReverbPreset.none,
  bool noiseReduction = false,
}) {
  final delay = alignMs < 0 ? 0 : alignMs;
  final gains = mixGains(mixBalance);
  final vocalChain = [
    'adelay=$delay|$delay',
    if (noiseReduction) 'afftdn',
    if (reverbFilter(reverbPreset) != null) reverbFilter(reverbPreset)!,
    'volume=${gains.vocal.toStringAsFixed(2)}',
  ].join(',');
  return [
    '-y',
    '-i', backingPath,
    '-i', vocalPath,
    '-filter_complex',
    '[0:a]volume=${gains.acc.toStringAsFixed(2)}[b];'
        '[1:a]$vocalChain[v];'
        '[b][v]amix=inputs=2:duration=first:normalize=0[a]',
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

/// 재생하던 반주 파일에서 녹음 구간과 같은 조각을 잘라내는 인자. (순수 함수)
List<String> buildAccompanimentCutArgs({
  required String sourcePath,
  required String outputPath,
  required int startMs,
  required int durationMs,
}) {
  return [
    '-y',
    '-ss', ffmpegSeconds(startMs < 0 ? 0 : startMs),
    '-t', ffmpegSeconds(durationMs),
    '-i', sourcePath,
    '-vn',
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
    double mixBalance = 0.5,
    ReverbPreset reverbPreset = ReverbPreset.none,
    bool noiseReduction = false,
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

    // 실패해도 기존 믹스가 남도록 임시 파일에 만들고 성공 시 교체한다.
    final tempPath = '$outputPath.tmp.m4a';
    final result = await _runner.run(
      ffmpeg.path!,
      buildMixArgs(
        backingPath: backingPath,
        vocalPath: vocalPath,
        outputPath: tempPath,
        alignMs: alignMs,
        mixBalance: mixBalance,
        reverbPreset: reverbPreset,
        noiseReduction: noiseReduction,
      ),
    );

    if (!result.ok || !await File(tempPath).exists()) {
      await _deleteIfExists(tempPath);
      return const TakeMixResult.failure('합치기에 실패했습니다.');
    }
    try {
      await File(tempPath).rename(outputPath);
    } catch (_) {
      // 교체 실패 시 임시 파일을 남기지 않는다.
      await _deleteIfExists(tempPath);
      return const TakeMixResult.failure('합친 파일을 저장하지 못했습니다.');
    }
    return TakeMixResult.success(outputPath);
  }

  /// 재생하던 반주 파일에서 녹음 구간 조각을 잘라 저장한다.
  Future<TakeMixResult> cutAccompaniment({
    required String sourcePath,
    required String outputPath,
    required int startMs,
    required int durationMs,
  }) async {
    final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);
    if (!ffmpeg.found) {
      return const TakeMixResult.failure('반주를 잘라내려면 ffmpeg가 필요합니다.');
    }
    if (!await File(sourcePath).exists()) {
      return const TakeMixResult.failure('녹음 당시 반주 파일을 찾을 수 없습니다.');
    }
    if (durationMs <= 0) {
      return const TakeMixResult.failure('녹음 길이가 없어 반주를 잘라낼 수 없습니다.');
    }

    final result = await _runner.run(
      ffmpeg.path!,
      buildAccompanimentCutArgs(
        sourcePath: sourcePath,
        outputPath: outputPath,
        startMs: startMs,
        durationMs: durationMs,
      ),
    );

    if (!result.ok || !await File(outputPath).exists()) {
      await _deleteIfExists(outputPath);
      return const TakeMixResult.failure('반주 잘라내기에 실패했습니다.');
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
      await _deleteIfExists(outputPath);
      return const TakeMixResult.failure('듀엣 합성에 실패했습니다.');
    }
    return TakeMixResult.success(outputPath);
  }

  Future<void> _deleteIfExists(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
