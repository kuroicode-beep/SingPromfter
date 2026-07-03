// file: lib/services/prompter_auto_scroll_service.dart
//
// 가사 자동 스크롤 타이머를 관리한다.
import 'dart:async';

import 'package:flutter/widgets.dart';

import '../constants/app_constants.dart';
import '../models/song.dart';
import '../theme/prompter_levels.dart';

class PrompterAutoScrollService {
  final ScrollController controller;
  Timer? _timer;

  PrompterAutoScrollService(this.controller);

  void dispose() => _timer?.cancel();

  void sync({
    required Song? selectedSong,
    required bool playing,
    required double speedLevel,
  }) {
    _timer?.cancel();
    final isLyricsOnly =
        selectedSong != null && selectedSong.availableTrackSlots.isEmpty;
    final shouldScroll = playing || isLyricsOnly;
    if (!shouldScroll || speedLevel <= 0 || !controller.hasClients) {
      return;
    }

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
