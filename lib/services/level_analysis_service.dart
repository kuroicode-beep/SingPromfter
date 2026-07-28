// file: lib/services/level_analysis_service.dart
//
// 반주 파일을 밴드별로 훑어 EQ 미터용 음량 시계열을 만든다.
//
// 실시간 FFT 대신 오프라인 분석을 쓰는 이유: audioplayers는 PCM을 노출하지
// 않고, 무대용 앱에 오디오 엔진 교체는 위험이 크다. ffmpeg 필터 패스는
// 실시간보다 훨씬 빨라(패스당 1~2초) 한 번 분석해 캐시하면 끝이다.
// 피치 변형본은 길이를 보존하므로(rubberband) 원본 분석을 그대로 쓴다.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../controllers/recording_controller.dart' show parseRmsLevel;
import '../models/track_levels.dart';
import 'process/external_tool_locator.dart';
import 'process/process_runner.dart';

/// 분석 프레임레이트. 44100 / 1764 = 정확히 25fps.
const int levelAnalysisFps = 25;
const int _samplesPerFrame = 1764;

/// EQ 밴드 경계(Hz). null은 상한/하한 없음.
const List<({double? lowHz, double? highHz})> levelBands = [
  (lowHz: null, highHz: 150),
  (lowHz: 150, highHz: 400),
  (lowHz: 400, highHz: 1000),
  (lowHz: 1000, highHz: 2500),
  (lowHz: 2500, highHz: 6000),
  (lowHz: 6000, highHz: null),
];

/// 밴드 하나를 분석하는 ffmpeg 인자. (순수 함수 — 테스트 대상)
List<String> buildBandAnalysisArgs({
  required String input,
  double? lowHz,
  double? highHz,
}) {
  final filters = <String>[
    'aresample=44100',
    'aformat=channel_layouts=mono',
    if (lowHz != null) 'highpass=f=$lowHz',
    if (highHz != null) 'lowpass=f=$highHz',
    'asetnsamples=n=$_samplesPerFrame',
    'astats=metadata=1:reset=1',
    'ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-',
  ];
  return [
    '-hide_banner',
    '-i', input,
    '-af', filters.join(','),
    '-f', 'null',
    '-',
  ];
}

/// dBFS를 0..100 정수 레벨로 바꾼다. (-60dB 플로어 — 녹음 미터와 동일 기준)
int quantizeLevel(double dbfs) {
  const floor = -60.0;
  if (dbfs <= floor) return 0;
  if (dbfs >= 0) return 100;
  return ((dbfs - floor) / -floor * 100).round();
}

/// 밴드별 시계열을 프레임 배열로 합친다. 길이가 다르면 최단에 맞춘다.
TrackLevels assembleLevels(
  List<List<int>> perBandSeries, {
  int fps = levelAnalysisFps,
}) {
  if (perBandSeries.isEmpty) {
    return TrackLevels(fps: fps, bandCount: 0, frames: const []);
  }
  final length = perBandSeries
      .map((s) => s.length)
      .reduce((a, b) => a < b ? a : b);
  final frames = List<List<int>>.generate(
    length,
    (i) => perBandSeries
        .map((series) => series[i])
        .toList(growable: false),
    growable: false,
  );
  return TrackLevels(
    fps: fps,
    bandCount: perBandSeries.length,
    frames: frames,
  );
}

class LevelAnalysisService {
  final ProcessRunner _runner;
  final ExternalToolLocator _locator;

  /// 같은 파일을 동시에 두 번 분석하지 않게 막는다.
  final Set<String> _inFlight = {};

  LevelAnalysisService({
    ProcessRunner runner = const SystemProcessRunner(),
    ExternalToolLocator? locator,
  }) : _runner = runner,
       _locator = locator ?? ExternalToolLocator(runner: runner);

  Future<Directory> get cacheDir async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/data/cache/levels');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _cacheFile(String sourceFileName) async =>
      File('${(await cacheDir).path}/$sourceFileName.levels.json');

  /// 캐시된 분석 결과. 없으면 null.
  Future<TrackLevels?> cached(String sourceFileName) async {
    try {
      final file = await _cacheFile(sourceFileName);
      if (!await file.exists()) return null;
      return TrackLevels.decode(await file.readAsString());
    } catch (e) {
      debugPrint('레벨 캐시 읽기 실패: $e');
      return null;
    }
  }

  /// 분석해 캐시에 저장한다. ffmpeg가 없거나 실패하면 null (무해한 폴백).
  Future<TrackLevels?> analyze({
    required String sourcePath,
    required String sourceFileName,
  }) async {
    final existing = await cached(sourceFileName);
    if (existing != null) return existing;
    if (_inFlight.contains(sourceFileName)) return null;

    final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);
    if (!ffmpeg.found) return null;

    _inFlight.add(sourceFileName);
    try {
      final perBand = <List<int>>[];
      for (final band in levelBands) {
        final series = <int>[];
        final job = _runner.start(
          ffmpeg.path!,
          buildBandAnalysisArgs(
            input: sourcePath,
            lowHz: band.lowHz,
            highHz: band.highHz,
          ),
        );
        final sub = job.lines.listen((line) {
          final rms = parseRmsLevel(line);
          if (rms != null) series.add(quantizeLevel(rms));
        });
        final exitCode = await job.exitCode;
        await sub.cancel();
        if (exitCode != 0 || series.isEmpty) return null;
        perBand.add(series);
      }

      final levels = assembleLevels(perBand);
      if (levels.isEmpty) return null;
      try {
        await (await _cacheFile(sourceFileName)).writeAsString(levels.encode());
      } catch (e) {
        // 캐시 저장 실패는 치명적이지 않다 — 이번 세션에서는 그대로 쓴다.
        debugPrint('레벨 캐시 저장 실패: $e');
      }
      return levels;
    } catch (e) {
      debugPrint('레벨 분석 실패: $e');
      return null;
    } finally {
      _inFlight.remove(sourceFileName);
    }
  }

  /// 캐시 총 용량(바이트).
  Future<int> cacheSize() async {
    var total = 0;
    try {
      await for (final entity in (await cacheDir).list()) {
        if (entity is File) total += await entity.length();
      }
    } catch (e) {
      debugPrint('레벨 캐시 용량 계산 실패: $e');
    }
    return total;
  }

  Future<void> clearCache() async {
    try {
      final dir = await cacheDir;
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('레벨 캐시 삭제 실패: $e');
    }
  }
}
