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

/// Whisper 신뢰도 문턱 — **가창 기준으로 느슨하게**.
///
/// v3.19.0의 빡빡한 문턱은 노래에서 거꾸로 작동했다(실측:
/// 「너를 사랑하고도」 가사 전멸): Whisper는 실제 가창에 자신 없어하고
/// (낮은 logprob), "1부에서 계속 됩니다" 같은 방송 상용구 환청에는
/// 오히려 자신만만하다. 신뢰도는 극단값만 자르고, 상용구는 블랙리스트로
/// 직접 잡는다.
const double refineNoSpeechHard = 0.9;
const double refineNoSpeechProb = 0.6;
const double refineLowLogprob = -1.2;

/// Whisper가 한국어 음악·무성 구간에서 지어내는 방송 상용구들 —
/// 학습 데이터(방송 자막) 잔재라 모델 확신도가 높아 신뢰도 필터를
/// 통과한다. 정규식으로 직접 잡는 수밖에 없다.
final List<RegExp> refineHallucinationPhrases = [
  RegExp(r'^\d+부에서\s*계속'),
  RegExp(r'구독\s*(과)?\s*좋아요|좋아요\s*(와)?\s*구독'),
  RegExp(r'구독\s*(눌러|부탁|해)'),
  RegExp(r'시청해\s*주셔서|시청\s*감사'),
  RegExp(r'알림\s*설정'),
  RegExp(r'다음\s*(영상|편|시간)에\s*(만나|계속|뵙)'),
  RegExp(r'^자막\s*(제공|제작)'),
  RegExp(r'^\(?\s*(박수|웃음|음악)\s*\)?$'),
];

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

    // ① 방송 상용구 — Whisper 한국어 환청의 단골. 확신도가 높아
    // 신뢰도로는 못 잡는다.
    if (refineHallucinationPhrases.any((p) => p.hasMatch(text))) {
      drop(seg, '방송 상용구 환청');
      continue;
    }

    // ② 모델 신뢰도 — 가창은 원래 확신도가 낮으니 극단값만 자른다.
    final noSpeech = seg.noSpeechProb;
    final logprob = seg.avgLogprob;
    if (noSpeech != null && noSpeech > refineNoSpeechHard) {
      drop(seg, '무음 확률 매우 높음 (${noSpeech.toStringAsFixed(2)})');
      continue;
    }
    if (noSpeech != null &&
        logprob != null &&
        noSpeech > refineNoSpeechProb &&
        logprob < refineLowLogprob) {
      drop(seg, '무음 확률 높음 + 확신도 낮음');
      continue;
    }

    // ③ 보컬 에너지 — 노래가 없는 구간에 붙은 줄은 반주 환청이다.
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
