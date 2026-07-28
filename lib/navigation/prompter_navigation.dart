// file: lib/navigation/prompter_navigation.dart
//
// 전체화면 프롬프터 라우팅 구성을 담당한다.
//
// 이전에는 position/duration을 값으로 한 번만 넘겨 라우트가 부모 setState로
// 리빌드되지 않았고, 그 결과 전체화면의 재생 위치가 멈춰 있었다.
// 이제 컨트롤러를 넘겨 전체화면이 직접 구독한다.
//
// 설정도 값이 아니라 provider로 받는다. 값으로 캡처하면 라우트를 연 시점의
// 스냅샷 위에 copyWith가 얹혀, 글자 크기를 바꾼 뒤 속도를 바꾸면 크기가
// 조용히 되돌아갔다. Ctrl+휠은 이 경로를 연달아 타므로 특히 치명적이다.
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
    required PrompterSettings Function() settingsProvider,
    required PlaybackController playback,
    required double fontSize,
    required double lineHeight,
    required String? fontFamily,
    required ValueChanged<PrompterSettings> onSettingsChanged,
  }) {
    final initial = settingsProvider();

    /// 콜백이 실제로 불리는 시점의 최신 설정 위에 변경을 얹는다.
    void update(PrompterSettings Function(PrompterSettings current) change) {
      onSettingsChanged(change(settingsProvider()));
    }

    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrompterScreen(
          song: song,
          playback: playback,
          fontSize: fontSize,
          lineHeight: lineHeight,
          fontSizeLevel: initial.fontSizeLevel,
          lineHeightLevel: initial.lineHeightLevel,
          customFontSizePt: initial.customFontSizePt,
          speedLevel: initial.speedLevel,
          volume: initial.volume,
          fontFamily: fontFamily,
          boldText: initial.boldText,
          displayMode: initial.displayMode,
          showEqMeter: initial.showEqMeter,
          onDisplayModeChanged: (mode) =>
              update((s) => s.copyWith(displayMode: mode)),
          onFontSizeLevelChanged: (value) => update(
            (s) => s.copyWith(fontSizeLevel: value, clearCustomFontSize: true),
          ),
          onLineHeightLevelChanged: (value) =>
              update((s) => s.copyWith(lineHeightLevel: value)),
          onSpeedLevelChanged: (value) =>
              update((s) => s.copyWith(speedLevel: value)),
          onVolumeChanged: (value) => update((s) => s.copyWith(volume: value)),
        ),
      ),
    );
  }
}
