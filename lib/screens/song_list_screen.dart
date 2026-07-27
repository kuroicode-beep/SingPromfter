import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter/material.dart';

import '../controllers/import_job_controller.dart';
import '../controllers/playback_controller.dart';
import '../coordinators/song_action_coordinator.dart';
import '../dialogs/custom_font_size_dialog.dart';
import '../models/app_destination.dart';
import '../models/mr_source_mode.dart';
import '../models/prompter_display_mode.dart';
import '../models/prompter_settings.dart';
import '../models/queue_item.dart';
import '../models/song.dart';
import '../models/song_draft.dart';
import '../navigation/prompter_navigation.dart';
import '../repository/song_repository.dart';
import '../services/backup_service.dart';
import '../services/batch_registration_service.dart';
import '../services/lyrics_sync_service.dart';
import '../services/practice_log_service.dart';
import '../services/process/external_tool_locator.dart';
import '../services/process/tool_progress_parsers.dart';
import '../services/youtube_import_service.dart';
import '../services/prompter_audio_service.dart';
import '../services/prompter_settings_service.dart';
import '../services/song_library_service.dart';
import '../services/song_list_bootstrap_service.dart';
import '../services/song_queue_service.dart';
import '../services/song_filter_service.dart';
import '../widgets/song_list_screen_content.dart';
import '../widgets/snack_message.dart';
import '../widgets/prompter_keyboard_scope.dart';

class SongListScreen extends StatefulWidget {
  const SongListScreen({super.key});

  @override
  State<SongListScreen> createState() => _SongListScreenState();
}

class _SongListScreenState extends State<SongListScreen> {
  final _repo = SongRepository.instance;
  late final _queueService = SongQueueService(_repo);
  late final _bootstrapService = SongListBootstrapService(_repo);
  late final _libraryService = SongLibraryService(_repo);
  late final _backupService = BackupService(_repo);
  late final _batchService = BatchRegistrationService(_repo, _libraryService);
  late final _songActions = SongActionCoordinator(_repo, _libraryService);
  late final _audio = PrompterAudioService(_repo);
  final _lyricsScrollController = ScrollController();
  final _practiceLog = PracticeLogService();
  final _lyricsSync = LyricsSyncService();
  final _toolLocator = ExternalToolLocator();
  late final _youtubeImport = YoutubeImportService(
    tmpDirProvider: _repo.getTmpDir,
    locator: _toolLocator,
  );
  late final ImportJobController _importJobs;

  bool _ytDlpAvailable = false;
  String? _ytDlpMissingReason;

  late final PlaybackController _playback;

  final _pendingDeleteTimers = <String, Timer>{};

  List<Song> _songs = [];
  List<QueueItem> _queue = [];
  PrompterSettings _settings = const PrompterSettings();

  bool _loading = true;

  AppDestination _destination = AppDestination.home;
  String _searchQuery = '';
  SongListFilterMode _searchFilterMode = SongListFilterMode.all;

  // 좌측 목록 자체의 검색·필터 (검색 화면과 독립)
  String _listQuery = '';
  SongListFilterMode _listFilterMode = SongListFilterMode.all;

  Song? get _selectedSong => _playback.snapshot.song;
  int? get _selectedTrackSlot => _playback.snapshot.trackSlot;

  @override
  void initState() {
    super.initState();
    _playback = PlaybackController(
      audio: _audio,
      queueService: _queueService,
      repo: _repo,
      lyricsScrollController: _lyricsScrollController,
      songsProvider: () => _songs,
      queueProvider: () => _queue,
      settingsProvider: () => _settings,
      onQueueChanged: (queue) {
        if (mounted) setState(() => _queue = queue);
      },
      onMessage: _showSnack,
      timedLyricsLoader: _lyricsSync.loadFor,
      onPracticeSessionEnded: (snapshot, played) {
        _practiceLog.record(snapshot: snapshot, played: played);
      },
    )..init();
    // 재생 상태(저빈도)만 화면 재빌드에 연결한다. 위치(60Hz)는 구독 위젯이 직접 받는다.
    _playback.state.addListener(_onPlaybackStateChanged);
    _playback.lineIndex.addListener(_onPlaybackStateChanged);
    _importJobs = ImportJobController(runner: _runImportJob)
      ..addListener(_onPlaybackStateChanged);
    _bootstrap();
  }

  void _onPlaybackStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final timer in _pendingDeleteTimers.values) {
      timer.cancel();
    }
    _playback.state.removeListener(_onPlaybackStateChanged);
    _playback.lineIndex.removeListener(_onPlaybackStateChanged);
    _importJobs.dispose();
    _playback.dispose();
    _audio.dispose();
    _lyricsScrollController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final initial = await _bootstrapService.load();
    await _practiceLog.load();

    if (!mounted) return;
    setState(() {
      _songs = initial.songs;
      _queue = initial.queue;
      _settings = initial.settings;
      _loading = false;
    });

    unawaited(_refreshToolAvailability());

    await _audio.setVolume(_settings.volume);
    await _audio.setPlaybackRate(_settings.playbackRate);
    final initialSong = initial.initialSong;
    if (initialSong != null) {
      await _playback.loadSong(
        initialSong,
        preferredSlot:
            _settings.trackSlotForSong(initialSong.id) ??
            _settings.lastSelectedTrackSlot,
      );
    }
  }

  Future<void> _loadSong(Song song, {int? preferredSlot}) =>
      _playback.loadSong(song, preferredSlot: preferredSlot);

  Future<void> _togglePlayPause() => _playback.togglePlayPause();

  Future<void> _stopPlayback() => _playback.stop();

  Future<void> _restartPlayback() => _playback.restart();

  Future<void> _applyAccessibilityPreset(String preset) =>
      _updateSettings(PrompterSettingsService.preset(_settings, preset));

  Future<void> _updateSettings(PrompterSettings next) async {
    if (mounted) setState(() => _settings = next);
    await _repo.saveSettings(next);
    await _playback.applySettings(next);
  }

  Future<void> _showCustomFontSizeDialog() async {
    final next = await CustomFontSizeDialog.pickSettings(context, _settings);
    if (!mounted) return;
    if (next != null) await _updateSettings(next);
  }

  Future<void> _selectTrackSlot(int slot) async {
    final song = _selectedSong;
    if (song == null) return;
    if (!song.availableTrackSlots.contains(slot)) return;
    await _updateSettings(_settings.withSongTrackSlot(song.id, slot));
    await _playback.selectTrackSlot(slot);
  }

  // ── 싱크 가사 ───────────────────────────────────────────

  Future<void> _fetchSyncedLyrics() async {
    final song = _selectedSong;
    if (song == null) {
      _showSnack('먼저 곡을 선택해 주세요.');
      return;
    }
    _showSnack('싱크 가사를 찾는 중...');
    final outcome = await _lyricsSync.fetchFor(
      song,
      duration: _playback.snapshot.duration,
    );
    if (!mounted) return;
    if (outcome.success && outcome.song != null) {
      final updated = outcome.song!;
      setState(() {
        _songs = _songs
            .map((s) => s.id == updated.id ? updated : s)
            .toList(growable: false);
      });
      await _repo.saveSongs(_songs);
      // 새로 받은 가사를 즉시 반영하고 싱크 모드로 전환한다.
      _playback.timedLyrics.value = await _lyricsSync.loadFor(updated);
      await _updateSettings(
        _settings.copyWith(displayMode: PrompterDisplayMode.timed),
      );
    }
    if (!mounted) return;
    _showSnack(outcome.message);
  }

  /// 곡별 가사 선행/지연 오프셋을 바꾼다. 음수면 가사가 먼저 나온다.
  Future<void> _adjustLyricsOffset(int deltaMs) async {
    final song = _selectedSong;
    final slot = _selectedTrackSlot;
    if (song == null || slot == null) return;
    final track = song.trackForSlot(slot);
    if (track == null) return;

    final next = (track.lyricsOffsetMs + deltaMs).clamp(-3000, 3000);
    final updatedTracks = song.backingTracks
        .map((t) => t.slot == slot ? t.copyWith(lyricsOffsetMs: next) : t)
        .toList(growable: false);
    final updatedSong = song.copyWith(
      backingTracks: updatedTracks,
      updatedAt: DateTime.now(),
    );

    setState(() {
      _songs = _songs
          .map((s) => s.id == updatedSong.id ? updatedSong : s)
          .toList(growable: false);
    });
    await _repo.saveSongs(_songs);
    _playback.applyLyricsOffset(next);
  }

  // ── 유튜브 가져오기 ─────────────────────────────────────

  Future<void> _refreshToolAvailability() async {
    final tool = await _toolLocator.locate(ExternalTool.ytDlp, refresh: true);
    if (!mounted) return;
    setState(() {
      _ytDlpAvailable = tool.found;
      _ytDlpMissingReason = tool.found
          ? null
          : 'yt-dlp를 찾을 수 없습니다. 설치했다면 실행 파일 경로를 직접 지정해 주세요.';
    });
  }

  Future<void> _locateYtDlp() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'yt-dlp 실행 파일 선택',
    );
    final files = picked?.files ?? const [];
    final path = files.isEmpty ? null : files.first.path;
    if (path == null) return;
    await _toolLocator.setUserPath(ExternalTool.ytDlp, path);
    await _refreshToolAvailability();
    if (!mounted) return;
    _showSnack(_ytDlpAvailable ? 'yt-dlp 경로를 저장했습니다.' : '해당 파일을 실행할 수 없습니다.');
  }

  void _startYoutubeImport(String url, MrSourceMode mode) {
    if (!looksLikeYoutubeUrl(url)) {
      _showSnack('유튜브 주소가 아닙니다. 링크를 다시 확인해 주세요.');
      return;
    }
    _importJobs.enqueue(url: url, mode: mode, id: const Uuid().v4());
  }

  /// 작업 1건 수행: 메타 조회 → 내려받기 → 곡으로 등록.
  Future<void> _runImportJob(
    ImportJob job, {
    required void Function(JobProgress progress) onProgress,
    required void Function(void Function() cancel) onCancel,
  }) async {
    onProgress(const JobProgress(label: '영상 정보 확인 중'));
    final metadata = await _youtubeImport.fetchMetadata(job.url);
    if (metadata == null) {
      _failJob(job, '영상 정보를 가져오지 못했습니다. 링크와 yt-dlp 설치를 확인해 주세요.');
      return;
    }
    _importJobs.update(
      _importJobs.jobById(job.id)?.copyWith(title: metadata.title) ?? job,
    );

    final result = await _youtubeImport.download(
      url: job.url,
      jobId: job.id,
      metadata: metadata,
      mode: job.mode,
      onProgress: onProgress,
      onCancel: onCancel,
    );

    // 사용자가 중간에 취소했으면 결과를 덮어쓰지 않는다.
    final current = _importJobs.jobById(job.id);
    if (current == null || current.status != ImportJobStatus.running) {
      await _youtubeImport.cleanupJob(job.id);
      return;
    }

    if (!result.success) {
      _failJob(job, result.message ?? '가져오기에 실패했습니다.');
      await _youtubeImport.cleanupJob(job.id);
      return;
    }

    onProgress(const JobProgress(ratio: 1, label: '곡으로 등록 중'));
    final registered = await _registerImportedSong(
      metadata: metadata,
      audioPath: result.audioPath!,
    );
    await _youtubeImport.cleanupJob(job.id);

    final finished = _importJobs.jobById(job.id);
    if (finished == null) return;
    _importJobs.update(
      finished.copyWith(
        status: registered ? ImportJobStatus.done : ImportJobStatus.failed,
        statusDetail: registered ? '곡 목록에 추가했습니다.' : '곡 등록에 실패했습니다.',
        ratio: 1,
      ),
    );
  }

  void _failJob(ImportJob job, String message) {
    final current = _importJobs.jobById(job.id);
    if (current == null) return;
    _importJobs.update(
      current.copyWith(
        status: ImportJobStatus.failed,
        statusDetail: message,
        clearRatio: true,
      ),
    );
  }

  /// 받은 오디오를 반주 1번 슬롯으로 하는 곡을 만든다.
  /// 가사는 비워 두고 이후 단계(가사 가져오기)에서 채운다.
  Future<bool> _registerImportedSong({
    required YoutubeMetadata metadata,
    required String audioPath,
  }) async {
    try {
      final title = _libraryService.hasDuplicateTitle(_songs, metadata.title)
          ? '${metadata.title} (가져오기)'
          : metadata.title;
      final draft = SongDraft(
        title: title.isEmpty ? '제목 없음' : title,
        artist: metadata.uploader,
        trackPaths: {1: audioPath},
        trackLabels: {1: 'MR1'},
      );
      final result = await _libraryService.addSong(
        songs: _songs,
        draft: draft,
        lyrics: '',
      );
      if (!mounted) return true;
      setState(() => _songs = result.songs);
      return true;
    } catch (e) {
      debugPrint('가져온 곡 등록 실패: $e');
      return false;
    }
  }
  Future<void> _addSong() async => _applySongActionOutcome(
    await _songActions.addSong(context: context, songs: _songs),
  );

  Future<void> _editSong(Song song) async {
    final outcome = await _songActions.editSong(
      context: context,
      songs: _songs,
      song: song,
      selectedSong: _selectedSong,
    );
    await _applySongActionOutcome(outcome, preferredSlot: _selectedTrackSlot);
  }

  Future<void> _deleteSong(Song song) async => _applySongActionOutcome(
    await _songActions.deleteSong(
      context: context,
      songs: _songs,
      queue: _queue,
      song: song,
      selectedSong: _selectedSong,
    ),
  );

  Future<void> _toggleFavorite(Song song) async {
    final result = await _libraryService.toggleFavorite(
      songs: _songs,
      song: song,
    );
    if (!mounted) return;
    setState(() {
      _songs = result.songs;
    });
    if (_selectedSong?.id == song.id) {
      await _playback.loadSong(result.song, preferredSlot: _selectedTrackSlot);
    }
  }

  Future<void> _exportBackup() async {
    final result = await _backupService.exportAll();
    if (result == null) return;
    _showSnack(
      result.success
          ? '${result.songCount}곡 백업 완료: ${result.path}'
          : result.message ?? '백업에 실패했습니다.',
    );
  }

  Future<void> _importBackup() async {
    final result = await _backupService.importFromPicker(_songs);
    if (result == null) return;
    if (!result.success) {
      _showSnack(result.message ?? '백업 가져오기에 실패했습니다.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _songs = result.songs ?? _songs;
    });
    final next = _selectedSong ?? (_songs.isNotEmpty ? _songs.first : null);
    if (next != null) await _loadSong(next);
    _showSnack(
      '${result.importedCount}곡 가져오기 완료, 이름변경 ${result.renamedCount}곡',
    );
  }

  Future<void> _batchRegister() async {
    final matches = await _batchService.pickAndMatch();
    if (matches == null) return;
    if (matches.isEmpty) {
      _showSnack('등록할 txt 파일을 찾지 못했습니다.');
      return;
    }
    if (!mounted) return;
    final confirmed = await _confirmBatchMatches(matches);
    if (confirmed != true) return;

    final result = await _batchService.register(
      songs: _songs,
      matches: matches,
    );
    if (!mounted) return;
    setState(() {
      _songs = result.songs;
    });
    final next = _selectedSong ?? (_songs.isNotEmpty ? _songs.first : null);
    if (next != null) await _loadSong(next);
    _showSnack(
      '${result.importedCount}곡 일괄 등록, 중복 건너뜀 ${result.skippedCount}곡',
    );
  }

  Future<bool?> _confirmBatchMatches(List<BatchMatch> matches) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('일괄 등록 확인'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${matches.length}개 txt 파일을 찾았습니다. 모두 등록할까요?'),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: matches.length,
                  itemBuilder: (_, index) {
                    final match = matches[index];
                    return ListTile(
                      dense: true,
                      title: Text(match.title),
                      subtitle: Text('반주 ${match.trackPaths.length}개 매칭'),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('등록'),
          ),
        ],
      ),
    );
  }

  Future<void> _applySongActionOutcome(
    SongActionOutcome? outcome, {
    int? preferredSlot,
  }) async {
    if (outcome == null) return;
    if (outcome.stopPlayback) {
      await _stopPlayback();
    }

    if (!mounted) return;
    setState(() {
      if (outcome.songs != null) _songs = outcome.songs!;
      if (outcome.queue != null) _queue = outcome.queue!;
    });
    if (outcome.clearSelectedTrackSlot) {
      _playback.clearSelection();
    }

    if (outcome.loadSong != null) {
      await _loadSong(outcome.loadSong!, preferredSlot: preferredSlot);
    }
    if (outcome.deletedSong != null) {
      _showDeleteUndoSnack(outcome.deletedSong!, outcome.message);
    } else if (outcome.message != null) {
      _showSnack(outcome.message!);
    }
  }

  void _showDeleteUndoSnack(Song song, String? message) {
    _pendingDeleteTimers[song.id]?.cancel();
    _pendingDeleteTimers[song.id] = Timer(const Duration(seconds: 10), () {
      _pendingDeleteTimers.remove(song.id);
      _libraryService.permanentlyDeleteSong(song);
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message ?? '"${song.title}" 삭제됨'),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: '실행 취소',
            onPressed: () => _restoreDeletedSong(song),
          ),
        ),
      );
  }

  Future<void> _restoreDeletedSong(Song song) async {
    _pendingDeleteTimers.remove(song.id)?.cancel();
    final result = await _libraryService.restoreSong(songs: _songs, song: song);
    if (!mounted) return;
    setState(() {
      _songs = result.songs;
    });
    if (_selectedSong == null || _selectedSong!.id == result.song.id) {
      await _loadSong(result.song);
    }
    _showSnack('"${song.title}" 복원 완료');
  }

  Future<void> _reserveSong(Song song) async {
    await _applyQueueChange(
      _queueService.addSong(queue: _queue, song: song, settings: _settings),
      message: '"${song.title}" 예약 완료',
    );
  }

  Future<void> _removeQueueItem(int index) =>
      _applyQueueChange(_queueService.removeAt(_queue, index));

  Future<void> _reorderQueue(int oldIndex, int newIndex) =>
      _applyQueueChange(_queueService.reorder(_queue, oldIndex, newIndex));

  Future<void> _clearQueue() => _applyQueueChange(_queueService.clear());

  Future<void> _applyQueueChange(
    Future<List<QueueItem>> queueTask, {
    String? message,
  }) async {
    final next = await queueTask;
    if (!mounted) return;
    setState(() => _queue = next);
    if (message != null) _showSnack(message);
  }

  Future<void> _startSong(Song song) async {
    await _loadSong(song);
    final snapshot = _playback.snapshot;
    if (snapshot.audioReady && !snapshot.playing) {
      await _togglePlayPause();
    }
    if (!mounted) return;
    _openPrompter(song);
  }

  Future<void> _reserveAllSongs(List<Song> songs) async {
    if (songs.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('전체 곡 예약'),
        content: Text('검색 결과 ${songs.length}곡을 모두 예약 큐에 추가할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('예약'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _applyQueueChange(
      _queueService.addSongs(
        queue: _queue,
        songs: songs,
        settings: _settings,
      ),
      message: '${songs.length}곡 예약 완료',
    );
  }

  void _openPrompter(Song song) {
    // 컨트롤러를 넘겨 전체화면도 살아 있는 재생 위치를 구독하게 한다.
    PrompterNavigation.open(
      context: context,
      song: song,
      settings: _settings,
      playback: _playback,
      fontSize: _settings.effectiveFontSizePt,
      lineHeight: _settings.effectiveLineHeight,
      fontFamily: PrompterSettingsService.resolvedFontFamily(_settings),
      onSettingsChanged: _updateSettings,
    );
  }

  void _showSnack(String message) =>
      mounted ? SnackMessage.show(context, message) : null;

  @override
  Widget build(BuildContext context) {
    final snapshot = _playback.snapshot;
    return PrompterKeyboardScope(
      settings: _settings,
      onSettingsChanged: _updateSettings,
      onTogglePlayPause: _togglePlayPause,
      onOpenPrompter: () {
        final song = _selectedSong;
        if (song != null) _openPrompter(song);
      },
      child: SongListScreenContent(
        loading: _loading,
        destination: _destination,
        onDestinationChanged: (next) => setState(() => _destination = next),
        songs: _songs,
        queue: _queue,
        selectedSong: snapshot.song,
        settings: _settings,
        selectedTrackSlot: snapshot.trackSlot,
        playing: snapshot.playing,
        audioReady: snapshot.audioReady,
        duration: snapshot.duration,
        playback: _playback,
        practiceSummaries: _practiceLog.summaries,
        importJobs: _importJobs.jobs,
        ytDlpAvailable: _ytDlpAvailable,
        ytDlpMissingReason: _ytDlpMissingReason,
        onStartYoutubeImport: _startYoutubeImport,
        onCancelImportJob: _importJobs.cancel,
        onClearFinishedImports: _importJobs.clearFinished,
        onLocateYtDlp: _locateYtDlp,
        onFetchSyncedLyrics: _fetchSyncedLyrics,
        onAdjustLyricsOffset: _adjustLyricsOffset,
        lyricsScrollController: _lyricsScrollController,
        highlightLineIndex: _playback.lineIndex.value,
        searchQuery: _searchQuery,
        searchFilterMode: _searchFilterMode,
        listQuery: _listQuery,
        listFilterMode: _listFilterMode,
        onListQueryChanged: (value) => setState(() => _listQuery = value),
        onListFilterModeChanged: (value) =>
            setState(() => _listFilterMode = value),
        onSearchQueryChanged: (value) => setState(() => _searchQuery = value),
        onSearchFilterModeChanged: (value) =>
            setState(() => _searchFilterMode = value),
        onAddSong: _addSong,
        onBatchRegister: _batchRegister,
        onExportBackup: _exportBackup,
        onImportBackup: _importBackup,
        onSelectTrack: (_, slot) => _selectTrackSlot(slot),
        onSelectSong: _loadSong,
        onStart: _startSong,
        onReserveSong: _reserveSong,
        onReserveAllSongs: _reserveAllSongs,
        onEditSong: _editSong,
        onDeleteSong: _deleteSong,
        onToggleFavorite: _toggleFavorite,
        onStop: _stopPlayback,
        onTogglePlayPause: _togglePlayPause,
        onRestart: _restartPlayback,
        onSkipNext: _playback.onSongCompleted,
        onOpenPrompter: _openPrompter,
        onSeek: _playback.seek,
        onSettingsChanged: _updateSettings,
        onCustomFontSize: _showCustomFontSizeDialog,
        onAccessibilityPreset: _applyAccessibilityPreset,
        onMessage: _showSnack,
        onClearQueue: _clearQueue,
        onReorderQueue: _reorderQueue,
        onRemoveQueueItem: _removeQueueItem,
      ),
    );
  }
}
