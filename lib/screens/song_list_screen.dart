import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
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
    'System Default': null,
    'Malgun Gothic': 'MalgunGothic',
    'Segoe UI': 'SegoeUI',
    'Monospace': 'monospace',
  };

  final _repo = SongRepository.instance;
  final _player = AudioPlayer();
  final _lyricsScrollController = ScrollController();

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
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
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _bindPlayerStreams();
    _bootstrap();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _autoScrollTimer?.cancel();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _player.dispose();
    _lyricsScrollController.dispose();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!mounted) return false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      _togglePlayPause();
      return true;
    }
    if (key == LogicalKeyboardKey.f5) {
      final song = _selectedSong;
      if (song != null) {
        _openPrompter(song);
      }
      return true;
    }
    return false;
  }

  Future<void> _bootstrap() async {
    final songs = await _repo.loadSongs();
    final queue = await _repo.loadQueue();
    final settings = await _repo.loadSettings();
    final lastSongId = await _repo.loadLastSongId();

    Song? initialSong;
    if (lastSongId != null) {
      initialSong = songs
          .where((s) => s.id == lastSongId)
          .cast<Song?>()
          .firstWhere((s) => s != null, orElse: () => null);
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
        preferredSlot:
            _settings.trackSlotForSong(_selectedSong!.id) ??
            _settings.lastSelectedTrackSlot,
      );
    }
  }

  void _bindPlayerStreams() {
    _playerStateSub = _player.onPlayerStateChanged.listen((state) async {
      if (!mounted) return;
      setState(() => _playing = state == PlayerState.playing);
      _syncAutoScroll();

      if (state == PlayerState.completed) {
        await _onSongCompleted();
      }
    });

    _positionSub = _player.onPositionChanged.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
    });

    _durationSub = _player.onDurationChanged.listen((dur) {
      if (!mounted) return;
      setState(() => _duration = dur);
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

      await _loadSong(
        song,
        preferredSlot: next.selectedTrackSlot,
        autoPlay: true,
      );
      return;
    }
  }

  Future<void> _loadSong(
    Song song, {
    int? preferredSlot,
    bool autoPlay = false,
  }) async {
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
      await _player.resume();
    }
  }

  Future<void> _prepareAudioForSelection() async {
    final song = _selectedSong;
    if (song == null || _selectedTrackSlot == null) {
      if (mounted) {
        setState(() {
          _audioReady = false;
          _duration = Duration.zero;
          _position = Duration.zero;
        });
      }
      return;
    }

    final track = song.trackForSlot(_selectedTrackSlot!);
    if (track == null) {
      if (mounted) {
        setState(() {
          _audioReady = false;
          _duration = Duration.zero;
          _position = Duration.zero;
        });
      }
      return;
    }

    final path = await _repo.getBackingTrackPath(track.fileName);
    if (path == null) {
      if (mounted) {
        setState(() {
          _audioReady = false;
          _duration = Duration.zero;
          _position = Duration.zero;
        });
      }
      if (mounted) {
        _showSnack('반주 파일을 찾을 수 없습니다. 곡을 다시 등록해 주세요.');
      }
      return;
    }

    try {
      await _player.stop();
      await _player.setSourceDeviceFile(path);
      await _player.setVolume(_settings.volume);
      if (mounted) {
        setState(() {
          _audioReady = true;
          _duration = Duration.zero; // updated via onDurationChanged stream
          _position = Duration.zero;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _audioReady = false;
          _duration = Duration.zero;
          _position = Duration.zero;
        });
      }
      if (mounted) {
        _showSnack('반주 파일을 재생할 수 없습니다: $e');
      }
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
      await _player.resume();
    }
  }

  Future<void> _stopPlayback() async {
    await _player.pause();
    await _player.seek(Duration.zero);
    if (mounted) setState(() => _position = Duration.zero);
  }

  Future<void> _restartPlayback() async {
    if (!_audioReady) {
      _showSnack('재생 가능한 반주가 없습니다.');
      return;
    }
    await _player.seek(Duration.zero);
    await _player.resume();
  }

  void _syncAutoScroll() {
    _autoScrollTimer?.cancel();
    if (!_playing ||
        _settings.speedLevel <= 0 ||
        !_lyricsScrollController.hasClients) {
      return;
    }

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
    if (_settings.fontFamily == '기본' ||
        _settings.fontFamily == 'System Default') {
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
            fontFamily: 'Malgun Gothic',
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
            fontFamily: 'Malgun Gothic',
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
            fontFamily: 'System Default',
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

  Future<String> _decodeLyricsFromBytes(List<int> bytes) async {
    try {
      return utf8.decode(bytes).trim();
    } catch (_) {
      // CP949가 아닌 환경에서도 깨짐을 줄이기 위한 최소 fallback
      return latin1.decode(bytes).trim();
    }
  }

  Song? _findSongByTitle(String title, {String? excludeId}) {
    final normalized = title.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final song in _songs) {
      if (song.id == excludeId) continue;
      if (song.title.trim().toLowerCase() == normalized) {
        return song;
      }
    }
    return null;
  }

  Future<void> _addSong() async {
    final lyricsFile = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
      dialogTitle: '가사 파일(txt) 선택',
      withData: kIsWeb,
    );
    if (lyricsFile == null || lyricsFile.files.isEmpty) return;

    final picked = lyricsFile.files.first;
    final ext = picked.extension?.toLowerCase() ?? '';
    if (ext != 'txt') {
      _showSnack('txt 파일만 선택할 수 있습니다.');
      return;
    }

    List<int>? bytes = picked.bytes;
    if (bytes == null && picked.path != null) {
      try {
        bytes = await File(picked.path!).readAsBytes();
      } catch (_) {}
    }
    if (bytes == null) {
      _showSnack('가사 파일 내용을 읽을 수 없습니다.');
      return;
    }

    String lyrics;
    try {
      lyrics = await _decodeLyricsFromBytes(bytes);
    } catch (_) {
      _showSnack('가사 파일 읽기에 실패했습니다.');
      return;
    }

    final draft = await _showSongCreateDialog(picked.name);
    if (draft == null) return;
    if (_findSongByTitle(draft.title) != null) {
      _showSnack('같은 제목의 곡이 이미 있습니다. 제목을 바꿔 주세요.');
      return;
    }

    final id = const Uuid().v4();
    try {
      final song = await _repo.addSong(
        id: id,
        title: draft.title,
        lyrics: lyrics,
        sourceTrackPaths: kIsWeb ? null : draft.trackPaths,
      );

      final nextSongs = List<Song>.from(_songs)..add(song);
      await _repo.saveSongs(nextSongs);

      if (!mounted) return;
      setState(() => _songs = nextSongs);
      await _loadSong(song);
      _showSnack('곡이 추가되었습니다.');
      if (kIsWeb && draft.trackPaths.isNotEmpty) {
        _showSnack('웹에서는 반주 파일 첨부가 제외되고 가사만 등록됩니다.');
      }
    } catch (_) {
      _showSnack('곡 추가 중 오류가 발생했습니다.');
    }
  }

  Future<void> _editSong(Song song) async {
    final draft = await _showSongEditDialog(song);
    if (draft == null) return;
    if (_findSongByTitle(draft.title, excludeId: song.id) != null) {
      _showSnack('같은 제목의 곡이 이미 있습니다. 제목을 바꿔 주세요.');
      return;
    }

    try {
      final updatedSong = await _repo.updateSong(
        song: song,
        title: draft.title,
        lyrics: draft.lyricsText,
        sourceTrackPaths: kIsWeb ? null : draft.trackPaths,
      );

      final nextSongs = _songs
          .map((item) => item.id == song.id ? updatedSong : item)
          .toList(growable: false);
      await _repo.saveSongs(nextSongs);

      if (!mounted) return;
      setState(() {
        _songs = nextSongs;
        if (_selectedSong?.id == song.id) {
          _selectedSong = updatedSong;
        }
      });

      if (_selectedSong?.id == song.id) {
        await _loadSong(updatedSong, preferredSlot: _selectedTrackSlot);
      }
      _showSnack('곡 정보가 수정되었습니다.');
    } catch (_) {
      _showSnack('곡 수정 중 오류가 발생했습니다.');
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
                if (kIsWeb) {
                  _showSnack('웹에서는 로컬 반주 파일 첨부를 지원하지 않습니다.');
                } else {
                  _showSnack('반주 파일 경로를 읽을 수 없습니다.');
                }
                return;
              }
              setLocal(() => trackPaths[slot] = path);
            }

            final maxWidth = MediaQuery.of(ctx).size.width;
            final dialogWidth = (maxWidth * 0.86).clamp(620.0, 920.0);

            return AlertDialog(
              backgroundColor: AppColors.elevated,
              title: const Text(
                '곡 등록 (가사1 + 반주1~3)',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              content: SizedBox(
                width: dialogWidth,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: titleController,
                        autofocus: true,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                        ),
                        decoration: const InputDecoration(
                          labelText: '곡 제목',
                          labelStyle: TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 98,
                              child: Text(
                                '가사1 (txt)',
                                style: TextStyle(color: AppColors.textPrimary),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '반주 (선택: 0~3개)',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final slot in [1, 2, 3])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 98,
                                  child: Text(
                                    '반주$slot (mp3)',
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
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
                                const SizedBox(width: 10),
                                ElevatedButton(
                                  onPressed: () => pickTrack(slot),
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(88, 42),
                                  ),
                                  child: const Text('선택'),
                                ),
                                const SizedBox(width: 6),
                                TextButton(
                                  onPressed: () =>
                                      setLocal(() => trackPaths[slot] = null),
                                  child: const Text('취소'),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('닫기'),
                ),
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
                    Navigator.pop(
                      ctx,
                      _SongDraft(title: title, trackPaths: normalized),
                    );
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

  Future<_SongEditDraft?> _showSongEditDialog(Song song) async {
    final titleController = TextEditingController(text: song.title);
    final trackPaths = <int, String?>{1: null, 2: null, 3: null};
    String? nextLyricsText;
    String? nextLyricsFileName;

    return showDialog<_SongEditDraft>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> pickLyrics() async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['txt'],
                dialogTitle: '새 가사 파일(txt) 선택',
                withData: kIsWeb,
              );
              if (result == null || result.files.isEmpty) return;

              final picked = result.files.first;
              if ((picked.extension ?? '').toLowerCase() != 'txt') {
                _showSnack('txt 파일만 선택할 수 있습니다.');
                return;
              }

              List<int>? bytes = picked.bytes;
              if (bytes == null && picked.path != null) {
                try {
                  bytes = await File(picked.path!).readAsBytes();
                } catch (_) {}
              }
              if (bytes == null) {
                _showSnack('가사 파일 내용을 읽을 수 없습니다.');
                return;
              }

              try {
                final decoded = await _decodeLyricsFromBytes(bytes);
                setLocal(() {
                  nextLyricsText = decoded;
                  nextLyricsFileName = picked.name;
                });
              } catch (_) {
                _showSnack('가사 파일 읽기에 실패했습니다.');
              }
            }

            Future<void> pickTrack(int slot) async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.audio,
                dialogTitle: '새 반주$slot 파일 선택',
              );
              if (result == null || result.files.isEmpty) return;
              final path = result.files.first.path;
              if (path == null) {
                if (kIsWeb) {
                  _showSnack('웹에서는 로컬 반주 파일 첨부를 지원하지 않습니다.');
                } else {
                  _showSnack('반주 파일 경로를 읽을 수 없습니다.');
                }
                return;
              }
              setLocal(() => trackPaths[slot] = path);
            }

            final maxWidth = MediaQuery.of(ctx).size.width;
            final dialogWidth = (maxWidth * 0.86).clamp(620.0, 920.0);

            return AlertDialog(
              backgroundColor: AppColors.elevated,
              title: const Text(
                '곡 수정',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              content: SizedBox(
                width: dialogWidth,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: titleController,
                        autofocus: true,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                        ),
                        decoration: const InputDecoration(
                          labelText: '곡 제목',
                          labelStyle: TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '가사 (txt)',
                              style: TextStyle(color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              nextLyricsFileName ?? '기존 파일 유지',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: nextLyricsFileName == null
                                    ? AppColors.textMuted
                                    : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                ElevatedButton(
                                  onPressed: pickLyrics,
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(88, 42),
                                  ),
                                  child: const Text('다시 선택'),
                                ),
                                const SizedBox(width: 6),
                                TextButton(
                                  onPressed: () {
                                    setLocal(() {
                                      nextLyricsText = null;
                                      nextLyricsFileName = null;
                                    });
                                  },
                                  child: const Text('유지'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '반주 교체 (선택: 0~3개)',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final slot in [1, 2, 3])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 98,
                                  child: Text(
                                    '반주$slot (mp3)',
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    trackPaths[slot] != null
                                        ? trackPaths[slot]!.split('\\').last
                                        : (song.trackForSlot(slot)?.fileName ??
                                              '없음'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: trackPaths[slot] == null
                                          ? AppColors.textMuted
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                ElevatedButton(
                                  onPressed: () => pickTrack(slot),
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(88, 42),
                                  ),
                                  child: const Text('교체'),
                                ),
                                const SizedBox(width: 6),
                                TextButton(
                                  onPressed: () =>
                                      setLocal(() => trackPaths[slot] = null),
                                  child: const Text('유지'),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('닫기'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final title = titleController.text.trim().isEmpty
                        ? song.title
                        : titleController.text.trim();
                    final normalized = <int, String>{};
                    trackPaths.forEach((slot, path) {
                      if (path != null && path.trim().isNotEmpty) {
                        normalized[slot] = path;
                      }
                    });
                    Navigator.pop(
                      ctx,
                      _SongEditDraft(
                        title: title,
                        lyricsText: nextLyricsText,
                        trackPaths: normalized,
                      ),
                    );
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
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

    final nextSongs = List<Song>.from(_songs)
      ..removeWhere((s) => s.id == song.id);
    final nextQueue = List<QueueItem>.from(_queue)
      ..removeWhere((q) => q.songId == song.id);

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
        : (song.availableTrackSlots.isNotEmpty
              ? song.availableTrackSlots.first
              : null);

    final nextQueue = List<QueueItem>.from(_queue)
      ..add(
        QueueItem(
          songId: song.id,
          selectedTrackSlot: slot,
          queuedAt: DateTime.now(),
        ),
      );

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

  Future<void> _clearQueue() async {
    await _repo.saveQueue(const []);
    if (!mounted) return;
    setState(() => _queue = []);
  }

  void _openPrompter(Song song) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrompterScreen(
          song: song,
          fontSize: _fontSizePt,
          lineHeight: _lineHeightVal,
          fontSizeLevel: _settings.fontSizeLevel,
          lineHeightLevel: _settings.lineHeightLevel,
          speedLevel: _settings.speedLevel,
          fontFamily: _resolvedFontFamily,
          boldText: _settings.boldText,
          autoScrollEnabled: _playing || !_audioReady,
          onFontSizeLevelChanged: (value) =>
              _updateSettings(_settings.copyWith(fontSizeLevel: value)),
          onLineHeightLevelChanged: (value) =>
              _updateSettings(_settings.copyWith(lineHeightLevel: value)),
          onSpeedLevelChanged: (value) =>
              _updateSettings(_settings.copyWith(speedLevel: value)),
        ),
      ),
    );
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
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  double get _queuePanelHeight {
    final rowCount = (_queue.length / 3).ceil().clamp(1, 99);
    return (rowCount * 92) + ((rowCount - 1) * 8);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
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
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(top: 8, right: 4),
        child: FloatingActionButton.extended(
          onPressed: _addSong,
          icon: const Icon(Icons.library_add, size: 18),
          label: const Text('곡 등록'),
          extendedPadding: const EdgeInsets.symmetric(horizontal: 14),
        ),
      ),
    );
  }

  Widget _buildSongListPanel() {
    if (_songs.isEmpty) {
      return Column(
        children: [
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.queue_music, size: 56, color: AppColors.border),
                  SizedBox(height: 14),
                  Text(
                    '등록된 곡이 없습니다',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '하단 버튼으로 곡을 추가해 주세요',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
          _buildSongListFooter(),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 124),
            itemCount: _songs.length,
            separatorBuilder: (_, index) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final song = _songs[i];
              final selected = _selectedSong?.id == song.id;
              return _SongTile(
                song: song,
                selected: selected,
                selectedTrackSlot: selected ? _selectedTrackSlot : null,
                onSelectTrack: _selectTrackSlot,
                onSelect: () => _loadSong(song),
                onPlayNow: () async {
                  await _loadSong(song);
                  await _togglePlayPause();
                },
                onReserve: () => _reserveSong(song),
                onEdit: () => _editSong(song),
                onDelete: () => _deleteSong(song),
              );
            },
          ),
        ),
        _buildSongListFooter(),
      ],
    );
  }

  Widget _buildSongListFooter() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Text(
        'Copyright SVIL. Powered by 디또 2026/03/10',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.2),
      ),
    );
  }

  Widget _buildPrompterPanel() {
    final song = _selectedSong;
    if (song == null) {
      return const Center(
        child: Text(
          '곡을 선택해 주세요',
          style: TextStyle(color: AppColors.textMuted, fontSize: 18),
        ),
      );
    }

    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
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
                    fontWeight: _settings.boldText
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          _buildBottomBar(song),
          if (_queue.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: _buildQueuePanel(),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildBottomBar(Song song) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1번 줄: 재생 버튼 + 프로그레스 바 + 볼륨
          Row(
            children: [
              _CompactBtn(
                icon: Icons.stop,
                onTap: () {
                  _stopPlayback();
                },
              ),
              const SizedBox(width: 4),
              _CompactBtn(
                icon: _playing ? Icons.pause : Icons.play_arrow,
                onTap: () {
                  _togglePlayPause();
                },
                highlighted: true,
              ),
              const SizedBox(width: 4),
              _CompactBtn(
                icon: Icons.replay,
                onTap: () {
                  _restartPlayback();
                },
              ),
              const SizedBox(width: 4),
              _CompactBtn(
                icon: Icons.fullscreen,
                onTap: () => _openPrompter(song),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(_position),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 10,
                    ),
                  ),
                  child: Slider(
                    min: 0,
                    max: _duration.inMilliseconds.toDouble().clamp(
                      1,
                      double.infinity,
                    ),
                    value: _position.inMilliseconds.toDouble().clamp(
                      0,
                      _duration.inMilliseconds.toDouble().clamp(
                        1,
                        double.infinity,
                      ),
                    ),
                    onChanged: _audioReady
                        ? (v) => _player.seek(Duration(milliseconds: v.toInt()))
                        : null,
                  ),
                ),
              ),
              Text(
                _formatDuration(_duration),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.volume_up, size: 14, color: AppColors.textMuted),
              SizedBox(
                width: 72,
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 10,
                    ),
                  ),
                  child: Slider(
                    min: 0,
                    max: 1,
                    value: _settings.volume,
                    onChanged: (v) =>
                        _updateSettings(_settings.copyWith(volume: v)),
                  ),
                ),
              ),
            ],
          ),
          // 2번 줄: 슬라이더 + 스타일 옵션
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _MiniSlider(
                  label: '크기',
                  value: _settings.fontSizeLevel,
                  min: 1,
                  max: 5,
                  divisions: 4,
                  onChanged: (v) =>
                      _updateSettings(_settings.copyWith(fontSizeLevel: v)),
                ),
              ),
              Expanded(
                child: _MiniSlider(
                  label: '줄간격',
                  value: _settings.lineHeightLevel,
                  min: 1,
                  max: 5,
                  divisions: 4,
                  onChanged: (v) =>
                      _updateSettings(_settings.copyWith(lineHeightLevel: v)),
                ),
              ),
              Expanded(
                child: _MiniSlider(
                  label: '속도',
                  value: _settings.speedLevel,
                  min: 0,
                  max: 10,
                  divisions: 20,
                  onChanged: (v) =>
                      _updateSettings(_settings.copyWith(speedLevel: v)),
                ),
              ),
              const SizedBox(width: 6),
              _PresetBtn(
                label: '표준',
                onTap: () => _applyAccessibilityPreset('standard'),
              ),
              const SizedBox(width: 4),
              _PresetBtn(
                label: '저시력',
                onTap: () => _applyAccessibilityPreset('recommended'),
              ),
              const SizedBox(width: 4),
              _PresetBtn(
                label: '원거리',
                onTap: () => _applyAccessibilityPreset('stage'),
              ),
              const SizedBox(width: 6),
              DropdownButton<String>(
                value: _fontOptions.containsKey(_settings.fontFamily)
                    ? _settings.fontFamily
                    : 'System Default',
                dropdownColor: AppColors.surface,
                isDense: true,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                ),
                items: _fontOptions.keys
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(growable: false),
                onChanged: (v) {
                  if (v == null) return;
                  _updateSettings(_settings.copyWith(fontFamily: v));
                },
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: _settings.boldText,
                  onChanged: (v) =>
                      _updateSettings(_settings.copyWith(boldText: v ?? false)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 3),
              const Text(
                '굵게',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQueuePanel() {
    final panelHeight = _queuePanelHeight;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _clearQueue,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 24),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('비우기', style: TextStyle(fontSize: 12)),
            ),
          ),
          /* Row(
            children: [
              const Text(
                '예약 큐',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _clearQueue,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('비우기', style: TextStyle(fontSize: 12)),
              ),
            ],
          ), */
          SizedBox(
            height: panelHeight.toDouble(),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _queue.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.6,
              ),
              itemBuilder: (_, i) {
                final item = _queue[i];
                Song? song;
                for (final s in _songs) {
                  if (s.id == item.songId) {
                    song = s;
                    break;
                  }
                }
                return Container(
                  key: ValueKey(
                    '${item.songId}_${item.queuedAt.toIso8601String()}_$i',
                  ),
                  padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                  decoration: BoxDecoration(
                    color: AppColors.elevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${i + 1}. ${song?.title ?? '(삭제된 곡)'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.selectedTrackSlot == null
                                  ? '가사'
                                  : 'MR${item.selectedTrackSlot}',
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _removeQueueItem(i),
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                        tooltip: '삭제',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                      ),
                    ],
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
  final int? selectedTrackSlot;
  final void Function(int slot)? onSelectTrack;
  final VoidCallback onSelect;
  final VoidCallback onPlayNow;
  final VoidCallback onReserve;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SongTile({
    required this.song,
    required this.selected,
    this.selectedTrackSlot,
    this.onSelectTrack,
    required this.onSelect,
    required this.onPlayNow,
    required this.onReserve,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF2A240A) : AppColors.elevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
              if (selected &&
                  song.backingTracks.isNotEmpty &&
                  onSelectTrack != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: song.backingTracks.map((track) {
                    final isSel = selectedTrackSlot == track.slot;
                    return OutlinedButton.icon(
                      onPressed: () => onSelectTrack!(track.slot),
                      icon: Icon(
                        isSel
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 14,
                      ),
                      label: Text('반주${track.slot}'),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: isSel
                            ? AppColors.accent
                            : AppColors.elevated,
                        foregroundColor: isSel
                            ? const Color(0xFF0A0A0A)
                            : AppColors.textPrimary,
                        side: BorderSide(
                          color: isSel ? AppColors.accent : AppColors.border,
                        ),
                        minimumSize: const Size(90, 38),
                        textStyle: const TextStyle(fontSize: 13),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _SmallActionButton(
                      label: '선택',
                      icon: Icons.check,
                      onTap: onSelect,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _SmallActionButton(
                      label: '재생',
                      icon: Icons.play_arrow,
                      onTap: onPlayNow,
                      primary: true,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _SmallActionButton(
                      label: '예약',
                      icon: Icons.schedule,
                      onTap: onReserve,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _SmallActionButton(
                      label: '수정',
                      icon: Icons.edit_outlined,
                      onTap: onEdit,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _SmallActionButton(
                      label: '삭제',
                      icon: Icons.delete_outline,
                      onTap: onDelete,
                    ),
                  ),
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
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: primary ? AppColors.accent : AppColors.border,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: primary ? const Color(0xFF0A0A0A) : AppColors.textPrimary,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: TextStyle(
                color: primary
                    ? const Color(0xFF0A0A0A)
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool highlighted;

  const _CompactBtn({
    required this.icon,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: highlighted ? AppColors.accent : AppColors.elevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: highlighted ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: highlighted ? const Color(0xFF0A0A0A) : AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _MiniSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  const _MiniSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
          ),
          child: Slider(
            min: min,
            max: max,
            divisions: divisions,
            value: value,
            onChanged: onChanged,
          ),
        ),
      ],
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

class _SongEditDraft {
  final String title;
  final String? lyricsText;
  final Map<int, String> trackPaths;

  const _SongEditDraft({
    required this.title,
    required this.lyricsText,
    required this.trackPaths,
  });
}
