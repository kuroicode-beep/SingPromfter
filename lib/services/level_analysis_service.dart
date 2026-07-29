// file: lib/services/level_analysis_service.dart
//
// 반주 파일을 밴드별로 훑어 EQ 미터용 음량 시계열을 만든다.
//
// 실시간 FFT 대신 오프라인 분석을 쓰는 이유: audioplayers는 PCM을 노출하지
// 않고, 무대용 앱에 오디오 엔진 교체는 위험이 크다. ffmpeg 필터 패스는
// 실시간보다 훨씬 빠르고, 한 번 분석해 캐시하면 끝이다.
// 피치 변형본은 길이를 보존하므로(rubberband) 원본 분석을 그대로 쓴다.
//
// v2.8.0: 밴드마다 파일을 통째로 디코드하던 것을 **한 번의 디코드**로 바꿨다.
// asplit으로 갈라 밴드별 필터를 건 뒤 amerge로 다채널 한 스트림을 만들고,
// astats의 채널별 메타데이터로 밴드를 구분한다. 실측(248초 트랙): 6밴드
// 6패스 약 9초 → 24밴드 1패스 약 5초. 밴드를 4배로 늘리고도 더 빠르다.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../controllers/recording_controller.dart' show parseRmsLevel;
import '../models/track_levels.dart';
import 'process/external_tool_locator.dart';
import 'process/process_runner.dart';

/// 분석 프레임레이트. 44100 / 1764 = 정확히 25fps.
const int levelAnalysisFps = 25;
const int _samplesPerFrame = 1764;

/// EQ 밴드 수·범위. 40Hz~16kHz를 24등분하면 밴드당 약 0.35옥타브다.
const int levelBandCount = 24;
const double levelBandLowHz = 40;
const double levelBandHighHz = 16000;

/// 밴드마다 겹쳐 거는 필터 단수. 2단(4차, ~24dB/oct).
///
/// 실측으로 정했다: 4단으로 올리면 순음 분리도는 좋아지지만 대역 안까지
/// 깎여 실제 음악에서 프레임 내 최대-최소가 41 → 36으로 **좁아지고**
/// 고역 밴드 몇 개가 0으로 죽는다. 장식용 미터에는 2단이 더 생생하다.
const int levelBandCascade = 2;

/// 로그 등간격 밴드 경계(Hz). null은 상한/하한 없음.
/// 첫 밴드는 하한 없음(서브베이스 손실 방지), 마지막은 상한 없음.
List<({double? lowHz, double? highHz})> buildLevelBands({
  int count = levelBandCount,
  double lowHz = levelBandLowHz,
  double highHz = levelBandHighHz,
}) {
  if (count <= 0) return const [];
  final ratio = math.pow(highHz / lowHz, 1 / count).toDouble();
  final edges = List<double>.generate(
    count + 1,
    (i) => lowHz * math.pow(ratio, i).toDouble(),
    growable: false,
  );
  return [
    for (var i = 0; i < count; i++)
      (
        lowHz: i == 0 ? null : edges[i],
        highHz: i == count - 1 ? null : edges[i + 1],
      ),
  ];
}

final List<({double? lowHz, double? highHz})> levelBands = buildLevelBands();

/// 모든 밴드를 **한 번의 디코드**로 재는 ffmpeg 인자. (순수 함수 — 테스트 대상)
///
/// asplit으로 갈라 밴드마다 필터를 건 뒤 amerge로 N채널 한 스트림으로 합친다.
/// astats는 metadata=1이면 채널마다 `lavfi.astats.<n>.<key>`를 내는데,
/// 그게 밴드를 구분하는 수단이다(조성 감지의 amix는 합쳐 버려서 못 쓴다).
/// measure_perchannel/measure_overall로 RMS_level 하나만 남기지 않으면
/// 프레임마다 수백 줄이 쏟아져 파싱이 분석보다 오래 걸린다.
List<String> buildAllBandAnalysisArgs({
  required String input,
  List<({double? lowHz, double? highHz})>? bands,
}) {
  final list = bands ?? levelBands;
  final count = list.length;
  final buffer = StringBuffer()
    ..write('aresample=44100,aformat=channel_layouts=mono,asplit=$count');
  for (var i = 0; i < count; i++) {
    buffer.write('[b$i]');
  }
  buffer.write(';');
  for (var i = 0; i < count; i++) {
    final filters = <String>[
      if (list[i].lowHz != null)
        ...List.filled(
          levelBandCascade,
          'highpass=f=${list[i].lowHz!.toStringAsFixed(2)}',
        ),
      if (list[i].highHz != null)
        ...List.filled(
          levelBandCascade,
          'lowpass=f=${list[i].highHz!.toStringAsFixed(2)}',
        ),
    ];
    // 상·하한이 모두 없는 밴드(밴드가 하나뿐일 때)는 그냥 통과시킨다.
    buffer.write('[b$i]${filters.isEmpty ? 'anull' : filters.join(',')}[c$i];');
  }
  for (var i = 0; i < count; i++) {
    buffer.write('[c$i]');
  }
  buffer
    ..write('amerge=inputs=$count,')
    ..write('asetnsamples=n=$_samplesPerFrame,')
    ..write('astats=metadata=1:reset=1:measure_perchannel=RMS_level')
    ..write(':measure_overall=none,')
    ..write('ametadata=print:file=-');

  return [
    '-hide_banner',
    '-i', input,
    '-filter_complex', buffer.toString(),
    '-f', 'null',
    '-',
  ];
}

/// `lavfi.astats.<n>.RMS_level=<dB>` 한 줄에서 (밴드, dB)를 뽑는다.
///
/// 채널 번호는 1부터라 0-based로 낮춘다. 무음(-inf/nan)은 -100으로 본다.
/// Overall.* 줄은 무시한다(measure_overall=none이라 없어야 정상이지만 방어).
({int band, double dbfs})? parseBandRmsLevel(String line) {
  final match = _bandRms.firstMatch(line);
  if (match == null) return null;
  final band = int.tryParse(match.group(1)!);
  if (band == null || band < 1) return null;
  final raw = match.group(2)!;
  final value = double.tryParse(raw);
  return (
    band: band - 1,
    dbfs: value == null || value.isNaN || value.isInfinite ? -100.0 : value,
  );
}

final RegExp _bandRms = RegExp(
  r'lavfi\.astats\.(\d+)\.RMS_level=(-?[\d.]+|-?inf|nan)',
);

/// 밴드 하나를 분석하는 ffmpeg 인자. (순수 함수 — 테스트 대상)
///
/// 단일 패스가 실패했을 때 쓰는 폴백 경로다. 느리지만(밴드당 전체 디코드)
/// 필터그래프가 단순해 확실히 동작한다.
List<String> buildBandAnalysisArgs({
  required String input,
  double? lowHz,
  double? highHz,
}) {
  final filters = <String>[
    'aresample=44100',
    'aformat=channel_layouts=mono',
    if (lowHz != null) 'highpass=f=${lowHz.toStringAsFixed(2)}',
    if (highHz != null) 'lowpass=f=${highHz.toStringAsFixed(2)}',
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
      final levels = TrackLevels.decode(await file.readAsString());
      // 버전을 안 올리고 밴드 수만 바꿔도 낡은 캐시를 물지 않게 하는 안전망.
      // 여기서 null을 주면 analyze()가 그대로 재분석해 파일을 덮어쓴다.
      if (levels != null && levels.bandCount != levelBands.length) return null;
      return levels;
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
      // 한 번의 디코드로 전부 재 본다. 실패하면 밴드별 순차 패스로 물러선다.
      var perBand = await _analyzeSinglePass(ffmpeg.path!, sourcePath);
      if (perBand == null) {
        debugPrint('EQ 단일 패스 분석 실패 — 밴드별 순차 분석으로 대체합니다.');
        perBand = await _analyzePerBand(ffmpeg.path!, sourcePath);
      }
      if (perBand == null) return null;

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

  /// 한 번의 디코드로 모든 밴드를 잰다. 결과가 온전하지 않으면 null.
  Future<List<List<int>>?> _analyzeSinglePass(
    String ffmpegPath,
    String sourcePath,
  ) async {
    final perBand = List.generate(
      levelBands.length,
      (_) => <int>[],
      growable: false,
    );
    final job = _runner.start(
      ffmpegPath,
      buildAllBandAnalysisArgs(input: sourcePath),
    );
    final sub = job.lines.listen((line) {
      final hit = parseBandRmsLevel(line);
      if (hit == null || hit.band >= perBand.length) return;
      perBand[hit.band].add(quantizeLevel(hit.dbfs));
    });
    final exitCode = await job.exitCode;
    await sub.cancel();

    if (exitCode != 0) return null;
    // 한 밴드라도 비어 있으면 필터그래프가 기대와 다르게 붙은 것이다.
    if (perBand.any((s) => s.isEmpty)) return null;
    return perBand;
  }

  /// 밴드마다 파일을 다시 디코드하는 폴백. 느리지만 확실하다.
  Future<List<List<int>>?> _analyzePerBand(
    String ffmpegPath,
    String sourcePath,
  ) async {
    final perBand = <List<int>>[];
    for (final band in levelBands) {
      final series = <int>[];
      final job = _runner.start(
        ffmpegPath,
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
    return perBand;
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
