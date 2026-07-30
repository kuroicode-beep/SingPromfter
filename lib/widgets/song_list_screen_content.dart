// file: lib/widgets/song_list_screen_content.dart
//
// SongListScreen의 도메인 상태를 화면 패널 위젯들로 연결한다.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../controllers/playback_controller.dart';
import '../controllers/import_job_controller.dart';
import '../models/mr_source_mode.dart';
import '../models/practice_session.dart';
import '../models/recording_take.dart';
import '../models/vocal_routine.dart';

import '../models/app_destination.dart';
import '../models/prompter_settings.dart';
import '../models/queue_item.dart';
import '../models/song.dart';
import '../services/prompter_settings_service.dart';
import '../utils/music_key.dart';
import '../services/song_filter_service.dart';
import '../services/song_sort_service.dart';
import '../theme/app_theme.dart';
import 'prompter_panel.dart';
import 'queue_panel.dart';
import 'settings_panel.dart';
import 'song_list_panel.dart';
import 'song_list_screen_view.dart';
import 'prompter_line_list_view.dart' show LineEditRequest;
import 'search_hub_panel.dart';
import 'song_search_panel.dart';
import 'youtube_search_panel.dart';
import 'import_progress_strip.dart';
import 'recordings_panel.dart';
import 'training_panel.dart';
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
  final ValueChanged<String> onRetryImportJob;
  final VoidCallback onClearFinishedImports;
  final VoidCallback onLocateYtDlp;
  final String? ytDlpVersion;
  final VoidCallback onUpdateYtDlp;
  final String separatorStatusLabel;
  final VoidCallback onImportLrcFile;
  final ValueChanged<RecordingTake> onMixTake;
  final ValueChanged<RecordingTake> onAnalyzeTake;
  final ValueChanged<RecordingTake> onCorrectTake;
  final ValueChanged<RecordingTake> onPlayTakeMix;
  final VoidCallback onFetchSyncedLyrics;
  final ValueChanged<int> onAdjustLyricsOffset;

  /// 원곡·MR 비교로 가사 싱크를 자동으로 맞춘다.
  final VoidCallback? onAutoAlignLyrics;

  /// AI 받아쓰기(STT)로 싱크 가사 생성 + 프롬프터 인라인 가사 수정.
  final VoidCallback? onSttLyrics;
  final void Function(int index, String text)? onEditLyricsLine;
  final LineEditRequest? lineEditRequest;

  /// 재생 중에 "지금이 첫 줄"을 지정한다(단축키 T).
  final VoidCallback? onAnchorFirstLine;
  final int pitchSemitones;
  final ValueChanged<int> onAdjustPitch;

  /// 현재 반주의 템포(배)와 조절 콜백.
  final double tempoScale;
  final ValueChanged<double> onAdjustTempo;

  /// Alt+휠 경로 — 굴리는 동안은 표시만, 렌더는 손을 멈춘 뒤.
  final void Function(int delta)? onStepPitch;

  /// 분리 서버가 꺼져 있을 때 홈 상태 칩으로 켠다.
  final Future<bool> Function()? onStartSeparator;
  final ValueListenable<int?>? pendingPitch;
  final ValueListenable<double?>? pendingTempo;

  /// 지금 들리는 조성(곡 조성 + 구운 키 + 사용자 키).
  final MusicKey? soundingKey;

  /// 사용자 키 이전의 슬롯 조성 — 키 HUD 기준값.
  final MusicKey? pitchBaseKey;
  final bool isRecording;
  final String recordingLevelLabel;
  final Duration recordingElapsed;
  final VoidCallback onToggleRecording;
  final List<RecordingTake> recordingTakes;
  final String recordingQuery;
  final RecordingFilterMode recordingFilterMode;
  final String? playingTakeId;
  final ValueChanged<String> onRecordingQueryChanged;
  final ValueChanged<RecordingFilterMode> onRecordingFilterModeChanged;
  final ValueChanged<RecordingTake> onPlayTake;
  final ValueChanged<RecordingTake> onStopTake;
  final ValueChanged<RecordingTake> onEditTakeComment;
  final void Function(RecordingTake take, int rating) onRateTake;
  final ValueChanged<RecordingTake> onToggleTakeKeep;
  final ValueChanged<RecordingTake> onDeleteTake;
  final DailyGoalLog todayGoal;
  final int trainingStreak;
  final int trainingCompletedThisWeek;
  final ValueChanged<String> onRoutineChanged;
  final ValueChanged<String> onToggleRoutineStep;
  final ScrollController lyricsScrollController;
  final int highlightLineIndex;
  final String searchQuery;
  final String listQuery;
  final SongListFilterMode listFilterMode;
  final ValueChanged<String> onListQueryChanged;
  final ValueChanged<SongListFilterMode> onListFilterModeChanged;
  final SongSortMode listSortMode;
  final ValueChanged<SongSortMode> onListSortModeChanged;

  /// 곡 목록 드래그 재정렬 — 보이는 id 순서와 출발/도착(보정) 인덱스.
  final void Function(List<String> visibleIds, int oldIndex, int newIndex)
  onReorderSongs;
  final SongListFilterMode searchFilterMode;
  final ValueChanged<String> onSearchQueryChanged;
  final ValueChanged<SongListFilterMode> onSearchFilterModeChanged;

  /// 곡 검색 탭의 [내 곡 | 유튜브] 전환과 유튜브 검색 상태(화면 State 소유).
  final SearchSource searchSource;
  final ValueChanged<SearchSource> onSearchSourceChanged;
  final YoutubeSearchViewState youtubeSearch;
  final ValueChanged<String> onYoutubeSearch;
  final ValueChanged<YoutubeChartKind> onYoutubeChartChanged;
  final ValueChanged<YoutubeVideo> onYoutubeImport;
  final VoidCallback onAddSong;
  final VoidCallback onExportBackup;
  final VoidCallback onImportBackup;
  final VoidCallback onRunMaintenance;
  final void Function(Song song, int slot) onSelectTrack;
  final ValueChanged<Song> onAddTrack;
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
    required this.onRetryImportJob,
    required this.onClearFinishedImports,
    required this.onLocateYtDlp,
    this.ytDlpVersion,
    required this.onUpdateYtDlp,
    required this.separatorStatusLabel,
    required this.onImportLrcFile,
    required this.onMixTake,
    required this.onAnalyzeTake,
    required this.onCorrectTake,
    required this.onPlayTakeMix,
    required this.onFetchSyncedLyrics,
    required this.onAdjustLyricsOffset,
    this.onAutoAlignLyrics,
    this.onSttLyrics,
    this.onEditLyricsLine,
    this.lineEditRequest,
    this.onAnchorFirstLine,
    required this.pitchSemitones,
    required this.onAdjustPitch,
    this.tempoScale = 1,
    required this.onAdjustTempo,
    this.onStepPitch,
    this.onStartSeparator,
    this.pendingPitch,
    this.pendingTempo,
    this.soundingKey,
    this.pitchBaseKey,
    required this.isRecording,
    required this.recordingLevelLabel,
    required this.recordingElapsed,
    required this.onToggleRecording,
    required this.recordingTakes,
    required this.recordingQuery,
    required this.recordingFilterMode,
    required this.playingTakeId,
    required this.onRecordingQueryChanged,
    required this.onRecordingFilterModeChanged,
    required this.onPlayTake,
    required this.onStopTake,
    required this.onEditTakeComment,
    required this.onRateTake,
    required this.onToggleTakeKeep,
    required this.onDeleteTake,
    required this.todayGoal,
    required this.trainingStreak,
    required this.trainingCompletedThisWeek,
    required this.onRoutineChanged,
    required this.onToggleRoutineStep,
    required this.lyricsScrollController,
    required this.highlightLineIndex,
    required this.searchQuery,
    required this.listQuery,
    required this.listFilterMode,
    required this.onListQueryChanged,
    required this.onListFilterModeChanged,
    required this.listSortMode,
    required this.onListSortModeChanged,
    required this.onReorderSongs,
    required this.searchFilterMode,
    required this.onSearchQueryChanged,
    required this.onSearchFilterModeChanged,
    required this.searchSource,
    required this.onSearchSourceChanged,
    required this.youtubeSearch,
    required this.onYoutubeSearch,
    required this.onYoutubeChartChanged,
    required this.onYoutubeImport,
    required this.onAddSong,
    required this.onExportBackup,
    required this.onImportBackup,
    required this.onRunMaintenance,
    required this.onSelectTrack,
    required this.onAddTrack,
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

  /// 곡별 현재 키(원곡 대비 반음). 저장된 슬롯이 없으면 첫 반주 기준.
  Map<String, int> _pitchBySongId() {
    final result = <String, int>{};
    for (final song in songs) {
      final slot =
          settings.trackSlotForSong(song.id) ??
          (song.availableTrackSlots.isNotEmpty
              ? song.availableTrackSlots.first
              : null);
      final semitones = settings.pitchForSong(song.id, slot);
      if (semitones != 0) result[song.id] = semitones;
    }
    return result;
  }

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
      sortMode: listSortMode,
      onSortModeChanged: onListSortModeChanged,
      practiceCounts: SongSortService.practiceCountsFrom(
        practiceSummaries,
      ),
      pitchBySongId: _pitchBySongId(),
      onSelectTrack: onSelectTrack,
      onAddTrack: onAddTrack,
      onSelect: onSelectSong,
      onStart: onStart,
      onReserve: onReserveSong,
      onEdit: onEditSong,
      onDelete: onDeleteSong,
      onToggleFavorite: onToggleFavorite,
      onReorder: onReorderSongs,
    );
  }

  PrompterPanel _buildPrompterPanel({required bool showQueue}) {
    return PrompterPanel(
      onAddSong: onAddSong,
      onStartSeparator: onStartSeparator,
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
      onImportLrcFile: onImportLrcFile,
      onAdjustLyricsOffset: onAdjustLyricsOffset,
      onAutoAlignLyrics: onAutoAlignLyrics,
      onAnchorFirstLine: onAnchorFirstLine,
      onSttLyrics: onSttLyrics,
      onEditLyricsLine: onEditLyricsLine,
      lineEditRequest: lineEditRequest,
      pitchSemitones: pitchSemitones,
      onAdjustPitch: onAdjustPitch,
      onStepPitch: onStepPitch,
      pendingPitch: pendingPitch,
      pendingTempo: pendingTempo,
      soundingKey: soundingKey,
      pitchBaseKey: pitchBaseKey,
      tempoScale: tempoScale,
      onAdjustTempo: onAdjustTempo,
      isRecording: isRecording,
      recordingLevelLabel: recordingLevelLabel,
      recordingElapsed: recordingElapsed,
      onToggleRecording: onToggleRecording,
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

    // 사이드바에 상단 고정으로 꽉 차게 — 스크롤은 패널 안 목록이 맡는다.
    return Padding(
      padding: const EdgeInsets.all(6),
      child: QueuePanel(
        queue: queue,
        songs: songs,
        playingSongId: selectedSong?.id,
        playing: playing,
        onClear: onClearQueue,
        onReorder: onReorderQueue,
        onRemove: onRemoveQueueItem,
        expand: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SongListScreenView(
      loading: loading,
      destination: destination,
      onDestinationChanged: onDestinationChanged,
      selectedSong: selectedSong,
      selectedTrackSlot: selectedTrackSlot,
      playing: playing,
      queueLength: queue.length,
      queueSidebarOpen: settings.queueSidebarOpen,
      onQueueSidebarChanged: (open) =>
          onSettingsChanged(settings.copyWith(queueSidebarOpen: open)),
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
      searchPanel: SearchHubPanel(
        source: searchSource,
        onSourceChanged: onSearchSourceChanged,
        mySongsPanel: SongSearchPanel(
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
        youtubePanel: YoutubeSearchPanel(
          state: youtubeSearch,
          onSearch: onYoutubeSearch,
          onChartChanged: onYoutubeChartChanged,
          onImport: onYoutubeImport,
        ),
      ),
      trainingPanel: TrainingPanel(
        todayLog: todayGoal,
        streak: trainingStreak,
        completedThisWeek: trainingCompletedThisWeek,
        summaries: practiceSummaries,
        onRoutineChanged: onRoutineChanged,
        onToggleStep: onToggleRoutineStep,
      ),
      recordingsPanel: RecordingsPanel(
        takes: recordingTakes,
        query: recordingQuery,
        filterMode: recordingFilterMode,
        playingTakeId: playingTakeId,
        onQueryChanged: onRecordingQueryChanged,
        onFilterModeChanged: onRecordingFilterModeChanged,
        onPlay: onPlayTake,
        onStopPlay: onStopTake,
        onEditComment: onEditTakeComment,
        onRate: onRateTake,
        onToggleKeep: onToggleTakeKeep,
        onDelete: onDeleteTake,
        onMix: onMixTake,
        onAnalyze: onAnalyzeTake,
        onCorrect: onCorrectTake,
        onPlayMix: onPlayTakeMix,
      ),
      importProgress: ImportProgressStrip(
        jobs: importJobs,
        onCancel: onCancelImportJob,
        onRetry: onRetryImportJob,
        onOpenJobs: () => onDestinationChanged(AppDestination.jobs),
      ),
      importPanel: YoutubeImportPanel(
        jobs: importJobs,
        toolAvailable: ytDlpAvailable,
        toolMissingReason: ytDlpMissingReason,
        onSubmit: onStartYoutubeImport,
        onCancelJob: onCancelImportJob,
        onRetryJob: onRetryImportJob,
        onClearFinished: onClearFinishedImports,
        onLocateTool: onLocateYtDlp,
        toolVersion: ytDlpVersion,
        onUpdateTool: onUpdateYtDlp,
        separatorStatusLabel: separatorStatusLabel,
      ),
      settingsPanel: SettingsPanel(
        practiceSummaries: practiceSummaries,
        ytDlpVersion: ytDlpVersion,
        settings: settings,
        onSettingsChanged: onSettingsChanged,
        fontOptions: PrompterSettingsService.fontOptions,
        separatorStatusLabel: separatorStatusLabel,
        onUpdateYtDlp: onUpdateYtDlp,
        onExportBackup: onExportBackup,
        onImportBackup: onImportBackup,
        onRunMaintenance: onRunMaintenance,
        onCustomFontSize: onCustomFontSize,
        onAccessibilityPreset: onAccessibilityPreset,
      ),
    );
  }
}
