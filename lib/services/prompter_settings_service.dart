// file: lib/services/prompter_settings_service.dart
//
// 프롬프터 표시 설정의 프리셋과 폰트 해석 규칙을 제공한다.
import '../models/prompter_settings.dart';

class PrompterSettingsService {
  PrompterSettingsService._();

  static const Map<String, String?> fontOptions = {
    'System Default': null,
    'Malgun Gothic': 'MalgunGothic',
    'Segoe UI': 'SegoeUI',
    '교보손글씨2019': 'KyoboHandwriting2019',
    'Monospace': 'monospace',
  };

  static String? resolvedFontFamily(PrompterSettings settings) {
    if (fontOptions.containsKey(settings.fontFamily)) {
      return fontOptions[settings.fontFamily];
    }
    if (settings.fontFamily == '기본' ||
        settings.fontFamily == 'System Default') {
      return null;
    }
    return settings.fontFamily;
  }

  static PrompterSettings preset(PrompterSettings settings, String preset) {
    switch (preset) {
      case 'recommended':
        return settings.copyWith(
          fontSizeLevel: 5,
          lineHeightLevel: 5,
          speedLevel: 3,
          fontFamily: 'Malgun Gothic',
          boldText: true,
          clearCustomFontSize: true,
        );
      case 'stage':
        return settings.copyWith(
          fontSizeLevel: 7,
          lineHeightLevel: 6,
          speedLevel: 2,
          fontFamily: 'Malgun Gothic',
          boldText: true,
          clearCustomFontSize: true,
        );
      default:
        return settings.copyWith(
          fontSizeLevel: 3,
          lineHeightLevel: 3,
          speedLevel: 2,
          fontFamily: 'System Default',
          boldText: false,
          clearCustomFontSize: true,
        );
    }
  }
}
