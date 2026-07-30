// file: test/utils/lrc_edit_test.dart
//
// STT 세그먼트 → LRC 생성과 LRC 한 줄 텍스트 교체.
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/utils/lrc_edit.dart';

void main() {
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
