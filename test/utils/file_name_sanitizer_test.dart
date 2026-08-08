import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/utils/file_name_sanitizer.dart';

void main() {
  group('sanitizeFileName', () {
    test('Windows 금지문자를 공백으로 바꾼다', () {
      expect(sanitizeFileName('a<b>c:d"e/f\\g|h?i*j'), 'a b c d e f g h i j');
    });

    test('연속 공백을 하나로 줄이고 끝의 점·공백을 지운다', () {
      expect(sanitizeFileName('  봄날   Live.. '), '봄날 Live');
    });

    test('전부 지워지면 대체 이름을 쓴다', () {
      expect(sanitizeFileName('???'), 'file');
      expect(sanitizeFileName('***', fallback: '녹음'), '녹음');
    });

    test('한글·일반 문자는 그대로 둔다', () {
      expect(sanitizeFileName('거리에서_20260808_1030'), '거리에서_20260808_1030');
    });
  });
}
