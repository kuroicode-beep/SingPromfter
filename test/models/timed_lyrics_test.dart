import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/timed_lyrics.dart';

void main() {
  group('LrcParser', () {
    test('기본 [mm:ss.xx] 형식을 읽는다', () {
      final lrc = LrcParser.parse('''
[00:12.50]첫 번째 줄
[00:17.20]두 번째 줄
[01:05.00]세 번째 줄
''');
      expect(lrc.lines, hasLength(3));
      expect(lrc.lines.first.time, const Duration(seconds: 12, milliseconds: 500));
      expect(lrc.lines.first.text, '첫 번째 줄');
      expect(lrc.lines.last.time, const Duration(minutes: 1, seconds: 5));
    });

    test('밀리초 3자리도 읽는다', () {
      final lrc = LrcParser.parse('[00:12.345]줄');
      expect(lrc.lines.first.time, const Duration(seconds: 12, milliseconds: 345));
    });

    test('소수점 없는 [mm:ss]도 읽는다', () {
      final lrc = LrcParser.parse('[01:30]줄');
      expect(lrc.lines.first.time, const Duration(minutes: 1, seconds: 30));
    });

    test('콜론 구분자 [mm:ss:xx]도 읽는다', () {
      final lrc = LrcParser.parse('[00:12:50]줄');
      expect(lrc.lines.first.time, const Duration(seconds: 12, milliseconds: 500));
    });

    test('한 줄에 여러 타임스탬프가 있으면 각각 만든다 (후렴 반복)', () {
      final lrc = LrcParser.parse('[00:10.00][01:20.00][02:30.00]후렴');
      expect(lrc.lines, hasLength(3));
      expect(lrc.lines.every((l) => l.text == '후렴'), isTrue);
      expect(lrc.lines[1].time, const Duration(minutes: 1, seconds: 20));
    });

    test('메타 태그를 읽고 가사에서 제외한다', () {
      final lrc = LrcParser.parse('''
[ti:봄날]
[ar:테스트]
[offset:-500]
[00:10.00]가사
''');
      expect(lrc.title, '봄날');
      expect(lrc.artist, '테스트');
      expect(lrc.offsetMs, -500);
      expect(lrc.lines, hasLength(1));
    });

    test('시간 순으로 정렬한다', () {
      final lrc = LrcParser.parse('''
[00:30.00]나중
[00:10.00]먼저
''');
      expect(lrc.lines.first.text, '먼저');
      expect(lrc.lines.last.text, '나중');
    });

    test('타임스탬프 없는 줄·빈 본문은 건너뛴다', () {
      final lrc = LrcParser.parse('''
그냥 텍스트
[00:10.00]
[00:20.00]유효한 줄
''');
      expect(lrc.lines, hasLength(1));
      expect(lrc.lines.first.text, '유효한 줄');
    });

    test('빈 입력은 빈 결과', () {
      expect(LrcParser.parse('').isEmpty, isTrue);
      expect(LrcParser.parse('   \n  ').isEmpty, isTrue);
    });

    test('BOM과 CRLF가 있어도 읽는다', () {
      final lrc = LrcParser.parse('﻿[00:05.00]줄1\r\n[00:10.00]줄2\r\n');
      expect(lrc.lines, hasLength(2));
      expect(lrc.lines.first.text, '줄1');
    });
  });

  group('TimedLyrics.indexAt (이진 탐색)', () {
    final lrc = LrcParser.parse('''
[00:10.00]A
[00:20.00]B
[00:30.00]C
''');

    test('첫 줄 이전에는 0', () {
      expect(lrc.indexAt(Duration.zero), 0);
      expect(lrc.indexAt(const Duration(seconds: 5)), 0);
    });

    test('경계 시각에는 해당 줄로 넘어간다', () {
      expect(lrc.indexAt(const Duration(seconds: 10)), 0);
      expect(lrc.indexAt(const Duration(seconds: 19, milliseconds: 999)), 0);
      expect(lrc.indexAt(const Duration(seconds: 20)), 1);
    });

    test('마지막 줄 이후에는 마지막 인덱스를 유지한다', () {
      expect(lrc.indexAt(const Duration(minutes: 10)), 2);
    });

    test('offset이 있으면 반영한다 (음수 = 가사를 먼저 띄움)', () {
      final shifted = TimedLyrics(lines: lrc.lines, offsetMs: -2000);
      // 8초 시점에 이미 (10초 줄 - 2초) 조건을 만족한다
      expect(shifted.indexAt(const Duration(seconds: 8)), 0);
      expect(shifted.indexAt(const Duration(seconds: 18)), 1);
    });

    test('빈 가사는 0', () {
      expect(const TimedLyrics(lines: []).indexAt(const Duration(seconds: 5)), 0);
    });

    test('구간 전체에서 인덱스가 줄지 않는다 (단조 증가)', () {
      var previous = 0;
      for (var s = 0; s <= 40; s++) {
        final current = lrc.indexAt(Duration(seconds: s));
        expect(current, greaterThanOrEqualTo(previous));
        previous = current;
      }
    });
  });
}
