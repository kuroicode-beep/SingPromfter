// file: test/utils/lrc_edit_test.dart
//
// STT 세그먼트 → LRC 생성과 LRC 한 줄 텍스트 교체.
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/utils/lrc_edit.dart';

void main() {
  group('shiftLrcFromLine — 현재 줄부터 아래만 밀기(Alt+←/→)', () {
    const raw = '[ti:테스트]\n'
        '[00:10.00]첫 줄\n'
        '[00:14.00]둘째 줄\n'
        '[00:19.00]셋째 줄';

    test('기준 줄부터만 옮기고 위 줄·메타 태그는 그대로', () {
      final next = shiftLrcFromLine(raw, displayIndex: 1, deltaMs: 200);
      expect(next?.appliedDeltaMs, 200);
      expect(next?.lrc, contains('[ti:테스트]'));
      expect(next?.lrc, contains('[00:10.00]첫 줄'));
      expect(next?.lrc, contains('[00:14.20]둘째 줄'));
      expect(next?.lrc, contains('[00:19.20]셋째 줄'));
    });

    test('앞당김(음수)도 되고 0 밑으로는 내려가지 않는다', () {
      final next = shiftLrcFromLine(raw, displayIndex: 0, deltaMs: -11000);
      expect(next?.lrc, contains('[00:00.00]첫 줄'));
      expect(next?.lrc, contains('[00:03.00]둘째 줄'));
    });

    test('앞당김이 바로 위 줄을 넘지 못한다 — 순서 보존 클램프', () {
      // 둘째 줄(14초)을 4.5초 당기면 첫 줄(10초)을 추월한다 —
      // 추월하면 파서가 재정렬해 줄 순서가 뒤섞인다("가사가 춤을 춤").
      // 위 줄 직전(10.01초)까지만 당겨진다.
      final next = shiftLrcFromLine(raw, displayIndex: 1, deltaMs: -4500);
      expect(next?.appliedDeltaMs, -3990);
      expect(next?.lrc, contains('[00:10.00]첫 줄'));
      expect(next?.lrc, contains('[00:10.01]둘째 줄'));
      expect(next?.lrc, contains('[00:15.01]셋째 줄'));
    });

    test('위 줄과 이미 붙어 있으면 적용 0으로 알려 준다', () {
      const dense = '[00:10.00]첫 줄\n[00:10.00]둘째 줄';
      final next = shiftLrcFromLine(dense, displayIndex: 1, deltaMs: -200);
      expect(next?.appliedDeltaMs, 0);
    });

    test('후렴 반복(한 줄 다중 태그)은 시각 기준으로 각각 판정한다', () {
      const chorus = '[00:10.00][00:30.00]후렴\n[00:20.00]중간 줄';
      // 표시 시각순: 10(후렴)·20(중간)·30(후렴) — 20부터 밀면
      // 같은 원문 줄이라도 10초 태그는 남고 30초 태그만 움직인다.
      final next = shiftLrcFromLine(chorus, displayIndex: 1, deltaMs: 500);
      expect(next?.lrc, contains('[00:10.00][00:30.50]후렴'));
      expect(next?.lrc, contains('[00:20.50]중간 줄'));
    });

    test('없는 줄이면 null', () {
      expect(shiftLrcFromLine(raw, displayIndex: 9, deltaMs: 200), isNull);
      expect(shiftLrcFromLine(raw, displayIndex: -1, deltaMs: 200), isNull);
    });
  });

  group('lrcFromSttSegments', () {
    test('타임스탬프 형식과 메타 태그', () {
      final lrc = lrcFromSttSegments(
        const [
          SttSegment(startSeconds: 13.6, endSeconds: 20, text: '첫 소절'),
          SttSegment(startSeconds: 75.25, endSeconds: 80, text: '둘째 소절'),
        ],
        title: '선물',
        artist: '윤후',
      );
      expect(lrc, contains('[ti:선물]'));
      expect(lrc, contains('[ar:윤후]'));
      expect(lrc, contains('[00:13.60]첫 소절'));
      expect(lrc, contains('[01:15.25]둘째 소절'));
    });

    test('곡 길이 밖 세그먼트는 버린다 — 페이드아웃 환청 가드', () {
      final lrc = lrcFromSttSegments(
        const [
          SttSegment(startSeconds: 10, endSeconds: 15, text: '진짜 가사'),
          SttSegment(startSeconds: 261, endSeconds: 263, text: '지어낸 가사'),
        ],
        duration: const Duration(milliseconds: 256392),
      );
      expect(lrc, contains('진짜 가사'));
      expect(lrc, isNot(contains('지어낸 가사')));
    });

    test('빈 텍스트·음수 시각은 버린다', () {
      final lrc = lrcFromSttSegments(const [
        SttSegment(startSeconds: -1, endSeconds: 0, text: '이상한 줄'),
        SttSegment(startSeconds: 5, endSeconds: 6, text: '  '),
        SttSegment(startSeconds: 10, endSeconds: 12, text: '정상'),
      ]);
      expect(lrc.trim().split('\n'), hasLength(1));
      expect(lrc, contains('[00:10.00]정상'));
    });
  });

  group('replaceLrcLineText', () {
    const raw = '[ti:테스트]\n'
        '[00:10.00]첫 줄\n'
        '[00:20.50]둘째 줄\n'
        '[00:30.00]셋째 줄';

    test('타임스탬프는 그대로 두고 텍스트만 바꾼다', () {
      final next = replaceLrcLineText(raw, displayIndex: 1, newText: '고친 줄');
      expect(next, contains('[00:20.50]고친 줄'));
      expect(next, isNot(contains('둘째 줄')));
      expect(next, contains('[ti:테스트]'));
      expect(next, contains('[00:10.00]첫 줄'));
    });

    test('표시 인덱스는 파일 순서가 아니라 시각순이다', () {
      // 파일에는 뒤 시각이 먼저 적혀 있다 — 파서는 시각순으로 보여 준다.
      const shuffled = '[00:30.00]나중 줄\n[00:10.00]먼저 줄';
      final next = replaceLrcLineText(
        shuffled,
        displayIndex: 0,
        newText: '고친 먼저 줄',
      );
      expect(next, contains('[00:10.00]고친 먼저 줄'));
      expect(next, contains('[00:30.00]나중 줄'));
    });

    test('한 줄에 태그가 여럿이면 태그 묶음을 보존한다', () {
      const multi = '[00:10.00][01:10.00]반복 소절';
      final next = replaceLrcLineText(
        multi,
        displayIndex: 0,
        newText: '고친 소절',
      );
      expect(next, '[00:10.00][01:10.00]고친 소절');
    });

    test('범위 밖 인덱스는 null', () {
      expect(replaceLrcLineText(raw, displayIndex: 9, newText: 'x'), isNull);
      expect(replaceLrcLineText(raw, displayIndex: -1, newText: 'x'), isNull);
    });
  });
}
