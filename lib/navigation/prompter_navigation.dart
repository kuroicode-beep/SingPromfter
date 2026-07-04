// file: lib/navigation/prompter_navigation.dart
//
// 전체화면 프롬pter 라우팅 구성을 담당한다.
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
    required bool audioReady,
    required Duration position,
    required Duration duration,
    required ValueChanged<PrompterSettings> onSettingsChanged,
    ValueChanged<Duration>? onSeek,
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
          volume: settings.volume,
          fontFamily: fontFamily,
          boldText: settings.boldText,
          autoScrollEnabled: autoScrollEnabled,
          displayMode: settings.displayMode,
          audioReady: audioReady,
          position: position,
          duration: duration,
          onSeek: onSeek,
          onDisplayModeChanged: (mode) =>
              onSettingsChanged(settings.copyWith(displayMode: mode)),
          onFontSizeLevelChanged: (value) => onSettingsChanged(
            settings.copyWith(fontSizeLevel: value, clearCustomFontSize: true),
          ),
          onLineHeightLevelChanged: (value) =>
              onSettingsChanged(settings.copyWith(lineHeightLevel: value)),
          onSpeedLevelChanged: (value) =>
              onSettingsChanged(settings.copyWith(speedLevel: value)),
          onVolumeChanged: (value) =>
              onSettingsChanged(settings.copyWith(volume: value)),
        ),
      ),
    );
  }
}
