// file: lib/widgets/song_list_screen_content.dart
//
// SongListScreen의 도메인 상태를 화면 패널 위젯들로 연결한다.
import 'package:flutter/material.dart';

import '../controllers/playback_controller.dart';
import '../controllers/import_job_controller.dart';
import '../models/mr_source_mode.dart';
import '../models/practice_session.dart';

import '../models/app_destination.dart';
import '../models/prompter_settings.dart';
import '../models/queue_item.dart';
import '../models/song.dart';
import '../services/prompter_settings_service.dart';
import '../services/song_filter_service.dart';
import '../theme/app_theme.dart';
import 'prompter_panel.dart';
import 'queue_panel.dart';
import 'settings_panel.dart';
import 'song_list_panel.dart';
import 'song_list_screen_view.dart';
import 'song_search_panel.dart';
import 'youtube_import_panel.dart';

class SongListScreenContent extends StatelessWidget {
  final bool loading;
  final AppDestination destination;
  final ValueChanged<AppDestination> onDestinationChanged;
  final List<Song> songs;
  final List<QueueItem> queue;
  final Song? selectedSong;
  final PrompterSettings settings;
  final int? selectedTrackSlot;
  final bool playing;
  final bool audioReady;
  final Duration duration;
  final PlaybackController playback;
  final List<PracticeSummary> practiceSummaries;
  final List<ImportJob> importJobs;
  final bool ytDlpAvailable;
  final String? ytDlpMissingReason;
  final void Function(String url, MrSourceMode mode) onStartYoutubeImport;
  final ValueChanged<String> onCancelImportJob;
  final VoidCallback onClearFinishedImports;
  final VoidCallback onLocateYtDlp;
  final VoidCallback onFetchSyncedLyrics;
  final ValueChanged<int> onAdjustLyricsOffset;
  final int pitchSemitones;
  final ValueChanged<int> onAdjustPitch;
  final ScrollController lyricsScrollController;
  final int highlightLineIndex;
  final String searchQuery;
  final String listQuery;
  final SongListFilterMode listFilterMode;
  final ValueChanged<String> onListQueryChanged;
  final ValueChanged<SongListFilterMode> onListFilterModeChanged;
  final SongListFilterMode searchFilterMode;
  final ValueChanged<String> onSearchQueryChanged;
  final ValueChanged<SongListFilterMode> onSearchFilterModeChanged;
  final VoidCallback onAddSong;
  final VoidCallback onBatchRegister;
  final VoidCallback onExportBackup;
  final VoidCallback onImportBackup;
  final void Function(Song song, int slot) onSelectTrack;
  final ValueChanged<Song> onSelectSong;
  final ValueChanged<Song> onStart;
  final ValueChanged<Song> onReserveSong;
  final ValueChanged<List<Song>> onReserveAllSongs;
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
    required this.destination,
    required this.onDestinationChanged,
    required this.songs,
    required this.queue,
    required this.selectedSong,
    required this.settings,
    required this.selectedTrackSlot,
    required this.playing,
    required this.audioReady,
    required this.duration,
    required this.playback,
    required this.practiceSummaries,
    required this.importJobs,
    required this.ytDlpAvailable,
    required this.ytDlpMissingReason,
    required this.onStartYoutubeImport,
    required this.onCancelImportJob,
    required this.onClearFinishedImports,
    required this.onLocateYtDlp,
    required this.onFetchSyncedLyrics,
    required this.onAdjustLyricsOffset,
    required this.pitchSemitones,
    required this.onAdjustPitch,
    required this.lyricsScrollController,
    required this.highlightLineIndex,
    required this.searchQuery,
    required this.listQuery,
    required this.listFilterMode,
    required this.onListQueryChanged,
    required this.onListFilterModeChanged,
    required this.searchFilterMode,
    required this.onSearchQueryChanged,
    required this.onSearchFilterModeChanged,
    required this.onAddSong,
    required this.onBatchRegister,
    required this.onExportBackup,
    required this.onImportBackup,
    required this.onSelectTrack,
    required this.onSelectSong,
    required this.onStart,
    required this.onReserveSong,
    required this.onReserveAllSongs,
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

  SongListPanel _buildSongListPanel({
    required SongListFilterMode filterMode,
    String? listTitle,
    bool showFilterChips = false,
  }) {
    return SongListPanel(
      songs: songs,
      selectedSong: selectedSong,
      selectedTrackSlot: selectedTrackSlot,
      filterMode: filterMode,
      listTitle: listTitle,
      showSearchControls: true,
      showFilterChips: showFilterChips,
      query: listQuery,
      onQueryChanged: onListQueryChanged,
      onFilterModeChanged: onListFilterModeChanged,
      onSelectTrack: onSelectTrack,
      onSelect: onSelectSong,
      onStart: onStart,
      onReserve: onReserveSong,
      onEdit: onEditSong,
      onDelete: onDeleteSong,
      onToggleFavorite: onToggleFavorite,
    );
  }

  PrompterPanel _buildPrompterPanel({required bool showQueue}) {
    return PrompterPanel(
      song: selectedSong,
      songs: songs,
      queue: queue,
      lyricsScrollController: lyricsScrollController,
      highlightLineIndex: highlightLineIndex,
      fontSize: settings.effectiveFontSizePt,
      lineHeight: settings.effectiveLineHeight,
      fontFamily: PrompterSettingsService.resolvedFontFamily(settings),
      playing: playing,
      audioReady: audioReady,
      duration: duration,
      playback: playback,
      hasSyncedLyrics: playback.timedLyrics.value != null,
      lyricsOffsetMs: playback.snapshot.lyricsOffsetMs,
      onFetchSyncedLyrics: onFetchSyncedLyrics,
      onAdjustLyricsOffset: onAdjustLyricsOffset,
      pitchSemitones: pitchSemitones,
      onAdjustPitch: onAdjustPitch,
      settings: settings,
      fontOptions: PrompterSettingsService.fontOptions,
      showQueue: showQueue,
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
    );
  }

  Widget _buildQueuePanel() {
    if (queue.isEmpty) {
      return Center(
        child: Text(
          '예약된 곡이 없습니다',
          style: AppTypography.bodyMuted,
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: QueuePanel(
        queue: queue,
        songs: songs,
        playingSongId: selectedSong?.id,
        playing: playing,
        onClear: onClearQueue,
        onReorder: onReorderQueue,
        onRemove: onRemoveQueueItem,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = selectedSong;
    return SongListScreenView(
      loading: loading,
      destination: destination,
      onDestinationChanged: onDestinationChanged,
      onAddSong: onAddSong,
      selectedSong: selectedSong,
      selectedTrackSlot: selectedTrackSlot,
      playing: playing,
      queueIsEmpty: queue.isEmpty,
      onStartPrompter:
          selected == null ? null : () => onOpenPrompter(selected),
      homeSongListPanel: _buildSongListPanel(
        // 홈에서는 사용자가 고른 필터를 그대로 쓴다.
        filterMode: listFilterMode,
        listTitle: '곡 목록',
        showFilterChips: true,
      ),
      favoritesSongListPanel: _buildSongListPanel(
        filterMode: SongListFilterMode.favorites,
        listTitle: '즐겨찾기',
      ),
      prompterPanel: _buildPrompterPanel(showQueue: false),
      queuePanel: _buildQueuePanel(),
      searchPanel: SongSearchPanel(
        songs: songs,
        searchQuery: searchQuery,
        filterMode: searchFilterMode,
        onSearchQueryChanged: onSearchQueryChanged,
        onFilterModeChanged: onSearchFilterModeChanged,
        onStart: onStart,
        onReserve: onReserveSong,
        onReserveAll: () {
          final results = SongFilterService.filter(
            songs,
            query: searchQuery,
            mode: searchFilterMode,
          );
          onReserveAllSongs(results);
        },
      ),
      importPanel: YoutubeImportPanel(
        jobs: importJobs,
        toolAvailable: ytDlpAvailable,
        toolMissingReason: ytDlpMissingReason,
        onSubmit: onStartYoutubeImport,
        onCancelJob: onCancelImportJob,
        onClearFinished: onClearFinishedImports,
        onLocateTool: onLocateYtDlp,
      ),
      settingsPanel: SettingsPanel(
        practiceSummaries: practiceSummaries,
        onBatchRegister: onBatchRegister,
        onExportBackup: onExportBackup,
        onImportBackup: onImportBackup,
        onCustomFontSize: onCustomFontSize,
        onAccessibilityPreset: onAccessibilityPreset,
      ),
    );
  }
}
