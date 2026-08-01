// file: test/utils/lyrics_refine_test.dart
//
// 받아쓰기 정밀 필터 — 환청 제거·온셋 스냅·정답 가사 대조.
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/utils/lrc_edit.dart';
import 'package:singpromfter_app/utils/lyrics_refine.dart';

SttSegment seg(
  double start,
  double end,
  String text, {
  double? noSpeech,
  double? logprob,
  double? firstWord,
}) => SttSegment(
  startSeconds: start,
  endSeconds: end,
  text: text,
  noSpeechProb: noSpeech,
  avgLogprob: logprob,
  firstWordStartSeconds: firstWord,
);

void main() {
  group('refineSttSegments', () {
    test('확신도 매우 낮은 줄은 단독으로 버린다', () {
      final r = refineSttSegments([
        seg(10, 14, '진짜 가사', logprob: -0.3),
        seg(200, 203, '웅얼거림 환청', logprob: -1.8),
      ]);
      expect(r.kept.map((s) => s.text), ['진짜 가사']);
      expect(r.dropped.single.reason, contains('확신도'));
    });

    test('무음 확률 높음 + 확신도 낮음 조합으로 버린다', () {
      final r = refineSttSegments([
        seg(10, 14, '가사', noSpeech: 0.1, logprob: -0.3),
        seg(240, 243, '페이드아웃 환청', noSpeech: 0.8, logprob: -1.0),
      ]);
      expect(r.kept.map((s) => s.text), ['가사']);
      expect(r.dropped.single.reason, contains('무음'));
    });

    test('보컬 없는 구간의 줄은 버리고, 전주 환청 시작은 온셋으로 스냅', () {
      final vocals = [(startMs: 30000, endMs: 60000)];
      final r = refineSttSegments([
        // 0:00 환청이지만 세그먼트 끝이 보컬 구간에 닿음 → 시작을 30초로 스냅
        seg(0, 35, '너를 사랑하고도'),
        // 보컬 구간과 전혀 안 겹침 → 삭제
        seg(70, 75, '간주 환청'),
        seg(31, 38, '늘 외로운 나는'),
      ], vocalSegments: vocals);
      expect(r.kept.length, 2);
      expect(r.kept.first.lineStartSeconds, 30.0);
      expect(r.dropped.single.reason, '보컬 없는 구간');
    });

    test('단어 타임스탬프가 있으면 줄 시작으로 쓴다', () {
      final r = refineSttSegments([seg(10, 14, '가사', firstWord: 10.62)]);
      expect(r.kept.single.lineStartSeconds, 10.62);
    });

    test('곡 길이 밖 줄은 버린다', () {
      final r = refineSttSegments(
        [seg(10, 14, '가사'), seg(261, 263, '지어낸 가사')],
        durationMs: 256000,
      );
      expect(r.kept.map((s) => s.text), ['가사']);
      expect(r.dropped.single.reason, '곡 길이 밖');
    });

    test('신뢰도 정보가 없으면 신뢰도 근거는 건너뛴다(옛 서버 호환)', () {
      final r = refineSttSegments([seg(10, 14, '가사')]);
      expect(r.kept, hasLength(1));
    });
  });

  group('applyReferenceLyrics', () {
    test('타이밍은 STT, 텍스트는 정답 — 매칭 없는 줄은 버린다', () {
      final kept = [
        seg(10, 14, '몸 한 몸 들어'),
        seg(20, 24, '중복 환청'),
        seg(30, 34, '서로 다른 사랑을'),
      ];
      final r = applyReferenceLyrics(kept, {
        0: '못 한 몫 되어',
        2: '서로 다른 사랑은',
      });
      expect(r.kept.map((s) => s.text), ['못 한 몫 되어', '서로 다른 사랑은']);
      expect(r.kept.first.lineStartSeconds, 10);
      expect(r.dropped.single.reason, '정답 가사에 없음');
    });
  });
}
