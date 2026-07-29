// file: lib/services/vocal_segments_service.dart
//
// 곡의 노래 구간을 분석하고 캐시한다. 분석은 ffmpeg 디코드 2회(원곡·MR)라
// 비싸므로, 결과를 파일로 남기고 메모리에도 들고 있는다.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/vocal_segments.dart';
import 'lyrics_align_service.dart';

class VocalSegmentsService {
  final LyricsAlignService _align;

  VocalSegmentsService({LyricsAlignService? align})
    : _align = align ?? LyricsAlignService();

  /// 파일 캐시를 읽은 뒤에도 재분석하지 않도록 메모리에 얹는다.
  /// null도 기억한다 — 소리를 못 재는 곡을 선택할 때마다 다시 재지 않게.
  final Map<String, VocalSegments?> _memory = {};

  Future<Directory> get cacheDir async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/data/cache/vocalseg');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _cacheFile(String cacheKey) async =>
      File('${(await cacheDir).path}/$cacheKey.vocalseg.json');

  Future<VocalSegments?> _readCache(String cacheKey) async {
    try {
      final file = await _cacheFile(cacheKey);
      if (!await file.exists()) return null;
      // decode가 버전 불일치를 null로 돌려주면 그대로 재분석 경로를 탄다.
      return VocalSegments.decode(await file.readAsString());
    } catch (e) {
      debugPrint('노래 구간 캐시 읽기 실패($cacheKey): $e');
      return null;
    }
  }

  /// 노래 구간을 얻는다. 캐시가 있으면 그걸, 없으면 분석해서 저장한다.
  ///
  /// [cacheKey]는 MR 파일명을 쓴다 — 반주가 갈리면 TrackAssetService가
  /// 같은 이름으로 invalidate를 불러 이 캐시도 함께 지워진다.
  Future<VocalSegments?> analyze({
    required String originalPath,
    required String mrPath,
    required String cacheKey,
  }) async {
    if (_memory.containsKey(cacheKey)) return _memory[cacheKey];

    final cached = await _readCache(cacheKey);
    if (cached != null) {
      _memory[cacheKey] = cached;
      return cached;
    }

    final original = await _align.envelope(originalPath);
    final mr = await _align.envelope(mrPath);
    if (original.isEmpty || mr.isEmpty) {
      // 파일 캐시는 남기지 않는다 — ffmpeg가 잠깐 없었던 것일 수 있다.
      _memory[cacheKey] = null;
      return null;
    }

    final segments = VocalSegments(
      detectVocalSegments(vocalPresence(original, mr)),
    );
    _memory[cacheKey] = segments;
    try {
      await (await _cacheFile(cacheKey)).writeAsString(segments.encode());
    } catch (e) {
      debugPrint('노래 구간 캐시 쓰기 실패($cacheKey): $e');
    }
    return segments;
  }

  /// 반주가 갈릴 때 낡은 구간을 지운다. TrackAssetService.invalidate가 부른다.
  Future<int> clearFor(String cacheKey) async {
    _memory.remove(cacheKey);
    try {
      final file = await _cacheFile(cacheKey);
      if (!await file.exists()) return 0;
      await file.delete();
      return 1;
    } catch (e) {
      debugPrint('노래 구간 캐시 정리 실패($cacheKey): $e');
      return 0;
    }
  }
}
