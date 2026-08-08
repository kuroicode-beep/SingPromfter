// file: lib/utils/youtube_subtitle.dart
//
// 유튜브 자막(json3) → 가사 세그먼트. (순수 함수 — 테스트 대상)
//
// 업로더가 단 **수동 자막**은 타이밍까지 있는 사실상 완성 LRC다.
// 자동 생성 자막은 ASR이라 우리 Whisper와 같은 환청 문제가 있어
// 애초에 받지 않는다(서비스 쪽에서 --write-subs만 요청).
import 'dart:convert';

import 'lrc_edit.dart';

/// yt-dlp `--sub-format json3` 원문을 세그먼트로 바꾼다.
/// 형식이 아니거나 쓸 줄이 없으면 빈 목록.
List<SttSegment> segmentsFromJson3(String raw) {
  dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return const [];
  }
  if (decoded is! Map) return const [];
  final events = decoded['events'];
  if (events is! List) return const [];

  final out = <SttSegment>[];
  for (final event in events) {
    if (event is! Map) continue;
    final startMs = (event['tStartMs'] as num?)?.toInt();
    if (startMs == null) continue;
    final durMs = (event['dDurationMs'] as num?)?.toInt() ?? 0;
    final segs = event['segs'];
    if (segs is! List) continue;
    final text = segs
        .whereType<Map<String, dynamic>>()
        .map((s) => (s['utf8'] as String? ?? ''))
        .join()
        .replaceAll('\n', ' ')
        .trim();
    if (text.isEmpty) continue;
    // ♪ 같은 장식 전용 줄은 가사가 아니다.
    if (RegExp(r'^[♪♬♫\s\[\]().-]*$').hasMatch(text)) continue;
    out.add(
      SttSegment(
        startSeconds: startMs / 1000,
        endSeconds: (startMs + durMs) / 1000,
        text: text,
      ),
    );
  }
  // 같은 시각 중복(스타일 이벤트)을 정리하고 시각순으로.
  out.sort((a, b) => a.startSeconds.compareTo(b.startSeconds));
  final deduped = <SttSegment>[];
  for (final seg in out) {
    if (deduped.isNotEmpty &&
        deduped.last.text == seg.text &&
        (seg.startSeconds - deduped.last.startSeconds).abs() < 0.05) {
      continue;
    }
    deduped.add(seg);
  }
  return deduped;
}
