// file: lib/navigation/prompter_navigation.dart
//
// 전체화면 프롬프터 라우팅 구성을 담당한다.
//
// 이전에는 position/duration을 값으로 한 번만 넘겨 라우트가 부모 setState로
// 리빌드되지 않았고, 그 결과 전체화면의 재생 위치가 멈춰 있었다.
// 이제 컨트롤러를 넘겨 전체화면이 직접 구독한다.
import 'package:flutter/material.dart';

import '../controllers/playback_controller.dart';
import '../models/prompter_settings.dart';
import '../models/song.dart';
import '../screens/prompter_screen.dart';

class PrompterNavigation {
  PrompterNavigation._();

  static Future<void> open({
    required BuildContext context,
    required Song song,
    required PrompterSettings settings,
    required PlaybackController playback,
    required double fontSize,
    required double lineHeight,
    required String? fontFamily,
    required ValueChanged<PrompterSettings> onSettingsChanged,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrompterScreen(
          song: song,
          playback: playback,
          fontSize: fontSize,
          lineHeight: lineHeight,
          fontSizeLevel: settings.fontSizeLevel,
          lineHeightLevel: settings.lineHeightLevel,
          customFontSizePt: settings.customFontSizePt,
          speedLevel: settings.speedLevel,
          volume: settings.volume,
          fontFamily: fontFamily,
          boldText: settings.boldText,
          displayMode: settings.displayMode,
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
