// file: lib/models/vocal_segments.dart
//
// 노래(보컬) 구간 목록 — 원곡−MR 포락선 비교로 얻는다.
//
// 용도: 싱크 가사가 없는 곡의 줄 배분. 줄을 곡 전체에 고르게 뿌리면 전주
// 동안 가사가 흘러가고 간주에도 진행된다(실측: 「선물」은 224초 중 노래가
// 55%뿐, 전주만 13.7초). "노래 구간 안에서만 시간이 흐르는" 축을 만들기
// 위한 재료다.
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/lyrics_align_service.dart' show vocalThreshold;

/// 노래가 이어지는 한 구간(ms, 파일 원본 축).
@immutable
class VocalSegment {
  final int startMs;
  final int endMs;

  const VocalSegment({required this.startMs, required this.endMs});

  int get durationMs => endMs - startMs;

  Map<String, dynamic> toJson() => {'startMs': startMs, 'endMs': endMs};

  factory VocalSegment.fromJson(Map<String, dynamic> json) => VocalSegment(
    startMs: (json['startMs'] as num?)?.toInt() ?? 0,
    endMs: (json['endMs'] as num?)?.toInt() ?? 0,
  );
}

/// 곡 하나의 노래 구간 전체.
@immutable
class VocalSegments {
  /// 구간 규칙(gap·최소 길이·문턱)이 바뀌면 반드시 올린다.
  /// 가드는 정확 일치 — "상위 버전만 거부"는 낡은 캐시를 영영 서빙한다
  /// (레벨 캐시에서 실제로 겪은 버그다).
  static const int schemaVersion = 1;

  final List<VocalSegment> segments;

  const VocalSegments(this.segments);

  bool get isEmpty => segments.isEmpty;

  /// 노래 시간 합계 — 구간 축의 전체 길이.
  int get totalSungMs =>
      segments.fold(0, (sum, s) => sum + s.durationMs);

  String encode() => jsonEncode({
    'version': schemaVersion,
    'segments': [for (final s in segments) s.toJson()],
  });

  static VocalSegments? decode(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      if ((json['version'] as num?)?.toInt() != schemaVersion) return null;
      final list = json['segments'];
      if (list is! List) return null;
      return VocalSegments([
        for (final item in list)
          if (item is Map<String, dynamic>) VocalSegment.fromJson(item),
      ]);
    } catch (_) {
      return null;
    }
  }
}

/// 보컬 존재도(25fps, 원곡dB−MRdB)에서 노래 구간을 뽑는다.
/// (순수 함수 — 테스트 대상)
///
/// 규칙은 실측으로 검증한 그대로: [gapMs] 이상 조용하면 구간을 끊고,
/// [minSegmentMs] 미만 조각은 버린다(한 프레임 튄 소리가 구간이 되지 않게).
/// 문턱은 가사 자동 맞춤과 같은 vocalThreshold를 쓴다 — 규약이 두 개면
/// 언젠가 서로 어긋난다.
List<VocalSegment> detectVocalSegments(
  List<double> presence, {
  int fps = 25,
  int gapMs = 1500,
  int minSegmentMs = 1000,
}) {
  if (presence.isEmpty) return const [];
  final threshold = vocalThreshold(presence);
  final gap = gapMs * fps ~/ 1000;

  final segments = <VocalSegment>[];
  int? start;
  var lastActive = 0;
  var quiet = 0;
  for (var i = 0; i < presence.length; i++) {
    if (presence[i] >= threshold) {
      start ??= i;
      lastActive = i;
      quiet = 0;
    } else if (start != null) {
      quiet += 1;
      if (quiet >= gap) {
        segments.add(
          VocalSegment(
            startMs: start * 1000 ~/ fps,
            endMs: lastActive * 1000 ~/ fps,
          ),
        );
        start = null;
        quiet = 0;
      }
    }
  }
  if (start != null) {
    segments.add(
      VocalSegment(
        startMs: start * 1000 ~/ fps,
        endMs: lastActive * 1000 ~/ fps,
      ),
    );
  }
  return segments
      .where((s) => s.durationMs >= minSegmentMs)
      .toList(growable: false);
}
