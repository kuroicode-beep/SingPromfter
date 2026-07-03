import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/theme/prompter_levels.dart';

void main() {
  group('PrompterLevels', () {
    test('fontSizeForLevel clamps and maps levels', () {
      expect(PrompterLevels.fontSizeForLevel(1), 18);
      expect(PrompterLevels.fontSizeForLevel(7), 72);
      expect(PrompterLevels.fontSizeForLevel(99), 72);
    });

    test('lineHeightForLevel clamps and maps levels', () {
      expect(PrompterLevels.lineHeightForLevel(1), 1.35);
      expect(PrompterLevels.lineHeightForLevel(7), 2.75);
      expect(PrompterLevels.lineHeightForLevel(-1), 1.35);
    });

    test('level inverse helpers choose nearest upper step', () {
      expect(PrompterLevels.levelForFontSize(18), 1);
      expect(PrompterLevels.levelForFontSize(50), 6);
      expect(PrompterLevels.levelForLineHeight(1.7), 3);
      expect(PrompterLevels.levelForLineHeight(9), 7);
    });

    test('scrollDeltaForSpeed scales speed level', () {
      expect(PrompterLevels.scrollDeltaForSpeed(2), 2.8);
    });
  });
}
