// file: lib/services/song_list_shortcut_service.dart
//
// 메인 화면의 키보드 단축키를 해석한다.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/prompter_settings.dart';
import '../models/song.dart';

class SongListShortcutService {
  SongListShortcutService._();

  static const double volumeStep = 0.1;
  static const double speedStep = 0.5;

  static bool isTextInputFocused() {
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus == null) return false;
    return primaryFocus.context?.widget is EditableText;
  }

  static bool handle({
    required KeyEvent event,
    required Song? selectedSong,
    required PrompterSettings settings,
    required VoidCallback onTogglePlayPause,
    required ValueChanged<Song> onOpenPrompter,
    required ValueChanged<PrompterSettings> onSettingsChanged,
  }) {
    if (event is! KeyDownEvent) return false;
    if (isTextInputFocused()) {
      return false;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      onTogglePlayPause();
      return true;
    }
    if (key == LogicalKeyboardKey.f5) {
      final song = selectedSong;
      if (song != null) onOpenPrompter(song);
      return true;
    }

    final adjusted = adjustSettings(settings, key);
    if (adjusted != null) {
      onSettingsChanged(adjusted);
      return true;
    }
    return false;
  }

  static PrompterSettings? adjustSettings(
    PrompterSettings settings,
    LogicalKeyboardKey key,
  ) {
    if (key == LogicalKeyboardKey.arrowUp) {
      return settings.copyWith(
        volume: (settings.volume + volumeStep).clamp(0.0, 1.0),
      );
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      return settings.copyWith(
        volume: (settings.volume - volumeStep).clamp(0.0, 1.0),
      );
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      return settings.copyWith(
        speedLevel: (settings.speedLevel + speedStep).clamp(0.0, 10.0),
      );
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      return settings.copyWith(
        speedLevel: (settings.speedLevel - speedStep).clamp(0.0, 10.0),
      );
    }
    return null;
  }
}
