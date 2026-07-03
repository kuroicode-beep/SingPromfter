// file: lib/services/song_list_shortcut_service.dart
//
// 메인 화면의 키보드 단축키를 해석한다.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/song.dart';

class SongListShortcutService {
  SongListShortcutService._();

  static bool handle({
    required KeyEvent event,
    required Song? selectedSong,
    required VoidCallback onTogglePlayPause,
    required ValueChanged<Song> onOpenPrompter,
  }) {
    if (event is! KeyDownEvent) return false;
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus?.context?.widget is EditableText) {
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
    return false;
  }
}
