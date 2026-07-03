// file: lib/theme/prompter_levels.dart
//
// 프롬프터의 단계형 설정을 실제 표시 값으로 변환하는 공통 모듈이다.
import '../constants/app_constants.dart';

class PrompterLevels {
  PrompterLevels._();

  static const double minLevel = 1;
  static const double maxLevel = 7;
  static const List<double> fontSizeSteps = [18, 22, 28, 36, 44, 56, 72];
  static const List<double> lineHeightSteps = [
    1.35,
    1.5,
    1.7,
    1.95,
    2.2,
    2.45,
    2.75,
  ];

  static double fontSizeForLevel(double level) {
    final index = level.round().clamp(1, fontSizeSteps.length) - 1;
    return fontSizeSteps[index];
  }

  static double lineHeightForLevel(double level) {
    final index = level.round().clamp(1, lineHeightSteps.length) - 1;
    return lineHeightSteps[index];
  }

  static double levelForFontSize(double pt) {
    for (var i = 0; i < fontSizeSteps.length; i++) {
      if (pt <= fontSizeSteps[i]) return (i + 1).toDouble();
    }
    return maxLevel;
  }

  static double levelForLineHeight(double value) {
    for (var i = 0; i < lineHeightSteps.length; i++) {
      if (value <= lineHeightSteps[i]) return (i + 1).toDouble();
    }
    return maxLevel;
  }

  static double scrollDeltaForSpeed(double speedLevel) =>
      speedLevel * AppConstants.scrollDeltaMultiplier;
}
