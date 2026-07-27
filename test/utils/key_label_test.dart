import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/utils/key_label.dart';

void main() {
  group('formatKeyLabel', () {
    test('0은 원키', () {
      expect(formatKeyLabel(0), '원키');
    });

    test('양수는 높임', () {
      expect(formatKeyLabel(1), '1키 높임');
      expect(formatKeyLabel(2), '2키 높임');
      expect(formatKeyLabel(6), '6키 높임');
    });

    test('음수는 낮춤 (부호 없이 표기)', () {
      expect(formatKeyLabel(-1), '1키 낮춤');
      expect(formatKeyLabel(-2), '2키 낮춤');
      expect(formatKeyLabel(-6), '6키 낮춤');
    });
  });

  group('formatKeyShort', () {
    test('0은 원키, 나머지는 부호 표기', () {
      expect(formatKeyShort(0), '원키');
      expect(formatKeyShort(3), '+3');
      expect(formatKeyShort(-3), '-3');
    });
  });
}
