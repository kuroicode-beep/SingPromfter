// file: lib/services/prompter_auto_scroll_service.dart
//
// 가사 자동 스크롤 타이머를 관리한다. 하이라이트 모드는 줄 인덱스를 타이머로 이동한다.
import 'dart:async';

import 'package:flutter/widgets.dart';

import '../constants/app_constants.dart';
import '../models/prompter_display_mode.dart';
import '../models/song.dart';
import '../theme/prompter_levels.dart';
import '../utils/lyrics_line_utils.dart';

class PrompterAutoScrollService {
  final ScrollController controller;
  Timer? _timer;
  int _lineIndex = 0;
  VoidCallback? onLineIndexChanged;

  PrompterAutoScrollService(this.controller);

  int get lineIndex => _lineIndex;

  void dispose() => _timer?.cancel();

  void resetLineIndex() {
    _lineIndex = 0;
    onLineIndexChanged?.call();
  }

  void sync({
    required Song? selectedSong,
    required bool playing,
    required double speedLevel,
    PrompterDisplayMode displayMode = PrompterDisplayMode.full,
  }) {
    _timer?.cancel();
    final isLyricsOnly =
        selectedSong != null && selectedSong.availableTrackSlots.isEmpty;
    final shouldScroll = playing || isLyricsOnly;
    if (!shouldScroll || speedLevel <= 0) {
      return;
    }

    if (displayMode == PrompterDisplayMode.highlight) {
      final lineCount = selectedSong == null
          ? 0
          : LyricsLineUtils.splitLines(selectedSong.lyricsText).length;
      if (lineCount <= 1) return;

      _timer = Timer.periodic(AppConstants.autoScrollInterval, (_) {
        final stillLyricsOnly =
            selectedSong != null && selectedSong.availableTrackSlots.isEmpty;
        if ((!playing && !stillLyricsOnly) || speedLevel <= 0) {
          return;
        }
        if (_lineIndex < lineCount - 1) {
          _lineIndex += 1;
          onLineIndexChanged?.call();
        }
      });
      return;
    }

    if (!controller.hasClients) return;

    _timer = Timer.periodic(AppConstants.autoScrollInterval, (_) {
      final stillLyricsOnly =
          selectedSong != null && selectedSong.availableTrackSlots.isEmpty;
      if ((!playing && !stillLyricsOnly) ||
          !controller.hasClients ||
          speedLevel <= 0) {
        return;
      }
      final delta = PrompterLevels.scrollDeltaForSpeed(speedLevel);
      final next = (controller.offset + delta).clamp(
        0.0,
        controller.position.maxScrollExtent,
      );
      controller.jumpTo(next);
    });
  }
}
