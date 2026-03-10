
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:uuid/uuid.dart';

import '../models/prompter_settings.dart';
import '../models/queue_item.dart';
import '../models/song.dart';
import '../repository/song_repository.dart';
import '../theme/app_theme.dart';
import 'prompter_screen.dart';

class SongListScreen extends StatefulWidget {
  const SongListScreen({super.key});

  @override
  State<SongListScreen> createState() => _SongListScreenState();
}

class _SongListScreenState extends State<SongListScreen> {
  static const Map<String, String?> _fontOptions = {
    '기본 (시스템 기본)': null,
    '맑은 고딕 (저시력 추천)': 'MalgunGothic',
    'Segoe UI (균형형)': 'SegoeUI',
    '고정폭 (정렬용)': 'monospace',
  };

  final _repo = SongRepository.instance;
  final _player = AudioPlayer();
  final _lyricsScrollController = ScrollController();

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  Timer? _autoScrollTimer;

  List<Song> _songs = [];
  List<QueueItem> _queue = [];
  Song? _selectedSong;
  PrompterSettings _settings = const PrompterSettings();

  bool _loading = true;
  bool _playing = false;
  bool _audioReady = false;
  bool _processingQueue = false;

  int? _selectedTrackSlot;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _bindPlayerStreams();
    _bootstrap();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _player.dispose();
    _lyricsScrollController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final songs = await _repo.loadSongs();
    final queue = await _repo.loadQueue();
    final settings = await _repo.loadSettings();
    final lastSongId = await _repo.loadLastSongId();

    Song? initialSong;
    if (lastSongId != null) {
      initialSong = songs.where((s) => s.id == lastSongId).cast<Song?>().firstWhere(
            (s) => s != null,
            orElse: () => null,
          );
    }
    initialSong ??= songs.isNotEmpty ? songs.first : null;

    if (!mounted) return;
    setState(() {
      _songs = songs;
      _queue = queue;
      _settings = settings;
      _selectedSong = initialSong;
      _loading = false;
    });

    await _player.setVolume(_settings.volume);
    if (_selectedSong != null) {
      await _loadSong(
        _selectedSong!,
        preferredSlot: _settings.trackSlotForSong(_selectedSong!.id) ?? _settings.lastSelectedTrackSlot,
      );
    }
  }

  void _bindPlayerStreams() {
    _playerStateSub = _player.playerStateStream.listen((state) async {
      if (!mounted) return;
      setState(() => _playing = state.playing);
      _syncAutoScroll();

      if (state.processingState == ProcessingState.completed) {
        await _onSongCompleted();
      }
    });

    _positionSub = _player.positionStream.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
    });

    _durationSub = _player.durationStream.listen((dur) {
      if (!mounted) return;
      setState(() => _duration = dur ?? Duration.zero);
    });
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
    while (_queue.isNotEmpty) {
      final next = _queue.first;
      _queue = List<QueueItem>.from(_queue)..removeAt(0);
      await _repo.saveQueue(_queue);
      if (mounted) setState(() {});

      Song? song;
      for (final item in _songs) {
        if (item.id == next.songId) {
          song = item;
          break;
        }
      }
      if (song == null) continue;

      await _loadSong(song, preferredSlot: next.selectedTrackSlot, autoPlay: true);
      return;
    }
  }

  Future<void> _loadSong(Song song, {int? preferredSlot, bool autoPlay = false}) async {
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
        _position = Duration.zero;
      });
    }

    await _repo.saveLastSongId(song.id);
    await _prepareAudioForSelection();

    if (autoPlay && _audioReady) {
      await _player.seek(Duration.zero);
      await _player.play();
    }
  }

  Future<void> _prepareAudioForSelection() async {
    final song = _selectedSong;
    if (song == null || _selectedTrackSlot == null) {
      _audioReady = false;
      _duration = Duration.zero;
      _position = Duration.zero;
      return;
    }

    final track = song.trackForSlot(_selectedTrackSlot!);
    if (track == null) {
      _audioReady = false;
      _duration = Duration.zero;
      _position = Duration.zero;
      return;
    }

    final path = await _repo.getBackingTrackPath(track.fileName);
    if (path == null) {
      _audioReady = false;
      _duration = Duration.zero;
      _position = Duration.zero;
      if (mounted) _showSnack('선택한 반주 파일을 찾을 수 없습니다.');
      return;
    }

    try {
      await _player.stop();
      await _player.setFilePath(path);
      await _player.setVolume(_settings.volume);
      _audioReady = true;
      _duration = _player.duration ?? Duration.zero;
      _position = Duration.zero;
    } catch (_) {
      _audioReady = false;
      _duration = Duration.zero;
      _position = Duration.zero;
      if (mounted) _showSnack('반주 파일을 재생할 수 없습니다.');
    }
  }

  Future<void> _togglePlayPause() async {
    final song = _selectedSong;
    if (song == null) return;

    if (!_audioReady) {
      if (song.backingTracks.isEmpty) {
        _showSnack('이 곡은 반주가 없어 가사만 표시됩니다.');
      } else {
        _showSnack('재생 가능한 반주를 먼저 선택해 주세요.');
      }
      return;
    }

    if (_playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _stopPlayback() async {
    await _player.stop();
    await _player.seek(Duration.zero);
    if (mounted) setState(() => _position = Duration.zero);
  }

  Future<void> _restartPlayback() async {
    if (!_audioReady) {
      _showSnack('재생 가능한 반주가 없습니다.');
      return;
    }
    await _player.seek(Duration.zero);
    await _player.play();
  }

  void _syncAutoScroll() {
    _autoScrollTimer?.cancel();
    if (!_playing || _settings.speedLevel <= 0 || !_lyricsScrollController.hasClients) return;

    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (!_playing || !_lyricsScrollController.hasClients) return;
      final delta = _settings.speedLevel * 1.4;
      final next = (_lyricsScrollController.offset + delta).clamp(
        0.0,
        _lyricsScrollController.position.maxScrollExtent,
      );
      _lyricsScrollController.jumpTo(next);
    });
  }

  double get _fontSizePt {
    final v = _settings.fontSizeLevel;
    if (v <= 1) return 18;
    if (v <= 2) return 24;
    if (v <= 3) return 32;
    if (v <= 4) return 42;
    return 56;
  }

  double get _lineHeightVal {
    final v = _settings.lineHeightLevel;
    if (v <= 1) return 1.4;
    if (v <= 2) return 1.6;
    if (v <= 3) return 1.9;
    if (v <= 4) return 2.2;
    return 2.6;
  }

    String? get _resolvedFontFamily {
    if (_fontOptions.containsKey(_settings.fontFamily)) {
      return _fontOptions[_settings.fontFamily];
    }
    if (_settings.fontFamily == '기본') {
      return null;
    }
    return _settings.fontFamily;
  }

  Future<void> _applyAccessibilityPreset(String preset) async {
    switch (preset) {
      case 'recommended':
        await _updateSettings(
          _settings.copyWith(
            fontSizeLevel: 4,
            lineHeightLevel: 4,
            speedLevel: 3,
            fontFamily: '맑은 고딕 (저시력 추천)',
            boldText: true,
          ),
        );
        break;
      case 'stage':
        await _updateSettings(
          _settings.copyWith(
            fontSizeLevel: 5,
            lineHeightLevel: 5,
            speedLevel: 2,
            fontFamily: '맑은 고딕 (저시력 추천)',
            boldText: true,
          ),
        );
        break;
      default:
        await _updateSettings(
          _settings.copyWith(
            fontSizeLevel: 3,
            lineHeightLevel: 3,
            speedLevel: 2,
            fontFamily: '기본 (시스템 기본)',
            boldText: false,
          ),
        );
    }
  }

  Future<void> _updateSettings(PrompterSettings next) async {
    if (mounted) setState(() => _settings = next);
    await _repo.saveSettings(next);
    await _player.setVolume(next.volume);
    _syncAutoScroll();
  }

  Future<void> _selectTrackSlot(int slot) async {
    final song = _selectedSong;
    if (song == null) return;
    if (!song.availableTrackSlots.contains(slot)) return;

    if (mounted) setState(() => _selectedTrackSlot = slot);
    await _updateSettings(_settings.withSongTrackSlot(song.id, slot));
    await _prepareAudioForSelection();
  }

  Future<String> _decodeLyricsFromFile(String path) async {
    final bytes = await File(path).readAsBytes();
    try {
      return utf8.decode(bytes).trim();
    } catch (_) {
      // CP949가 아닌 환경에서도 깨짐을 줄이기 위한 최소 fallback
      return latin1.decode(bytes).trim();
    }
  }
  Future<void> _addSong() async {
    final lyricsFile = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
      dialogTitle: '가사 파일(txt) 선택',
    );
    if (lyricsFile == null || lyricsFile.files.isEmpty) return;

    final picked = lyricsFile.files.first;
    final ext = picked.extension?.toLowerCase() ?? '';
    if (ext != 'txt') {
      _showSnack('txt 파일만 선택할 수 있습니다.');
      return;
    }

    final sourcePath = picked.path;
    if (sourcePath == null) {
      _showSnack('파일 경로를 읽을 수 없습니다.');
      return;
    }

    String lyrics;
    try {
      lyrics = await _decodeLyricsFromFile(sourcePath);
    } catch (_) {
      _showSnack('가사 파일 읽기에 실패했습니다.');
      return;
    }

    final draft = await _showSongCreateDialog(picked.name);
    if (draft == null) return;

    final id = const Uuid().v4();
    try {
      final song = await _repo.addSong(
        id: id,
        title: draft.title,
        lyrics: lyrics,
        sourceTrackPaths: draft.trackPaths,
      );

      final nextSongs = List<Song>.from(_songs)..add(song);
      await _repo.saveSongs(nextSongs);

      if (!mounted) return;
      setState(() => _songs = nextSongs);
      await _loadSong(song);
      _showSnack('곡이 추가되었습니다.');
    } catch (_) {
      _showSnack('곡 추가 중 오류가 발생했습니다.');
    }
  }

  Future<_SongDraft?> _showSongCreateDialog(String fileName) async {
    final titleController = TextEditingController(
      text: fileName.replaceAll(RegExp(r'\.txt$', caseSensitive: false), ''),
    );
    final trackPaths = <int, String?>{1: null, 2: null, 3: null};

    return showDialog<_SongDraft>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> pickTrack(int slot) async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.audio,
                dialogTitle: '반주$slot 파일 선택',
              );
              if (result == null || result.files.isEmpty) return;
              final path = result.files.first.path;
              if (path == null) {
                _showSnack('반주 파일 경로를 읽을 수 없습니다.');
                return;
              }
              setLocal(() => trackPaths[slot] = path);
            }

            return AlertDialog(
              backgroundColor: AppColors.elevated,
              title: const Text('곡 추가', style: TextStyle(color: AppColors.textPrimary)),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: titleController,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: '곡 제목',
                          labelStyle: TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '반주 연결 (선택: 1~3개)',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      for (final slot in [1, 2, 3])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 58,
                                child: Text('반주$slot', style: const TextStyle(color: AppColors.textPrimary)),
                              ),
                              Expanded(
                                child: Text(
                                  trackPaths[slot] == null
                                      ? '선택 안 됨'
                                      : trackPaths[slot]!.split('\\').last,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: trackPaths[slot] == null
                                        ? AppColors.textMuted
                                        : AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(onPressed: () => pickTrack(slot), child: const Text('선택')),
                              const SizedBox(width: 6),
                              TextButton(
                                onPressed: () => setLocal(() => trackPaths[slot] = null),
                                child: const Text('취소'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
                ElevatedButton(
                  onPressed: () {
                    final title = titleController.text.trim().isEmpty
                        ? fileName
                        : titleController.text.trim();
                    final normalized = <int, String>{};
                    trackPaths.forEach((slot, path) {
                      if (path != null && path.trim().isNotEmpty) {
                        normalized[slot] = path;
                      }
                    });
                    Navigator.pop(ctx, _SongDraft(title: title, trackPaths: normalized));
                  },
                  child: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteSong(Song song) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        title: const Text('삭제', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          '"${song.title}"을(를) 삭제하시겠습니까?',
          style: const TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _repo.deleteSong(song);

    final nextSongs = List<Song>.from(_songs)..removeWhere((s) => s.id == song.id);
    final nextQueue = List<QueueItem>.from(_queue)..removeWhere((q) => q.songId == song.id);

    Song? nextSelected = _selectedSong;
    if (_selectedSong?.id == song.id) {
      await _stopPlayback();
      nextSelected = nextSongs.isNotEmpty ? nextSongs.first : null;
    }

    await _repo.saveSongs(nextSongs);
    await _repo.saveQueue(nextQueue);

    if (!mounted) return;
    setState(() {
      _songs = nextSongs;
      _queue = nextQueue;
      _selectedSong = nextSelected;
      _selectedTrackSlot = null;
    });

    if (nextSelected != null) {
      await _loadSong(nextSelected);
    } else {
      await _repo.saveLastSongId(null);
    }
  }

  Future<void> _reserveSong(Song song) async {
    final songSlot = _settings.trackSlotForSong(song.id);
    final slot = song.availableTrackSlots.contains(songSlot)
        ? songSlot
        : (song.availableTrackSlots.isNotEmpty ? song.availableTrackSlots.first : null);

    final nextQueue = List<QueueItem>.from(_queue)
      ..add(QueueItem(songId: song.id, selectedTrackSlot: slot, queuedAt: DateTime.now()));

    await _repo.saveQueue(nextQueue);
    if (!mounted) return;
    setState(() => _queue = nextQueue);
    _showSnack('"${song.title}" 예약 완료');
  }

  Future<void> _removeQueueItem(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final next = List<QueueItem>.from(_queue)..removeAt(index);
    await _repo.saveQueue(next);
    if (!mounted) return;
    setState(() => _queue = next);
  }

  Future<void> _reorderQueue(int oldIndex, int newIndex) async {
    if (_queue.isEmpty || oldIndex < 0 || oldIndex >= _queue.length) return;
    final next = List<QueueItem>.from(_queue);
    if (newIndex > oldIndex) newIndex -= 1;
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    await _repo.saveQueue(next);
    if (!mounted) return;
    setState(() => _queue = next);
  }

  Future<void> _clearQueue() async {
    await _repo.saveQueue(const []);
    if (!mounted) return;
    setState(() => _queue = []);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SingPromfter v0.2')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : LayoutBuilder(
              builder: (_, constraints) {
                final wide = constraints.maxWidth >= 980;
                if (wide) {
                  return Row(
                    children: [
                      SizedBox(width: 360, child: _buildSongListPanel()),
                      const VerticalDivider(width: 1),
                      Expanded(child: _buildPrompterPanel()),
                    ],
                  );
                }

                return Column(
                  children: [
                    Expanded(flex: 5, child: _buildSongListPanel()),
                    const Divider(height: 1),
                    Expanded(flex: 6, child: _buildPrompterPanel()),
                  ],
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSong,
        icon: const Icon(Icons.library_add),
        label: const Text('곡 추가'),
      ),
    );
  }

  Widget _buildSongListPanel() {
    if (_songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.queue_music, size: 56, color: AppColors.border),
            SizedBox(height: 14),
            Text(
              '등록된 곡이 없습니다',
              style: TextStyle(color: AppColors.textMuted, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text('하단 + 버튼으로 곡을 추가해 주세요', style: TextStyle(color: AppColors.textMuted)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      itemCount: _songs.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final song = _songs[i];
        final selected = _selectedSong?.id == song.id;
        return _SongTile(
          song: song,
          selected: selected,
          onSelect: () => _loadSong(song),
          onPlayNow: () async {
            await _loadSong(song);
            await _togglePlayPause();
          },
          onReserve: () => _reserveSong(song),
          onDelete: () => _deleteSong(song),
        );
      },
    );
  }
  Widget _buildPrompterPanel() {
    final song = _selectedSong;
    if (song == null) {
      return const Center(
        child: Text('곡을 선택해 주세요', style: TextStyle(color: AppColors.textMuted, fontSize: 18)),
      );
    }

    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _buildTrackSelector(song),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _lyricsScrollController,
                      child: Text(
                        song.lyricsText.isEmpty ? '(가사가 없습니다)' : song.lyricsText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: _fontSizePt,
                          height: _lineHeightVal,
                          fontFamily: _resolvedFontFamily,
                          fontWeight: _settings.boldText ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildPromptTextStyleControls(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _buildPlaybackSection(song),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: _buildQueuePanel(),
          ),
        ],
      ),
    );
  }

    Widget _buildPromptTextStyleControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.elevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        children: [
          const Text('프롬프트 아래 설정 (v0.3.1)',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PresetBtn(label: '표준', onTap: () => _applyAccessibilityPreset('standard')),
              _PresetBtn(label: '저시력 추천', onTap: () => _applyAccessibilityPreset('recommended')),
              _PresetBtn(label: '원거리 무대', onTap: () => _applyAccessibilityPreset('stage')),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('글꼴', style: TextStyle(color: AppColors.textPrimary)),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _fontOptions.containsKey(_settings.fontFamily)
                    ? _settings.fontFamily
                    : '기본 (시스템 기본)',
                dropdownColor: AppColors.surface,
                items: _fontOptions.keys
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(growable: false),
                onChanged: (v) {
                  if (v == null) return;
                  _updateSettings(_settings.copyWith(fontFamily: v));
                },
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: _settings.boldText,
                onChanged: (v) => _updateSettings(_settings.copyWith(boldText: v ?? false)),
              ),
              const Text('굵게 (blod)', style: TextStyle(color: AppColors.textPrimary)),
            ],
          ),
        ],
      ),
    );
  }
  Widget _buildTrackSelector(Song song) {
    if (song.backingTracks.isEmpty) {
      return const Text('반주 없음 (가사만 표시)', style: TextStyle(color: AppColors.textMuted));
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: song.backingTracks.map((track) {
        final selected = _selectedTrackSlot == track.slot;
        return OutlinedButton.icon(
          onPressed: () => _selectTrackSlot(track.slot),
          icon: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, size: 16),
          label: Text('반주${track.slot}'),
          style: OutlinedButton.styleFrom(
            backgroundColor: selected ? AppColors.accent : AppColors.elevated,
            foregroundColor: selected ? const Color(0xFF0A0A0A) : AppColors.textPrimary,
            side: BorderSide(color: selected ? AppColors.accent : AppColors.border),
            minimumSize: const Size(110, 44),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPlaybackSection(Song song) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (_, constraints) {
          final narrow = constraints.maxWidth < 760;
          return Column(
            children: [
              if (narrow) ...[
                _buildLabeledSlider(
                  '글자 크기',
                  _settings.fontSizeLevel,
                  (v) => _updateSettings(_settings.copyWith(fontSizeLevel: v)),
                  min: 1,
                  max: 5,
                  divisions: 4,
                ),
                _buildLabeledSlider(
                  '줄 간격',
                  _settings.lineHeightLevel,
                  (v) => _updateSettings(_settings.copyWith(lineHeightLevel: v)),
                  min: 1,
                  max: 5,
                  divisions: 4,
                ),
                _buildLabeledSlider(
                  '속도',
                  _settings.speedLevel,
                  (v) => _updateSettings(_settings.copyWith(speedLevel: v)),
                  min: 0,
                  max: 10,
                  divisions: 20,
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: _buildLabeledSlider(
                        '글자 크기',
                        _settings.fontSizeLevel,
                        (v) => _updateSettings(_settings.copyWith(fontSizeLevel: v)),
                        min: 1,
                        max: 5,
                        divisions: 4,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildLabeledSlider(
                        '줄 간격',
                        _settings.lineHeightLevel,
                        (v) => _updateSettings(_settings.copyWith(lineHeightLevel: v)),
                        min: 1,
                        max: 5,
                        divisions: 4,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildLabeledSlider(
                        '속도',
                        _settings.speedLevel,
                        (v) => _updateSettings(_settings.copyWith(speedLevel: v)),
                        min: 0,
                        max: 10,
                        divisions: 20,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              Column(
                children: [
                  Slider(
                    min: 0,
                    max: _duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                    value: _position.inMilliseconds.toDouble().clamp(
                      0,
                      _duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                    ),
                    onChanged: _audioReady ? (v) => _player.seek(Duration(milliseconds: v.toInt())) : null,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(_position),
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      Text(_formatDuration(_duration),
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  _PlayBtn(icon: Icons.stop, label: '정지', onTap: _stopPlayback),
                  _PlayBtn(
                    icon: _playing ? Icons.pause : Icons.play_arrow,
                    label: _playing ? '일시정지' : '재생',
                    onTap: _togglePlayPause,
                    highlighted: true,
                  ),
                  _PlayBtn(icon: Icons.replay, label: '처음', onTap: _restartPlayback),
                  _PlayBtn(
                    icon: Icons.fullscreen,
                    label: '전체화면',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PrompterScreen(
                          song: song,
                          fontSize: _fontSizePt,
                          lineHeight: _lineHeightVal,
                          fontFamily: _resolvedFontFamily,
                          boldText: _settings.boldText,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.volume_down, size: 18, color: AppColors.textMuted),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: 1,
                      value: _settings.volume,
                      onChanged: (v) => _updateSettings(_settings.copyWith(volume: v)),
                    ),
                  ),
                  const Icon(Icons.volume_up, size: 18, color: AppColors.textMuted),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLabeledSlider(
    String label,
    double value,
    ValueChanged<double> onChanged, {
    required double min,
    required double max,
    int? divisions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        Slider(min: min, max: max, divisions: divisions, value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _buildQueuePanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '예약 큐',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              TextButton(onPressed: _queue.isEmpty ? null : _clearQueue, child: const Text('큐 비우기')),
            ],
          ),
          if (_queue.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('예약된 곡이 없습니다.', style: TextStyle(color: AppColors.textMuted)),
            )
          else
            SizedBox(
              height: 140,
              child: ReorderableListView.builder(
                itemCount: _queue.length,
                onReorder: _reorderQueue,
                buildDefaultDragHandles: false,
                itemBuilder: (_, i) {
                  final item = _queue[i];
                  Song? song;
                  for (final s in _songs) {
                    if (s.id == item.songId) {
                      song = s;
                      break;
                    }
                  }
                  return ListTile(
                    key: ValueKey('${item.songId}_${item.queuedAt.toIso8601String()}_$i'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    dense: true,
                    leading: ReorderableDragStartListener(
                      index: i,
                      child: const Icon(Icons.drag_indicator, color: AppColors.textMuted),
                    ),
                    title: Text(
                      '${i + 1}. ${song?.title ?? '(삭제된 곡)'}',
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                    ),
                    subtitle: Text(
                      item.selectedTrackSlot == null ? '가사 전용' : '반주 ${item.selectedTrackSlot}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                    trailing: IconButton(
                      onPressed: () => _removeQueueItem(i),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SongTile extends StatelessWidget {
  final Song song;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onPlayNow;
  final VoidCallback onReserve;
  final VoidCallback onDelete;

  const _SongTile({
    required this.song,
    required this.selected,
    required this.onSelect,
    required this.onPlayNow,
    required this.onReserve,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final mrLabel = song.backingTracks.isEmpty
        ? 'MR 없음'
        : song.backingTracks.length == 1
            ? 'MR 1개 있음'
            : 'MR ${song.backingTracks.length}개 있음';

    return Material(
      color: selected ? const Color(0xFF2A240A) : AppColors.elevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(mrLabel, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SmallActionButton(label: '선택', icon: Icons.check, onTap: onSelect),
                  _SmallActionButton(label: '재생', icon: Icons.play_arrow, onTap: onPlayNow, primary: true),
                  _SmallActionButton(label: '예약', icon: Icons.schedule, onTap: onReserve),
                  _SmallActionButton(label: '삭제', icon: Icons.delete_outline, onTap: onDelete),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  const _SmallActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: primary ? AppColors.accent : AppColors.border,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: primary ? const Color(0xFF0A0A0A) : AppColors.textPrimary),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: primary ? const Color(0xFF0A0A0A) : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Future<void> Function() onTap;
  final bool highlighted;

  const _PlayBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(),
      child: Container(
        width: 88,
        height: 64,
        decoration: BoxDecoration(
          color: highlighted ? AppColors.accent : AppColors.elevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: highlighted ? AppColors.accent : AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: highlighted ? const Color(0xFF0A0A0A) : AppColors.textPrimary),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: highlighted ? const Color(0xFF0A0A0A) : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _PresetBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PresetBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
class _SongDraft {
  final String title;
  final Map<int, String> trackPaths;

  const _SongDraft({required this.title, required this.trackPaths});
}








