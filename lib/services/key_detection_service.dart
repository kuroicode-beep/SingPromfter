// file: lib/services/key_detection_service.dart
//
// 반주에서 곡의 조성(C, Am …)을 추정한다.
//
// ffmpeg에는 크로마·조성 필터가 없다. 대신 12반음 각각에 대해 여러 옥타브의
// 대역만 남기고(bandpass) 합쳐(amix) 전체 에너지를 재는 패스를 12번 돌려
// 크로마 벡터를 만든 뒤, Krumhansl–Kessler 프로파일과 상관을 재 가장 잘 맞는
// 24가지(장/단 × 12) 중 하나를 고른다.
//
// 곡 전체를 다 보지 않고 가운데 구간만 표본으로 쓴다 — 인트로·아웃트로는
// 조성이 흐릿하고, 60초면 판정에 충분하며 12패스 합쳐 5초 남짓에 끝난다.
// 레벨 분석과 같은 방식으로 캐시하고, 반주가 바뀌면 함께 버린다.
//
// 반드시 **MR**을 재야 한다. 실측(넌 언제나, 247.8초)에서 MR과 그 −2키 렌더는
// A♭ / F♯ — 정확히 2반음 차 — 로 네 가지 필터 설정 모두에서 일치했지만,
// 보컬이 살아 있는 원곡은 같은 곡인데도 딸림음인 E♭로 끌려갔다. 멜로디가
// 상관을 흔드는 고전적인 으뜸음/딸림음 혼동이다. 키조절 기준이 MR인 것과
// 같은 규약을 쓴다.
//
// 상관계수는 "쓰레기 입력 거르기"에는 쓸모가 있지만 정답과 오답을 가르지는
// 못한다(위의 잘못된 E♭도 0.87이었다). 그래서 감지값은 제안일 뿐이고
// 사용자가 언제든 고쳐 쓸 수 있어야 한다.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../controllers/recording_controller.dart' show parseRmsLevel;
import '../utils/music_key.dart';
import 'process/external_tool_locator.dart';
import 'process/process_runner.dart';

/// 표본 구간 길이(초). 길수록 정확하지만 그만큼 오래 걸린다.
const int keySampleSeconds = 60;

/// 표본을 뜨는 지점 — 곡 앞쪽 20% 지난 자리(인트로 회피).
const double keySampleStartRatio = 0.2;

/// 대역을 뜰 옥타브 범위. C2(65Hz)~C6(1046Hz)면 반주의 화성이 대부분 들어온다.
const int keyLowestOctave = 2;
const int keyHighestOctave = 6;

/// bandpass를 몇 번 겹칠지. ffmpeg의 bandpass는 2차 biquad라 한 번만 걸면
/// 스커트가 완만해 저역 에너지가 열두 대역 전부로 샌다. 3단으로 겹치면
/// 실측 크로마 대비가 0.40 → 0.67로 넓어졌다(비용은 무시할 만하다).
const int keyBandpassCascade = 3;

/// bandpass의 Q. 48까지 올려 봤지만 대비 이득이 미미해 24로 둔다.
const int keyBandpassQ = 24;

/// 반음 하나의 중심 주파수들. (순수 함수)
List<double> pitchClassFrequencies(int pitchClass) {
  final freqs = <double>[];
  for (var octave = keyLowestOctave; octave <= keyHighestOctave; octave++) {
    // A4 = 440Hz 기준. pitchClass 9가 A다.
    final semitonesFromA4 = (pitchClass - 9) + (octave - 4) * 12;
    freqs.add(440.0 * math.pow(2, semitonesFromA4 / 12.0));
  }
  return freqs;
}

/// 반음 하나의 에너지를 재는 ffmpeg 인자. (순수 함수 — 테스트 대상)
List<String> buildChromaArgs({
  required String input,
  required int pitchClass,
  required double startSeconds,
  int sampleSeconds = keySampleSeconds,
}) {
  final freqs = pitchClassFrequencies(pitchClass);
  final labels = List.generate(freqs.length, (i) => String.fromCharCode(97 + i));

  final buffer = StringBuffer()
    ..write('aresample=44100,aformat=channel_layouts=mono,')
    ..write('asplit=${freqs.length}');
  for (final label in labels) {
    buffer.write('[$label]');
  }
  buffer.write(';');
  for (var i = 0; i < freqs.length; i++) {
    final f = freqs[i].toStringAsFixed(2);
    final chain = List.filled(
      keyBandpassCascade,
      'bandpass=f=$f:width_type=q:w=$keyBandpassQ',
    ).join(',');
    buffer.write('[${labels[i]}]$chain[${labels[i]}1];');
  }
  for (final label in labels) {
    buffer.write('[${label}1]');
  }
  buffer
    ..write('amix=inputs=${freqs.length}:normalize=0,')
    ..write('astats=metadata=1:reset=0,')
    ..write('ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-');

  return [
    '-hide_banner',
    '-ss', startSeconds.toStringAsFixed(2),
    '-t', '$sampleSeconds',
    '-i', input,
    '-filter_complex', buffer.toString(),
    '-f', 'null',
    '-',
  ];
}

/// dB 벡터를 0~1 크로마로 바꾼다. (순수 함수)
List<double> chromaFromDecibels(List<double> db) {
  if (db.isEmpty) return const [];
  // dB → 진폭. 무음(-100)은 0에 가깝게 떨어진다.
  final linear = db
      .map((v) => math.pow(10, v / 20.0).toDouble())
      .toList(growable: false);
  final max = linear.reduce((a, b) => a > b ? a : b);
  if (max <= 0) return List.filled(db.length, 0);
  return linear.map((v) => v / max).toList(growable: false);
}

/// Krumhansl–Kessler 조성 프로파일.
const List<double> majorProfile = [
  6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88,
];
const List<double> minorProfile = [
  6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17,
];

class KeyEstimate {
  final MusicKey key;

  /// 상관계수(-1~1). 낮으면 자신 없다는 뜻이다.
  final double confidence;

  const KeyEstimate({required this.key, required this.confidence});

  /// 이 정도는 넘어야 화면에 자신 있게 내놓는다.
  bool get isConfident => confidence >= 0.6;
}

/// 크로마 벡터에서 조성을 고른다. (순수 함수 — 테스트 대상)
KeyEstimate? detectKeyFromChroma(List<double> chroma) {
  if (chroma.length != 12) return null;
  if (chroma.every((v) => v <= 0)) return null;

  KeyEstimate? best;
  for (var tonic = 0; tonic < 12; tonic++) {
    for (final mode in KeyMode.values) {
      final profile = mode == KeyMode.major ? majorProfile : minorProfile;
      final rotated = List<double>.generate(
        12,
        (i) => profile[(i - tonic + 12) % 12],
      );
      final r = _correlation(chroma, rotated);
      if (best == null || r > best.confidence) {
        best = KeyEstimate(key: MusicKey(tonic, mode), confidence: r);
      }
    }
  }
  return best;
}

double _correlation(List<double> a, List<double> b) {
  final n = a.length;
  final meanA = a.reduce((x, y) => x + y) / n;
  final meanB = b.reduce((x, y) => x + y) / n;
  var num = 0.0, denA = 0.0, denB = 0.0;
  for (var i = 0; i < n; i++) {
    final da = a[i] - meanA;
    final db = b[i] - meanB;
    num += da * db;
    denA += da * da;
    denB += db * db;
  }
  if (denA <= 0 || denB <= 0) return 0;
  return num / math.sqrt(denA * denB);
}

class KeyDetectionService {
  final ProcessRunner _runner;
  final ExternalToolLocator _locator;
  final Set<String> _inFlight = {};

  KeyDetectionService({
    ProcessRunner runner = const SystemProcessRunner(),
    ExternalToolLocator? locator,
  }) : _runner = runner,
       _locator = locator ?? ExternalToolLocator(runner: runner);

  Future<Directory> get cacheDir async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/data/cache/keys');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _cacheFile(String sourceFileName) async =>
      File('${(await cacheDir).path}/$sourceFileName.key.json');

  Future<KeyEstimate?> cached(String sourceFileName) async {
    try {
      final file = await _cacheFile(sourceFileName);
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return null;
      final key = MusicKey.fromStorage(json['key'] as String?);
      if (key == null) return null;
      return KeyEstimate(
        key: key,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      );
    } catch (e) {
      debugPrint('조성 캐시 읽기 실패: $e');
      return null;
    }
  }

  /// 반주를 분석해 조성을 추정한다. ffmpeg가 없거나 실패하면 null.
  Future<KeyEstimate?> analyze({
    required String sourcePath,
    required String sourceFileName,
    Duration? duration,
  }) async {
    final hit = await cached(sourceFileName);
    if (hit != null) return hit;
    if (_inFlight.contains(sourceFileName)) return null;

    final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);
    if (!ffmpeg.found) return null;

    _inFlight.add(sourceFileName);
    try {
      final total = duration?.inSeconds ?? 0;
      final start = total > keySampleSeconds
          ? (total * keySampleStartRatio).clamp(
              0,
              (total - keySampleSeconds).toDouble(),
            )
          : 0.0;

      final db = <double>[];
      for (var pc = 0; pc < 12; pc++) {
        final level = await _measure(
          ffmpegPath: ffmpeg.path!,
          sourcePath: sourcePath,
          pitchClass: pc,
          startSeconds: start.toDouble(),
        );
        if (level == null) return null;
        db.add(level);
      }

      final estimate = detectKeyFromChroma(chromaFromDecibels(db));
      if (estimate == null) return null;
      try {
        await (await _cacheFile(sourceFileName)).writeAsString(
          jsonEncode({
            'key': estimate.key.storageValue,
            'confidence': estimate.confidence,
          }),
        );
      } catch (e) {
        debugPrint('조성 캐시 저장 실패: $e');
      }
      return estimate;
    } catch (e) {
      debugPrint('조성 분석 실패: $e');
      return null;
    } finally {
      _inFlight.remove(sourceFileName);
    }
  }

  /// 반음 하나의 누적 RMS(dB). astats는 reset=0이라 마지막 값이 전체 값이다.
  Future<double?> _measure({
    required String ffmpegPath,
    required String sourcePath,
    required int pitchClass,
    required double startSeconds,
  }) async {
    double? last;
    final job = _runner.start(
      ffmpegPath,
      buildChromaArgs(
        input: sourcePath,
        pitchClass: pitchClass,
        startSeconds: startSeconds,
      ),
    );
    final sub = job.lines.listen((line) {
      final value = parseRmsLevel(line);
      if (value != null) last = value;
    });
    final exitCode = await job.exitCode;
    await sub.cancel();
    if (exitCode != 0) return null;
    return last;
  }

  Future<void> clearCache() async {
    try {
      final dir = await cacheDir;
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('조성 캐시 삭제 실패: $e');
    }
  }
}
