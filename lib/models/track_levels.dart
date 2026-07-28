// file: lib/models/track_levels.dart
//
// 반주 파일의 밴드별 음량 시계열. EQ 미터가 재생 위치로 조회한다.
// 오프라인 분석(ffmpeg) 결과를 JSON으로 캐시해 두고 재사용한다.
import 'dart:convert';

class TrackLevels {
  static const int schemaVersion = 1;

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

  String encode() => jsonEncode({
    'version': schemaVersion,
    'fps': fps,
    'bands': bandCount,
    'frames': frames,
  });

  /// JSON을 파싱한다. 형식이 다르거나 상위 버전이면 null.
  static TrackLevels? decode(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      final version = json['version'];
      if (version is! int || version > schemaVersion) return null;
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
      return TrackLevels(fps: fps, bandCount: bands, frames: frames);
    } catch (_) {
      return null;
    }
  }
}
