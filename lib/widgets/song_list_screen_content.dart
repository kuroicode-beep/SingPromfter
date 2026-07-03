// file: lib/widgets/song_list_screen_content.dart
//
// SongListScreen의 도메인 상태를 화면 패널 위젯들로 연결한다.
import 'package:flutter/material.dart';

import '../models/prompter_settings.dart';
import '../models/queue_item.dart';
import '../models/song.dart';
import '../services/prompter_settings_service.dart';
import 'prompter_panel.dart';
import 'song_list_panel.dart';
import 'song_list_screen_view.dart';

class SongListScreenContent extends StatelessWidget {
  final bool loading;
  final List<Song> songs;
  final List<QueueItem> queue;
  final Song? selectedSong;
  final PrompterSettings settings;
  final int? selectedTrackSlot;
  final bool playing;
  final bool audioReady;
  final Duration position;
  final Duration duration;
  final ScrollController lyricsScrollController;
  final VoidCallback onAddSong;
  final VoidCallback onBatchRegister;
  final VoidCallback onExportBackup;
  final VoidCallback onImportBackup;
  final void Function(Song song, int slot) onSelectTrack;
  final ValueChanged<Song> onSelectSong;
  final ValueChanged<Song> onPlayNow;
  final ValueChanged<Song> onReserveSong;
  final ValueChanged<Song> onEditSong;
  final ValueChanged<Song> onDeleteSong;
  final ValueChanged<Song> onToggleFavorite;
  final VoidCallback onStop;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onRestart;
  final VoidCallback onSkipNext;
  final ValueChanged<Song> onOpenPrompter;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<PrompterSettings> onSettingsChanged;
  final VoidCallback onCustomFontSize;
  final ValueChanged<String> onAccessibilityPreset;
  final ValueChanged<String> onMessage;
  final VoidCallback onClearQueue;
  final void Function(int oldIndex, int newIndex) onReorderQueue;
  final ValueChanged<int> onRemoveQueueItem;

  const SongListScreenContent({
    super.key,
    required this.loading,
    required this.songs,
    required this.queue,
    required this.selectedSong,
    required this.settings,
    required this.selectedTrackSlot,
    required this.playing,
    required this.audioReady,
    required this.position,
    required this.duration,
    required this.lyricsScrollController,
    required this.onAddSong,
    required this.onBatchRegister,
    required this.onExportBackup,
    required this.onImportBackup,
    required this.onSelectTrack,
    required this.onSelectSong,
    required this.onPlayNow,
    required this.onReserveSong,
    required this.onEditSong,
    required this.onDeleteSong,
    required this.onToggleFavorite,
    required this.onStop,
    required this.onTogglePlayPause,
    required this.onRestart,
    required this.onSkipNext,
    required this.onOpenPrompter,
    required this.onSeek,
    required this.onSettingsChanged,
    required this.onCustomFontSize,
    required this.onAccessibilityPreset,
    required this.onMessage,
    required this.onClearQueue,
    required this.onReorderQueue,
    required this.onRemoveQueueItem,
  });

  @override
  Widget build(BuildContext context) {
    return SongListScreenView(
      loading: loading,
      songListPanel: SongListPanel(
        songs: songs,
        selectedSong: selectedSong,
        selectedTrackSlot: selectedTrackSlot,
        onSelectTrack: onSelectTrack,
        onSelect: onSelectSong,
        onPlayNow: onPlayNow,
        onReserve: onReserveSong,
        onEdit: onEditSong,
        onDelete: onDeleteSong,
        onToggleFavorite: onToggleFavorite,
      ),
      prompterPanel: PrompterPanel(
        song: selectedSong,
        songs: songs,
        queue: queue,
        lyricsScrollController: lyricsScrollController,
        fontSize: settings.effectiveFontSizePt,
        lineHeight: settings.effectiveLineHeight,
        fontFamily: PrompterSettingsService.resolvedFontFamily(settings),
        playing: playing,
        audioReady: audioReady,
        position: position,
        duration: duration,
        settings: settings,
        fontOptions: PrompterSettingsService.fontOptions,
        onStop: onStop,
        onTogglePlayPause: onTogglePlayPause,
        onRestart: onRestart,
        onSkipNext: onSkipNext,
        onOpenPrompter: onOpenPrompter,
        onSeek: onSeek,
        onSettingsChanged: onSettingsChanged,
        onCustomFontSize: onCustomFontSize,
        onAccessibilityPreset: onAccessibilityPreset,
        onMessage: onMessage,
        onClearQueue: onClearQueue,
        onReorderQueue: onReorderQueue,
        onRemoveQueueItem: onRemoveQueueItem,
      ),
      onAddSong: onAddSong,
      onBatchRegister: onBatchRegister,
      onExportBackup: onExportBackup,
      onImportBackup: onImportBackup,
    );
  }
}
