// file: lib/models/track_levels.dart
//
// 반주 파일의 밴드별 음량 시계열. EQ 미터가 재생 위치로 조회한다.
// 오프라인 분석(ffmpeg) 결과를 JSON으로 캐시해 두고 재사용한다.
import 'dart:convert';

class TrackLevels {
  /// 형식이 바뀔 때마다 올린다. 밴드 수가 바뀌어도 올려야 한다 —
  /// 낡은 캐시가 조용히 살아남는 것을 막는 유일한 장치다.
  static const int schemaVersion = 2;

  /// 초당 프레임 수 (분석 시 25fps 고정).
  final int fps;
  final int bandCount;

  /// frames[i] = 밴드별 레벨 0..100.
  final List<List<int>> frames;

  const TrackLevels({
    required this.fps,
    required this.bandCount,
    required this.frames,
  });

  bool get isEmpty => frames.isEmpty;

  /// 재생 위치의 프레임. 범위 밖(곡 끝 이후 등)이면 null.
  List<int>? frameAt(Duration position) {
    if (frames.isEmpty || position.isNegative) return null;
    final index = position.inMilliseconds * fps ~/ 1000;
    if (index >= frames.length) return null;
    return frames[index];
  }

  /// 재생 위치의 밴드 레벨을 0..1로, 프레임 사이는 선형 보간해서 준다.
  ///
  /// 분석은 25fps인데 그리기는 60Hz라 같은 프레임을 2.4번씩 반복하게 된다.
  /// 굵은 막대 6개일 때는 티가 안 났지만 얇은 막대 24개에서는 계단이 보인다.
  List<double>? sampleAt(Duration position) {
    if (frames.isEmpty || position.isNegative) return null;
    final t = position.inMilliseconds * fps / 1000.0;
    final i = t.floor();
    if (i < 0 || i >= frames.length) return null;

    final a = frames[i];
    final b = i + 1 < frames.length ? frames[i + 1] : a;
    final f = t - i;
    final n = a.length < b.length ? a.length : b.length;
    return [
      for (var k = 0; k < n; k++) (a[k] + (b[k] - a[k]) * f) / 100.0,
    ];
  }

  String encode() => jsonEncode({
    'version': schemaVersion,
    'fps': fps,
    'bands': bandCount,
    'frames': frames,
  });

  /// JSON을 파싱한다. 형식이 다르면 null.
  ///
  /// v2.7.0까지는 `version > schemaVersion`, 즉 **상위 버전만** 거부했다.
  /// 그래서 밴드 수를 바꿔도 이미 재생해 본 곡은 영영 옛 캐시를 돌려줬다 —
  /// 어떤 곡은 굵은 막대 6개, 어떤 곡은 얇은 막대 24개가 되고, 재생 이력에
  /// 따라 달라지니 간헐적 버그처럼 보인다. 오류도 로그도 없다.
  /// 이제 **정확히 일치**할 때만 받아들인다.
  static TrackLevels? decode(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      final version = json['version'];
      if (version is! int || version != schemaVersion) return null;
      final fps = json['fps'];
      final bands = json['bands'];
      final rawFrames = json['frames'];
      if (fps is! int || bands is! int || rawFrames is! List) return null;
      final frames = rawFrames
          .whereType<List<dynamic>>()
          .map(
            (f) => f
                .whereType<num>()
                .map((v) => v.toInt().clamp(0, 100))
                .toList(growable: false),
          )
          .toList(growable: false);
      // 프레임 폭이 밴드 수와 어긋난 캐시도 거부한다(예전에는 검사하지 않아
      // 밴드가 모자란 프레임이 그대로 렌더됐다).
      if (frames.any((f) => f.length != bands)) return null;
      return TrackLevels(fps: fps, bandCount: bands, frames: frames);
    } catch (_) {
      return null;
    }
  }
}
