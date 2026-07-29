// file: lib/services/track_asset_service.dart
//
// 반주 파일이 바뀌었을 때 그 파일에서 파생된 캐시를 지운다.
//
// 반주 파일명은 `<제목>_mr<슬롯>.mp3`로 슬롯마다 고정이라, 같은 슬롯에 다른
// 오디오를 넣으면 파일명이 그대로다. 그러면 키 변형본(cache/pitch)과 EQ 레벨
// 분석(cache/levels)이 **예전 오디오 것을 그대로 서빙한다** — 엉뚱한 키의
// 반주가 재생되거나 EQ가 다른 곡처럼 움직인다.
// 반주를 더하거나 빼거나 교체하는 모든 경로에서 이 서비스를 불러야 한다.
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'key_detection_service.dart';
import 'level_analysis_service.dart';
import 'pitch_variant_service.dart';

class TrackAssetService {
  final PitchVariantService pitch;
  final LevelAnalysisService levels;
  final KeyDetectionService keys;

  const TrackAssetService({
    required this.pitch,
    required this.levels,
    required this.keys,
  });

  /// [backingTrackFileName]에서 파생된 캐시를 모두 지운다.
  /// 다른 반주의 캐시는 건드리지 않는다.
  Future<int> invalidate(String backingTrackFileName) async {
    if (backingTrackFileName.trim().isEmpty) return 0;
    var removed = 0;
    removed += await _clearPitchVariants(backingTrackFileName);
    removed += await _clearLevels(backingTrackFileName);
    removed += await _clearKey(backingTrackFileName);
    return removed;
  }

  /// `<stem>__p±n.m4a` 규약에 맞는 변형본을 전부 지운다.
  Future<int> _clearPitchVariants(String fileName) async {
    try {
      final dir = await pitch.cacheDir;
      if (!await dir.exists()) return 0;
      final dot = fileName.lastIndexOf('.');
      final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
      final prefix = '${stem}__p';
      var removed = 0;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.startsWith(prefix)) continue;
        await entity.delete();
        removed += 1;
      }
      return removed;
    } catch (e) {
      debugPrint('키 변형본 캐시 정리 실패($fileName): $e');
      return 0;
    }
  }

  Future<int> _clearLevels(String fileName) async {
    try {
      final dir = await levels.cacheDir;
      final file = File('${dir.path}/$fileName.levels.json');
      if (!await file.exists()) return 0;
      await file.delete();
      return 1;
    } catch (e) {
      debugPrint('레벨 캐시 정리 실패($fileName): $e');
      return 0;
    }
  }

  Future<int> _clearKey(String fileName) async {
    try {
      final dir = await keys.cacheDir;
      final file = File('${dir.path}/$fileName.key.json');
      if (!await file.exists()) return 0;
      await file.delete();
      return 1;
    } catch (e) {
      debugPrint('조성 캐시 정리 실패($fileName): $e');
      return 0;
    }
  }
}
