import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/utils/lrc_builder.dart';

void main() {
  group('singableLines', () {
    test('빈 줄과 구조 태그를 걸러낸다', () {
      const lyrics = '[verse]\n별빛이 내리는 밤\n\n[chorus]\n노래를 불러요\n';
      expect(singableLines(lyrics), ['별빛이 내리는 밤', '노래를 불러요']);
    });

    test('구조 태그 판정', () {
      expect(isStructureTagLine('[verse]'), isTrue);
      expect(isStructureTagLine(' [chorus] '), isTrue);
      expect(isStructureTagLine('[00:12.34]가사'), isFalse);
      expect(isStructureTagLine('일반 가사'), isFalse);
    });
  });

  group('buildEvenlySpacedLrc', () {
    test('줄을 시간축에 고르게 깐다', () {
      final lrc = buildEvenlySpacedLrc(
        '[verse]\n하나\n둘\n셋',
        durationSec: 180,
      );
      expect(lrc, isNotNull);
      final lines = lrc!.trim().split('\n');
      expect(lines, hasLength(3));
      // 첫 줄은 전주(8% = 14.4초) 지점부터.
      expect(lines.first, startsWith('[00:14.'));
      expect(lines.first, endsWith('하나'));
      // 마지막 줄은 96% 지점(172.8초 = 2:52.8) 부근.
      expect(lines.last, startsWith('[02:52.'));
      // 시간이 단조 증가한다.
      expect(lines[1].compareTo(lines[0]), greaterThan(0));
    });

    test('가사가 없거나 곡이 너무 짧으면 null', () {
      expect(buildEvenlySpacedLrc('[verse]\n', durationSec: 180), isNull);
      expect(buildEvenlySpacedLrc('가사', durationSec: 10), isNull);
    });

    test('전주 상한 15초 — 긴 곡도 첫 줄이 늦지 않는다', () {
      final lrc = buildEvenlySpacedLrc('하나\n둘', durationSec: 600);
      expect(lrc!.split('\n').first, startsWith('[00:15.'));
    });
  });
}
