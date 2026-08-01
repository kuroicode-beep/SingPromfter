// file: lib/utils/lyrics_refine.dart
//
// 받아쓰기(STT) 세그먼트를 가사 줄로 다듬는 순수 규칙 — 환청 제거와
// 타이밍 정밀화. Whisper는 반주·페이드아웃에서 가사를 지어내는데
// (실측: 「너를 사랑하고도」 곡 끝 "march이 옆에도…"), 근거 두 가지로
// 걸러낸다: ① 모델 자신의 신뢰도 ② 보컬 에너지 구간과의 겹침.
import 'lrc_edit.dart';

/// 한 줄이 왜 버려졌는지 — 사용자에게 그대로 보여 줄 수 있는 사유.
typedef DroppedLine = ({String text, double startSeconds, String reason});

class RefineResult {
  final List<SttSegment> kept;
  final List<DroppedLine> dropped;

  const RefineResult({required this.kept, required this.dropped});
}

/// Whisper가 "말이 아니다"라고 자백하는 문턱.
/// no_speech_prob 단독으로는 노래에서 오탐이 많아(가창은 말과 다르다)
/// 확신도(avg_logprob)와 함께 본다.
const double refineNoSpeechProb = 0.5;
const double refineLowLogprob = -0.8;

/// 여기보다 낮은 확신도는 단독으로도 버린다 — 완전한 웅얼거림.
const double refineHardLogprob = -1.4;

/// 보컬 구간과 겹침을 판정할 때 구간을 양쪽으로 늘려 주는 여유(ms).
/// 구간 탐지가 프레임 단위라 경계가 수백 ms 어긋날 수 있다.
const int refineVocalPadMs = 400;

/// 세그먼트를 다듬는다. [vocalSegments]는 노래가 실제로 들리는 구간
/// (원곡−MR 비교 분석, 파일 원본 축 ms). 비어 있으면 에너지 근거는 쓰지
/// 않고 신뢰도 근거만 쓴다. [durationMs]를 알면 곡 길이 밖 줄을 버린다.
RefineResult refineSttSegments(
  List<SttSegment> segments, {
  List<({int startMs, int endMs})> vocalSegments = const [],
  int? durationMs,
}) {
  final kept = <SttSegment>[];
  final dropped = <DroppedLine>[];

  void drop(SttSegment seg, String reason) =>
      dropped.add((text: seg.text, startSeconds: seg.lineStartSeconds, reason: reason));

  for (final seg in segments) {
    final text = seg.text.trim();
    if (text.isEmpty) continue;

    final startMs = (seg.lineStartSeconds * 1000).round();
    final endMs = (seg.endSeconds * 1000).round();

    if (durationMs != null && startMs >= durationMs) {
      drop(seg, '곡 길이 밖');
      continue;
    }

    // ① 모델 신뢰도 — 무음일 확률이 높으면서 확신도도 낮으면 환청.
    final noSpeech = seg.noSpeechProb;
    final logprob = seg.avgLogprob;
    if (logprob != null && logprob < refineHardLogprob) {
      drop(seg, '확신도 매우 낮음 (${logprob.toStringAsFixed(2)})');
      continue;
    }
    if (noSpeech != null &&
        logprob != null &&
        noSpeech > refineNoSpeechProb &&
        logprob < refineLowLogprob) {
      drop(seg, '무음 확률 높음 + 확신도 낮음');
      continue;
    }

    // ② 보컬 에너지 — 노래가 없는 구간에 붙은 줄은 반주 환청이다.
    if (vocalSegments.isNotEmpty) {
      final overlapping = vocalSegments.where(
        (v) => startMs < v.endMs + refineVocalPadMs && endMs > v.startMs - refineVocalPadMs,
      );
      if (overlapping.isEmpty) {
        drop(seg, '보컬 없는 구간');
        continue;
      }
      // 줄 시작이 구간 앞의 무성 지대에 있으면 발성 시작(온셋)으로 끌어온다 —
      // "첫 줄이 0:00에 붙는" 전주 환청 타이밍의 교정.
      final firstOverlap = overlapping.first;
      if (startMs < firstOverlap.startMs - refineVocalPadMs) {
        kept.add(seg.copyWith(startSeconds: firstOverlap.startMs / 1000));
        continue;
      }
    }

    kept.add(seg);
  }
  return RefineResult(kept: kept, dropped: dropped);
}

/// 정답 가사 대조 결과를 적용한다 — 타이밍은 STT, 텍스트는 정답.
///
/// [matches]는 kept 인덱스 → 정답 줄 텍스트. 매칭이 없는 STT 줄은
/// 정답에 없는 가사(환청·중복)로 보고 버린다.
RefineResult applyReferenceLyrics(
  List<SttSegment> kept,
  Map<int, String> matches,
) {
  final out = <SttSegment>[];
  final dropped = <DroppedLine>[];
  for (var i = 0; i < kept.length; i++) {
    final seg = kept[i];
    final ref = matches[i]?.trim();
    if (ref == null || ref.isEmpty) {
      dropped.add((
        text: seg.text,
        startSeconds: seg.lineStartSeconds,
        reason: '정답 가사에 없음',
      ));
      continue;
    }
    out.add(seg.copyWith(text: ref));
  }
  return RefineResult(kept: out, dropped: dropped);
}
