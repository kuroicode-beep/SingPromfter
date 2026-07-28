import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter/material.dart';

import '../controllers/import_job_controller.dart';
import '../controllers/playback_controller.dart';
import '../controllers/recording_controller.dart';
import '../coordinators/song_action_coordinator.dart';
import '../dialogs/add_song_dialog.dart';
import '../dialogs/custom_font_size_dialog.dart';
import '../models/app_destination.dart';
import '../models/mr_source_mode.dart';
import '../models/prompter_display_mode.dart';
import '../models/prompter_settings.dart';
import '../models/queue_item.dart';
import '../models/recording_take.dart';
import '../models/song.dart';
import '../models/song_draft.dart';
import '../utils/key_label.dart';
import '../utils/pitch_math.dart';
import '../navigation/prompter_navigation.dart';
import '../repository/song_repository.dart';
import '../services/backup_service.dart';
import '../services/lyrics_sync_service.dart';
import '../services/pitch_variant_service.dart';
import '../services/practice_log_service.dart';
import '../services/daily_goal_service.dart';
import '../services/recording_library_service.dart';
import '../services/process/external_tool_locator.dart';
import '../services/process/process_runner.dart';
import '../services/process/tool_progress_parsers.dart';
import '../services/youtube_import_service.dart';
import '../services/prompter_audio_service.dart';
import '../services/prompter_settings_service.dart';
import '../services/song_library_service.dart';
import '../services/song_list_bootstrap_service.dart';
import '../services/song_queue_service.dart';
import '../services/library_maintenance_service.dart';
import '../services/song_filter_service.dart';
import '../services/song_sort_service.dart';
import '../services/take_mix_service.dart';
import '../services/vocal_separation_client.dart';
import '../widgets/song_list_screen_content.dart';
import '../theme/app_theme.dart';
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
  late final _songActions = SongActionCoordinator(_repo, _libraryService);
  late final _audio = PrompterAudioService(_repo);
  final _lyricsScrollController = ScrollController();
  final _practiceLog = PracticeLogService();
  final _lyricsSync = LyricsSyncService();
  late final _pitchVariants = PitchVariantService(locator: _toolLocator);
  final _toolLocator = ExternalToolLocator();
  late final _youtubeImport = YoutubeImportService(
    tmpDirProvider: _repo.getTmpDir,
    locator: _toolLocator,
  );
  late final ImportJobController _importJobs;
  final _recordingLibrary = RecordingLibraryService();
  final _dailyGoals = DailyGoalService();
  late final RecordingController _recording;
  late final _takePlayer = PrompterAudioService(_repo);
  AudioBindings? _takeBindings;

  String _recordingQuery = '';
  RecordingFilterMode _recordingFilterMode = RecordingFilterMode.all;
  String? _playingTakeId;
  Song? _recordingSong;
  int? _recordingSlot;
  int _recordingPitch = 0;
  int _recordingAlignMs = 0;

  bool _ytDlpAvailable = false;
  String? _ytDlpMissingReason;
  String? _ytDlpVersion;
  final _separation = VocalSeparationClient();
  String _separatorStatusLabel = '분리 서버: 확인 중';
  bool _separatorOnline = false;
  static const _kYtNoticeAckKey = 'yt_notice_ack';

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
  SongSortMode _listSortMode = SongSortMode.title;

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
      pitchVariantResolver: _resolvePitchVariant,
      onPracticeSessionEnded: (snapshot, played) {
        unawaited(_recordPractice(snapshot, played));
      },
    )..init();
    // 재생 상태(저빈도)만 화면 재빌드에 연결한다. 위치(60Hz)는 구독 위젯이 직접 받는다.
    _playback.state.addListener(_onPlaybackStateChanged);
    _playback.lineIndex.addListener(_onPlaybackStateChanged);
    _importJobs = ImportJobController(runner: _runImportJob)
      ..addListener(_onPlaybackStateChanged);
    _recording = RecordingController(
      pathBuilder: _buildRecordingPath,
    )..addListener(_onPlaybackStateChanged);
    // 아웃트로를 부르는 중에 다음 곡으로 넘어가지 않도록 막는다.
    _playback.isRecordingProvider = () => _recording.isRecording;
    // 테이크 재생이 끝나면 '정지' 버튼이 '듣기'로 돌아오게 한다.
    _takeBindings = _takePlayer.bind(
      onPlayingChanged: (playing) {
        if (!playing && _playingTakeId != null && mounted) {
          setState(() => _playingTakeId = null);
        }
      },
      onPositionChanged: (_) {},
      onDurationChanged: (_) {},
      onCompleted: () async {},
    );
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
    _recording.dispose();
    _takeBindings?.cancel();
    _takePlayer.dispose();
    _playback.dispose();
    _audio.dispose();
    _lyricsScrollController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final initial = await _bootstrapService.load();
    await _practiceLog.load();
    await _recordingLibrary.load();
    await _dailyGoals.load();

    if (!mounted) return;
    setState(() {
      _songs = initial.songs;
      _queue = initial.queue;
      _settings = initial.settings;
      _loading = false;
    });

    unawaited(_refreshToolAvailability());

    final schemaError = _repo.schemaLoadError;
    if (schemaError != null) _showSnack(schemaError);

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

  // ── 녹음 믹스다운 ───────────────────────────────────────

  Future<void> _mixTake(RecordingTake take) async {
    final songMatches = _songs.where((s) => s.id == take.songId).toList();
    final song = songMatches.isEmpty ? null : songMatches.first;
    final slot = take.backingTrackSlot;
    final track = (song != null && slot != null)
        ? song.trackForSlot(slot)
        : null;
    if (track == null) {
      _showSnack('이 녹음의 반주를 찾을 수 없어 합칠 수 없습니다.');
      return;
    }
    final backingPath = await _repo.getBackingTrackPath(track.fileName);
    if (backingPath == null) {
      _showSnack('반주 파일이 없습니다.');
      return;
    }

    _showSnack('반주와 합치는 중...');
    final vocalPath = await _recordingLibrary.pathFor(take);
    final mixedName = '${take.id}_mix.m4a';
    final outputPath =
        '${(await _recordingLibrary.directory()).path}/$mixedName';
    final result = await TakeMixService().mix(
      backingPath: backingPath,
      vocalPath: vocalPath,
      outputPath: outputPath,
      alignMs: take.alignOffsetMs,
    );
    if (!mounted) return;
    if (!result.success) {
      _showSnack(result.message ?? '합치기에 실패했습니다.');
      return;
    }
    await _recordingLibrary.update(take.copyWith(mixedFileName: mixedName));
    if (!mounted) return;
    setState(() {});
    _showSnack('합쳤습니다. "합친 곡 듣기"로 확인해 보세요.');
  }

  Future<void> _playTakeMix(RecordingTake take) async {
    final mixed = take.mixedFileName;
    if (mixed == null || mixed.isEmpty) return;
    final path =
        '${(await _recordingLibrary.directory()).path}/$mixed';
    final ok = await _takePlayer.playFile(path);
    if (!mounted) return;
    if (!ok) {
      _showSnack('합친 파일을 재생할 수 없습니다.');
      return;
    }
    setState(() => _playingTakeId = take.id);
  }

  // ── 수동 .lrc 가져오기 ──────────────────────────────────

  Future<void> _importLrcFile() async {
    final song = _selectedSong;
    if (song == null) {
      _showSnack('먼저 곡을 선택해 주세요.');
      return;
    }
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '.lrc 싱크 가사 파일 선택',
      type: FileType.custom,
      allowedExtensions: ['lrc', 'txt'],
    );
    final path = picked?.files.firstOrNull?.path;
    if (path == null) return;

    final String content;
    try {
      content = await File(path).readAsString();
    } catch (e) {
      _showSnack('파일을 읽을 수 없습니다: $e');
      return;
    }

    final updated = await _lyricsSync.save(song, content);
    if (!mounted) return;
    if (updated == null) {
      _showSnack('싱크 가사를 해석하지 못했습니다. [mm:ss.xx] 형식인지 확인해 주세요.');
      return;
    }
    setState(() {
      _songs = _songs
          .map((s) => s.id == updated.id ? updated : s)
          .toList(growable: false);
    });
    await _repo.saveSongs(_songs);
    _playback.timedLyrics.value = await _lyricsSync.loadFor(updated);
    await _updateSettings(
      _settings.copyWith(displayMode: PrompterDisplayMode.timed),
    );
    if (!mounted) return;
    _showSnack('싱크 가사를 등록했습니다.');
  }

  // ── 라이브러리 정리 ─────────────────────────────────────

  Future<void> _runMaintenance() async {
    final maintenance = LibraryMaintenanceService(_repo);
    final audit = await maintenance.audit(_songs);
    if (!mounted) return;

    if (audit.isClean) {
      _showSnack('정리할 항목이 없습니다.');
      return;
    }

    final lines = <String>[
      if (audit.orphanCount > 0) '사용하지 않는 파일 ${audit.orphanCount}개',
      if (audit.songsWithMissingTracks.isNotEmpty)
        '파일이 없는 곡 ${audit.songsWithMissingTracks.length}개',
      if (audit.duplicateTitleGroups.isNotEmpty)
        '제목이 겹치는 묶음 ${audit.duplicateTitleGroups.length}개',
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('라이브러리 정리'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...lines.map((l) => Text(l, style: AppTypography.body)),
            const SizedBox(height: 12),
            Text(
              audit.orphanCount > 0
                  ? '사용하지 않는 파일만 삭제합니다. 곡 목록은 그대로 둡니다.'
                  : '삭제할 파일은 없습니다. 위 항목은 직접 확인해 주세요.',
              style: AppTypography.bodyMuted,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('닫기'),
          ),
          if (audit.orphanCount > 0)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('정리'),
            ),
        ],
      ),
    );
    if (confirmed != true) return;

    final deleted = await maintenance.deleteOrphans(audit);
    final temp = await maintenance.clearTempFiles();
    final cache = await maintenance.clearPitchCache();
    if (!mounted) return;
    _showSnack('파일 $deleted개, 임시 항목 $temp개, 변환 캐시 $cache개를 정리했습니다.');
  }

  // ── 트레이닝 ────────────────────────────────────────────

  /// 연습을 기록하고, 목표곡·루틴곡 단계를 자동으로 체크한다.
  Future<void> _recordPractice(
    PlaybackSnapshot snapshot,
    Duration played,
  ) async {
    await _practiceLog.record(snapshot: snapshot, played: played);
    if (!PracticeSessionRules.shouldRecord(played)) return;

    // 실제로 부른 곡만 인정되도록 재생 기록에서 자동 체크한다.
    // 루틴곡이 이미 완료면 목표곡을 채운다.
    await _dailyGoals.autoCompleteNextSongStep();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _changeRoutine(String routineId) async {
    await _dailyGoals.changeRoutine(_dailyGoals.today(), routineId);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _toggleRoutineStep(String stepId) async {
    await _dailyGoals.toggleStep(_dailyGoals.today(), stepId);
    if (!mounted) return;
    setState(() {});
  }

  // ── 녹음 ────────────────────────────────────────────────

  Future<String> _buildRecordingPath(String fileName) async {
    final dir = await _recordingLibrary.directory();
    return '${dir.path}/$fileName';
  }

  Future<void> _skipToNext() async {
    if (_recording.isRecording) {
      _showSnack('녹음 중에는 다음 곡으로 넘어가지 않습니다. 녹음을 먼저 정지해 주세요.');
      return;
    }
    await _playback.onSongCompleted();
  }

  Future<void> _toggleRecording() async {
    if (_recording.isRecording) {
      await _finishRecording();
      return;
    }

    final song = _selectedSong;
    if (song == null) {
      _showSnack('먼저 곡을 선택해 주세요.');
      return;
    }
    if (!await _recording.isAvailable()) {
      if (!mounted) return;
      _showSnack('녹음 장치를 찾지 못했습니다. 마이크 연결과 ffmpeg 설치를 확인해 주세요.');
      return;
    }

    final id = const Uuid().v4();
    final started = await _recording.start('$id.wav');
    if (started == null) {
      if (mounted) _showSnack('녹음을 시작하지 못했습니다. 입력 장치를 확인해 주세요.');
      return;
    }

    _recordingSong = song;
    _recordingSlot = _selectedTrackSlot;
    _recordingPitch = _settings.pitchForSong(song.id, _selectedTrackSlot);
    // 반주와 합칠 때 쓸 정렬점 — 녹음 시작 순간의 재생 위치.
    _recordingAlignMs = _playback.position.value.inMilliseconds;
    if (!mounted) return;
    _showSnack('녹음을 시작했습니다. 스피커로 들으면 반주가 섞이니 헤드폰을 권장합니다.');
  }

  Future<void> _finishRecording() async {
    final result = await _recording.stop();
    final song = _recordingSong;
    _recordingSong = null;
    if (result == null || song == null) return;

    // 너무 짧으면 실수로 누른 것으로 보고 파일까지 지운다.
    if (result.duration < const Duration(seconds: 3)) {
      await RecordingStore().deleteFile(result.fileName);
      if (mounted) _showSnack('녹음이 너무 짧아 저장하지 않았습니다.');
      return;
    }

    await _recordingLibrary.add(
      RecordingTake(
        id: const Uuid().v4(),
        songId: song.id,
        songTitle: song.title,
        fileName: result.fileName,
        recordedAt: DateTime.now(),
        durationMs: result.duration.inMilliseconds,
        backingTrackSlot: _recordingSlot,
        pitchSemitones: _recordingPitch,
        alignOffsetMs: _recordingAlignMs,
      ),
    );
    if (!mounted) return;
    setState(() {});
    _showSnack('녹음을 저장했습니다. 녹음 탭에서 들어볼 수 있어요.');
  }

  Future<void> _playTake(RecordingTake take) async {
    final path = await _recordingLibrary.pathFor(take);
    final ok = await _takePlayer.playFile(path);
    if (!mounted) return;
    if (!ok) {
      _showSnack('녹음 파일을 재생할 수 없습니다.');
      return;
    }
    setState(() => _playingTakeId = take.id);
  }

  Future<void> _stopTake(RecordingTake take) async {
    await _takePlayer.stop();
    if (!mounted) return;
    setState(() => _playingTakeId = null);
  }

  Future<void> _editTakeComment(RecordingTake take) async {
    final controller = TextEditingController(text: take.comment);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('코멘트'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          style: AppTypography.body,
          decoration: const InputDecoration(
            hintText: '이번 녹음에서 느낀 점을 적어 두세요',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == null) return;
    await _recordingLibrary.update(take.copyWith(comment: saved));
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _rateTake(RecordingTake take, int rating) async {
    await _recordingLibrary.update(take.copyWith(rating: rating));
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _toggleTakeKeep(RecordingTake take) async {
    await _recordingLibrary.update(take.copyWith(isKeep: !take.isKeep));
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _deleteTake(RecordingTake take) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('녹음 삭제'),
        content: Text('${take.songTitle} 녹음을 삭제할까요? 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _recordingLibrary.remove(take);
    if (!mounted) return;
    setState(() {});
  }

  // ── 키(피치) 조절 ───────────────────────────────────────

  /// 키를 바꾼 반주를 준비한다. 처음 쓰는 키는 여기서 렌더링된다.
  Future<String?> _resolvePitchVariant(Song song, int slot, int semitones) async {
    final track = song.trackForSlot(slot);
    if (track == null) return null;
    final sourcePath = await _repo.getBackingTrackPath(track.fileName);
    if (sourcePath == null) return null;

    final cached = await _pitchVariants.cachedPath(
      sourceFileName: track.fileName,
      semitones: semitones,
    );
    if (cached != null) return cached;

    if (mounted) _showSnack('${formatKeyLabel(semitones)} 반주를 준비하는 중...');
    final result = await _pitchVariants.render(
      sourcePath: sourcePath,
      sourceFileName: track.fileName,
      semitones: semitones,
      total: _playback.snapshot.duration,
    );
    if (!result.success) {
      if (mounted) _showSnack(result.message ?? '키 변경에 실패했습니다.');
      return null;
    }
    return result.path;
  }

  Future<void> _adjustPitch(int delta) async {
    final song = _selectedSong;
    final slot = _selectedTrackSlot;
    if (song == null || slot == null) {
      _showSnack('먼저 곡과 반주를 선택해 주세요.');
      return;
    }
    final current = _settings.pitchForSong(song.id, slot);
    final next = clampSemitones(current + delta);
    if (next == current) return;

    await _updateSettings(_settings.withSongPitch(song.id, slot, next));
    // 새 키로 다시 준비한다(필요하면 렌더링이 일어난다).
    await _playback.prepareAudioForSelection();
    if (!mounted) return;
    _showSnack('키: ${formatKeyLabel(next)}');
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

      // 결정 사항: 싱크 가사는 기본으로 1초 먼저 띄워 읽을 시간을 준다.
      // 사용자가 이미 조절해 둔 값(0이 아님)은 건드리지 않는다.
      final slot = _selectedTrackSlot;
      final track = slot == null ? null : updated.trackForSlot(slot);
      if (track != null && track.lyricsOffsetMs == 0) {
        await _adjustLyricsOffset(-1000);
      }
    }
    if (!mounted) return;
    _showSnack(outcome.message);
  }

  /// 곡별 가사 선행/지연 오프셋을 바꾼다. 음수면 가사가 먼저 나온다.
  Future<void> _adjustLyricsOffset(int deltaMs) async {
    final snapshotSong = _selectedSong;
    final slot = _selectedTrackSlot;
    if (snapshotSong == null || slot == null) return;
    // 재생 스냅샷의 곡은 오래됐을 수 있다(예: 방금 받은 lrcFileName 누락).
    // 목록의 최신 인스턴스를 기준으로 수정해 다른 필드를 잃지 않는다.
    final song = _songs.firstWhere(
      (s) => s.id == snapshotSong.id,
      orElse: () => snapshotSong,
    );
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
    final separator = await _separation.status();
    if (!mounted) return;
    setState(() {
      _ytDlpAvailable = tool.found;
      _ytDlpVersion = tool.version;
      _ytDlpMissingReason = tool.found
          ? null
          : 'yt-dlp를 찾을 수 없습니다. 설치했다면 실행 파일 경로를 직접 지정해 주세요.';
      _separatorStatusLabel = separator.label;
      _separatorOnline = separator.online;
    });
  }

  Future<void> _updateYtDlp() async {
    final tool = await _toolLocator.locate(ExternalTool.ytDlp);
    if (!tool.found) {
      _showSnack('yt-dlp를 찾을 수 없습니다.');
      return;
    }
    _showSnack('yt-dlp 업데이트를 확인하는 중...');
    final result = await const SystemProcessRunner().run(tool.path!, ['-U']);
    if (!mounted) return;
    final output = (result.stdout + result.stderr).trim();
    final lastLine = output.isEmpty
        ? (result.ok ? '완료' : '실패')
        : output.split(RegExp(r'\r?\n')).last;
    _showSnack('yt-dlp: $lastLine');
    await _refreshToolAvailability();
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

  Future<void> _startYoutubeImport(
    String url,
    MrSourceMode mode, {
    bool fetchLyrics = true,
  }) async {
    if (!looksLikeYoutubeUrl(url)) {
      _showSnack('유튜브 주소가 아닙니다. 링크를 다시 확인해 주세요.');
      return;
    }
    if (!await _confirmYoutubeNotice()) return;
    _importJobs.enqueue(
      url: url,
      mode: mode,
      id: const Uuid().v4(),
      fetchLyrics: fetchLyrics,
    );
    if (!mounted) return;
    _showSnack('가져오는 중입니다. 진행 상황은 홈 위쪽에 표시됩니다.');
  }

  /// 저작권 방침: 최초 사용 시 1회 확인을 받는다. 이후에는 상시 문구만 보인다.
  Future<bool> _confirmYoutubeNotice() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kYtNoticeAckKey) ?? false) return true;
    if (!mounted) return false;

    final agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('사용 전 확인'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('개인이 저작권을 소유한 링크만 사용해야 합니다.',
                style: AppTypography.body),
            const SizedBox(height: 8),
            Text('개인적 용도의 사용에 대한 책임은 사용자 본인에게 있습니다.',
                style: AppTypography.body),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('확인했습니다'),
          ),
        ],
      ),
    );
    if (agreed == true) {
      await prefs.setBool(_kYtNoticeAckKey, true);
      return true;
    }
    return false;
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

    var audioPath = result.audioPath!;
    if (job.mode == MrSourceMode.aiSeparate) {
      onProgress(const JobProgress(label: 'AI 보컬 분리 중 (수십 초 걸립니다)'));
      final separated = await _separation.separate(audioPath);
      if (!separated.success || separated.instrumentalPath == null) {
        _failJob(job, separated.message ?? 'AI 보컬 분리에 실패했습니다.');
        await _youtubeImport.cleanupJob(job.id);
        return;
      }
      audioPath = separated.instrumentalPath!;
    }

    onProgress(const JobProgress(ratio: 1, label: '곡으로 등록 중'));
    var song = await _registerImportedSong(
      metadata: metadata,
      audioPath: audioPath,
    );
    await _youtubeImport.cleanupJob(job.id);

    if (song == null) {
      _failJob(job, '곡 등록에 실패했습니다.');
      return;
    }

    // 가사까지 한 흐름에서 붙인다. 실패해도 곡 자체는 남긴다.
    var lyricsNote = '';
    if (job.fetchLyrics) {
      onProgress(const JobProgress(ratio: 1, label: '가사 찾는 중'));
      final outcome = await _lyricsSync.fetchFor(
        song,
        duration: metadata.duration,
      );
      if (outcome.success && outcome.song != null) {
        song = outcome.song!;
        await _replaceSongInList(song);
        lyricsNote = ' · 가사 포함';
      } else {
        lyricsNote = ' · 가사는 찾지 못함';
      }
    }

    final finished = _importJobs.jobById(job.id);
    if (finished == null) return;
    _importJobs.update(
      finished.copyWith(
        status: ImportJobStatus.done,
        statusDetail: '재생목록에 추가했습니다$lyricsNote.',
        songId: song.id,
        ratio: 1,
      ),
    );
    if (!mounted) return;
    _showSnack('"${song.title}" 추가 완료$lyricsNote');
  }

  /// 목록의 곡을 최신 인스턴스로 갈아끼우고 저장한다.
  Future<void> _replaceSongInList(Song song) async {
    if (!mounted) return;
    setState(() {
      _songs = _songs
          .map((s) => s.id == song.id ? song : s)
          .toList(growable: false);
    });
    await _repo.saveSongs(_songs);
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
  /// 가사는 이어지는 단계에서 채운다. 실패하면 null.
  Future<Song?> _registerImportedSong({
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
      if (!mounted) return null;
      setState(() => _songs = result.songs);
      // 방금 추가된 곡을 돌려준다 — 가사 부착·선택에 이어 쓴다.
      final added = result.songs.where((s) => s.title == draft.title);
      return added.isEmpty ? null : added.last;
    } catch (e) {
      debugPrint('가져온 곡 등록 실패: $e');
      return null;
    }
  }

  /// 곡 추가의 유일한 경로 — 링크를 받아 가져오기 파이프라인에 넘긴다.
  Future<void> _addSong() async {
    // 최신 도구·서버 상태를 반영해 대화상자에서 바로 알려준다.
    unawaited(_refreshToolAvailability());
    final choice = await AddSongDialog.show(
      context,
      toolAvailable: _ytDlpAvailable,
      toolMissingReason: _ytDlpMissingReason,
      separatorStatusLabel: _separatorStatusLabel,
      separatorOnline: _separatorOnline,
    );
    if (choice == null) return;
    await _startYoutubeImport(
      choice.url,
      choice.mode,
      fetchLyrics: choice.fetchLyrics,
    );
  }

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
        ytDlpVersion: _ytDlpVersion,
        onUpdateYtDlp: _updateYtDlp,
        separatorStatusLabel: _separatorStatusLabel,
        onImportLrcFile: _importLrcFile,
        onMixTake: _mixTake,
        onPlayTakeMix: _playTakeMix,
        onFetchSyncedLyrics: _fetchSyncedLyrics,
        onAdjustLyricsOffset: _adjustLyricsOffset,
        pitchSemitones: _selectedSong == null
            ? 0
            : _settings.pitchForSong(_selectedSong!.id, _selectedTrackSlot),
        onAdjustPitch: _adjustPitch,
        isRecording: _recording.isRecording,
        recordingLevelLabel: _recording.levelLabel,
        recordingElapsed: _recording.elapsed,
        onToggleRecording: _toggleRecording,
        recordingTakes: RecordingFilter.apply(
          _recordingLibrary.takes,
          query: _recordingQuery,
          mode: _recordingFilterMode,
        ),
        recordingQuery: _recordingQuery,
        recordingFilterMode: _recordingFilterMode,
        playingTakeId: _playingTakeId,
        onRecordingQueryChanged: (v) => setState(() => _recordingQuery = v),
        onRecordingFilterModeChanged: (v) =>
            setState(() => _recordingFilterMode = v),
        onPlayTake: _playTake,
        onStopTake: _stopTake,
        onEditTakeComment: _editTakeComment,
        onRateTake: _rateTake,
        onToggleTakeKeep: _toggleTakeKeep,
        onDeleteTake: _deleteTake,
        todayGoal: _dailyGoals.today(),
        trainingStreak: _dailyGoals.streak(),
        trainingCompletedThisWeek: _dailyGoals.completedInLast(7),
        onRoutineChanged: _changeRoutine,
        onToggleRoutineStep: _toggleRoutineStep,
        lyricsScrollController: _lyricsScrollController,
        highlightLineIndex: _playback.lineIndex.value,
        searchQuery: _searchQuery,
        searchFilterMode: _searchFilterMode,
        listQuery: _listQuery,
        listFilterMode: _listFilterMode,
        onListQueryChanged: (value) => setState(() => _listQuery = value),
        onListFilterModeChanged: (value) =>
            setState(() => _listFilterMode = value),
        listSortMode: _listSortMode,
        onListSortModeChanged: (value) =>
            setState(() => _listSortMode = value),
        onRunMaintenance: _runMaintenance,
        onSearchQueryChanged: (value) => setState(() => _searchQuery = value),
        onSearchFilterModeChanged: (value) =>
            setState(() => _searchFilterMode = value),
        onAddSong: _addSong,
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
        onSkipNext: _skipToNext,
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
