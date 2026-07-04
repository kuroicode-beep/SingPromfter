import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../coordinators/song_action_coordinator.dart';
import '../dialogs/custom_font_size_dialog.dart';
import '../models/app_destination.dart';
import '../models/prompter_settings.dart';
import '../models/queue_item.dart';
import '../models/song.dart';
import '../navigation/prompter_navigation.dart';
import '../repository/song_repository.dart';
import '../services/backup_service.dart';
import '../services/batch_registration_service.dart';
import '../services/prompter_auto_scroll_service.dart';
import '../services/prompter_audio_service.dart';
import '../services/prompter_settings_service.dart';
import '../services/song_library_service.dart';
import '../services/song_list_bootstrap_service.dart';
import '../services/song_queue_service.dart';
import '../services/song_list_shortcut_service.dart';
import '../services/song_filter_service.dart';
import '../widgets/song_list_screen_content.dart';
import '../widgets/snack_message.dart';

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
  late final _autoScroll = PrompterAutoScrollService(_lyricsScrollController);

  AudioBindings? _audioBindings;
  Timer? _noAudioSkipTimer;
  final _pendingDeleteTimers = <String, Timer>{};

  List<Song> _songs = [];
  List<QueueItem> _queue = [];
  Song? _selectedSong;
  PrompterSettings _settings = const PrompterSettings();

  bool _loading = true;
  bool _playing = false;
  bool _audioReady = false;
  bool _processingQueue = false;

  int? _selectedTrackSlot;
  int? _selectedTrackStartMs;
  int? _selectedTrackEndMs;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  AppDestination _destination = AppDestination.home;
  String _searchQuery = '';
  SongListFilterMode _searchFilterMode = SongListFilterMode.all;
  int _highlightLineIndex = 0;

  @override
  void initState() {
    super.initState();
    _autoScroll.onLineIndexChanged = () {
      if (!mounted) return;
      setState(() => _highlightLineIndex = _autoScroll.lineIndex);
    };
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _bindPlayerStreams();
    _bootstrap();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _autoScroll.dispose();
    _noAudioSkipTimer?.cancel();
    for (final timer in _pendingDeleteTimers.values) {
      timer.cancel();
    }
    _audioBindings?.cancel();
    _audio.dispose();
    _lyricsScrollController.dispose();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!mounted) return false;
    return SongListShortcutService.handle(
      event: event,
      selectedSong: _selectedSong,
      onTogglePlayPause: _togglePlayPause,
      onOpenPrompter: _openPrompter,
    );
  }

  Future<void> _bootstrap() async {
    final initial = await _bootstrapService.load();

    if (!mounted) return;
    setState(() {
      _songs = initial.songs;
      _queue = initial.queue;
      _settings = initial.settings;
      _selectedSong = initial.initialSong;
      _loading = false;
    });

    await _audio.setVolume(_settings.volume);
    await _audio.setPlaybackRate(_settings.playbackRate);
    if (_selectedSong != null) {
      await _loadSong(
        _selectedSong!,
        preferredSlot:
            _settings.trackSlotForSong(_selectedSong!.id) ??
            _settings.lastSelectedTrackSlot,
      );
    }
  }

  void _bindPlayerStreams() {
    _audioBindings = _audio.bind(
      onPlayingChanged: (playing) {
        if (!mounted) return;
        setState(() => _playing = playing);
        _syncAutoScroll();
      },
      onPositionChanged: (pos) {
        if (!mounted) return;
        setState(() => _position = pos);
        final endMs = _selectedTrackEndMs;
        if (_playing && endMs != null && pos.inMilliseconds >= endMs) {
          _onSongCompleted();
        }
      },
      onDurationChanged: (dur) {
        if (!mounted) return;
        setState(() => _duration = dur);
      },
      onCompleted: _onSongCompleted,
    );
  }

  Future<void> _onSongCompleted() async {
    if (_processingQueue) return;
    _processingQueue = true;
    try {
      await _playNextFromQueue();
    } finally {
      _processingQueue = false;
    }
  }

  Future<void> _playNextFromQueue() async {
    final next = await _queueService.popNextPlayable(
      queue: _queue,
      songs: _songs,
    );
    if (!mounted) return;
    setState(() => _queue = next?.queue ?? const []);
    if (next == null) return;

    await _loadSong(
      next.song,
      preferredSlot: next.selectedTrackSlot,
      autoPlay: true,
    );
  }

  Future<void> _loadSong(
    Song song, {
    int? preferredSlot,
    bool autoPlay = false,
  }) async {
    _noAudioSkipTimer?.cancel();
    final available = song.availableTrackSlots;
    int? resolvedSlot;

    if (preferredSlot != null && available.contains(preferredSlot)) {
      resolvedSlot = preferredSlot;
    } else {
      final savedForSong = _settings.trackSlotForSong(song.id);
      if (savedForSong != null && available.contains(savedForSong)) {
        resolvedSlot = savedForSong;
      } else if (_settings.lastSelectedTrackSlot != null &&
          available.contains(_settings.lastSelectedTrackSlot)) {
        resolvedSlot = _settings.lastSelectedTrackSlot;
      } else if (available.isNotEmpty) {
        resolvedSlot = available.first;
      }
    }

    if (mounted) {
      setState(() {
        _selectedSong = song;
        _selectedTrackSlot = resolvedSlot;
        final track = song.trackForSlot(resolvedSlot ?? -1);
        _selectedTrackStartMs = track?.startMs;
        _selectedTrackEndMs = track?.endMs;
        _position = Duration.zero;
        _highlightLineIndex = 0;
      });
      _autoScroll.resetLineIndex();
    }

    await _repo.saveLastSongId(song.id);
    await _prepareAudioForSelection();

    if (autoPlay && available.isEmpty && _queue.isNotEmpty) {
      _noAudioSkipTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          _onSongCompleted();
        }
      });
    }

    if (autoPlay && _audioReady) {
      await _audio.resumeFromStart(startMs: _selectedTrackStartMs);
    }
    _syncAutoScroll();
  }

  Future<void> _prepareAudioForSelection() async {
    final result = await _audio.prepareSelection(
      song: _selectedSong,
      selectedTrackSlot: _selectedTrackSlot,
      volume: _settings.volume,
      playbackRate: _settings.playbackRate,
      startMs: _selectedTrackStartMs,
    );
    if (!mounted) return;
    setState(() {
      _audioReady = result.ready;
      _duration = Duration.zero;
      _position = Duration.zero;
    });
    if (result.message != null) {
      _showSnack(result.message!);
    }
  }

  Future<void> _togglePlayPause() async {
    final message = await _audio.togglePlayPause(
      song: _selectedSong,
      audioReady: _audioReady,
      playing: _playing,
    );
    if (message != null) _showSnack(message);
  }

  Future<void> _stopPlayback() async {
    await _audio.stop();
    if (mounted) setState(() => _position = Duration.zero);
  }

  Future<void> _restartPlayback() async {
    final message = await _audio.restart(
      audioReady: _audioReady,
      startMs: _selectedTrackStartMs,
    );
    if (message != null) _showSnack(message);
  }

  void _syncAutoScroll() {
    _autoScroll.sync(
      selectedSong: _selectedSong,
      playing: _playing,
      speedLevel: _settings.speedLevel,
      displayMode: _settings.displayMode,
    );
    if (mounted) {
      setState(() => _highlightLineIndex = _autoScroll.lineIndex);
    }
  }

  Future<void> _applyAccessibilityPreset(String preset) =>
      _updateSettings(PrompterSettingsService.preset(_settings, preset));

  Future<void> _updateSettings(PrompterSettings next) async {
    if (mounted) setState(() => _settings = next);
    await _repo.saveSettings(next);
    await _audio.setVolume(next.volume);
    await _audio.setPlaybackRate(next.playbackRate);
    _syncAutoScroll();
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
    final track = song.trackForSlot(slot);

    if (mounted) {
      setState(() {
        _selectedTrackSlot = slot;
        _selectedTrackStartMs = track?.startMs;
        _selectedTrackEndMs = track?.endMs;
      });
    }
    await _updateSettings(_settings.withSongTrackSlot(song.id, slot));
    await _prepareAudioForSelection();
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
      if (_selectedSong?.id == song.id) _selectedSong = result.song;
    });
  }

  Future<void> _exportBackup() async {
    final result = await _backupService.exportAll(appVersion: '0.8.0');
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
      _selectedSong ??= _songs.isNotEmpty ? _songs.first : null;
    });
    if (_selectedSong != null) await _loadSong(_selectedSong!);
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
      _selectedSong ??= _songs.isNotEmpty ? _songs.first : null;
    });
    if (_selectedSong != null) await _loadSong(_selectedSong!);
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
      if (outcome.selectedSong != null || outcome.clearSelectedTrackSlot) {
        _selectedSong = outcome.selectedSong;
      }
      if (outcome.clearSelectedTrackSlot) {
        _selectedTrackSlot = null;
        _selectedTrackStartMs = null;
        _selectedTrackEndMs = null;
      }
    });

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
      _selectedSong ??= result.song;
    });
    if (_selectedSong?.id == result.song.id) await _loadSong(result.song);
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
    if (_audioReady && !_playing) {
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
    PrompterNavigation.open(
      context: context,
      song: song,
      settings: _settings,
      fontSize: _settings.effectiveFontSizePt,
      lineHeight: _settings.effectiveLineHeight,
      fontFamily: PrompterSettingsService.resolvedFontFamily(_settings),
      autoScrollEnabled: _playing || !_audioReady,
      audioReady: _audioReady,
      position: _position,
      duration: _duration,
      onSeek: _audio.seek,
      onSettingsChanged: _updateSettings,
    );
  }

  void _showSnack(String message) =>
      mounted ? SnackMessage.show(context, message) : null;

  @override
  Widget build(BuildContext context) {
    return SongListScreenContent(
      loading: _loading,
      destination: _destination,
      onDestinationChanged: (next) => setState(() => _destination = next),
      songs: _songs,
      queue: _queue,
      selectedSong: _selectedSong,
      settings: _settings,
      selectedTrackSlot: _selectedTrackSlot,
      playing: _playing,
      audioReady: _audioReady,
      position: _position,
      duration: _duration,
      lyricsScrollController: _lyricsScrollController,
      highlightLineIndex: _highlightLineIndex,
      searchQuery: _searchQuery,
      searchFilterMode: _searchFilterMode,
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
      onSkipNext: _onSongCompleted,
      onOpenPrompter: _openPrompter,
      onSeek: _audio.seek,
      onSettingsChanged: _updateSettings,
      onCustomFontSize: _showCustomFontSizeDialog,
      onAccessibilityPreset: _applyAccessibilityPreset,
      onMessage: _showSnack,
      onClearQueue: _clearQueue,
      onReorderQueue: _reorderQueue,
      onRemoveQueueItem: _removeQueueItem,
    );
  }
}
