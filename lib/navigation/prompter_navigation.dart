// file: lib/navigation/prompter_navigation.dart
//
// 전체화면 프롬프터 라우팅 구성을 담당한다.
import 'package:flutter/material.dart';

import '../models/prompter_settings.dart';
import '../models/song.dart';
import '../screens/prompter_screen.dart';

class PrompterNavigation {
  PrompterNavigation._();

  static Future<void> open({
    required BuildContext context,
    required Song song,
    required PrompterSettings settings,
    required double fontSize,
    required double lineHeight,
    required String? fontFamily,
    required bool autoScrollEnabled,
    required ValueChanged<PrompterSettings> onSettingsChanged,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrompterScreen(
          song: song,
          fontSize: fontSize,
          lineHeight: lineHeight,
          fontSizeLevel: settings.fontSizeLevel,
          lineHeightLevel: settings.lineHeightLevel,
          customFontSizePt: settings.customFontSizePt,
          speedLevel: settings.speedLevel,
          fontFamily: fontFamily,
          boldText: settings.boldText,
          autoScrollEnabled: autoScrollEnabled,
          onFontSizeLevelChanged: (value) => onSettingsChanged(
            settings.copyWith(fontSizeLevel: value, clearCustomFontSize: true),
          ),
          onLineHeightLevelChanged: (value) =>
              onSettingsChanged(settings.copyWith(lineHeightLevel: value)),
          onSpeedLevelChanged: (value) =>
              onSettingsChanged(settings.copyWith(speedLevel: value)),
        ),
      ),
    );
  }
}
