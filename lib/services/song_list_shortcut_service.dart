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

  /// ←/→ 로 건너뛰는 폭. Shift를 누르면 [seekStepLarge].
  ///
  /// v2.8.0에서 이 키가 가사 속도 조절이었다가 이동으로 바뀌었다. 속도는 이제
  /// 음악 템포 하나뿐이고, 템포는 조작판의 -/+ 와 Shift+휠이 맡는다.
  /// adjustSettings는 순수 함수라 디바운스가 필요한 템포 렌더를 부를 수 없다 —
  /// 케이스를 비틀지 말고 빼는 쪽이 맞다.
  static const Duration seekStep = Duration(seconds: 5);
  static const Duration seekStepLarge = Duration(seconds: 30);

  static bool isTextInputFocused() {
    final primaryFocus = FocusManager.instance.primaryFocus;
    final context = primaryFocus?.context;
    if (context == null) return false;
    // 예전에는 포커스 노드의 context가 EditableText 자신이었지만, 지금
    // Flutter는 EditableText **내부의 Focus 위젯**에 노드를 붙인다 —
    // 자신만 보면 항상 false가 나와 "입력 중 단축키 차단"이 통째로 꺼진다
    // (검색창에 타이핑하다 R 녹음이 시작되는 사고). 조상까지 확인한다.
    if (context.widget is EditableText) return true;
    return context.findAncestorStateOfType<EditableTextState>() != null;
  }

  static bool handle({
    required KeyEvent event,
    required Song? selectedSong,
    required PrompterSettings settings,
    required VoidCallback onTogglePlayPause,
    required ValueChanged<Song> onOpenPrompter,
    required ValueChanged<PrompterSettings> onSettingsChanged,
    ValueChanged<Duration>? onSeekRelative,
  }) {
    if (event is! KeyDownEvent) return false;
    if (isTextInputFocused()) {
      return false;
    }

    final key = event.logicalKey;
    final seek = seekDeltaFor(key, shift: HardwareKeyboard.instance.isShiftPressed);
    if (seek != null) {
      if (onSeekRelative != null) onSeekRelative(seek);
      return true;
    }
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
    return null;
  }

  /// ←/→ 로 건너뛸 시간. 다른 키면 null.
  static Duration? seekDeltaFor(LogicalKeyboardKey key, {bool shift = false}) {
    final step = shift ? seekStepLarge : seekStep;
    if (key == LogicalKeyboardKey.arrowRight) return step;
    if (key == LogicalKeyboardKey.arrowLeft) return -step;
    return null;
  }
}
