import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../controllers/app_controller.dart';
import '../controllers/compose_job_controller.dart';
import '../controllers/import_job_controller.dart';
import '../controllers/playback_controller.dart';
import '../controllers/recording_controller.dart';
import '../coordinators/song_action_coordinator.dart';
import '../dialogs/add_song_dialog.dart';
import '../dialogs/add_track_dialog.dart';
import '../dialogs/custom_font_size_dialog.dart';
import '../dialogs/take_mix_dialog.dart';
import '../models/app_destination.dart';
import '../models/composition.dart';
import '../models/import_plan.dart';
import '../models/mr_source_mode.dart';
import '../models/prompter_display_mode.dart';
import '../models/prompter_settings.dart';
import '../models/queue_item.dart';
import '../models/recording_take.dart';
import '../models/song.dart';
import '../navigation/prompter_navigation.dart';
import '../repository/song_repository.dart';
import '../services/backup_service.dart';
import '../services/lyrics_sync_service.dart';
import '../services/practice_log_service.dart';
import '../services/daily_goal_service.dart';
import '../services/recording_library_service.dart';
import '../services/youtube_import_service.dart';
import '../services/prompter_audio_service.dart';
import '../services/prompter_settings_service.dart';
import '../services/song_library_service.dart';
import '../services/library_maintenance_service.dart';
import '../services/song_filter_service.dart';
import '../services/song_sort_service.dart';
import '../services/take_mix_service.dart';
import '../services/vocal_separation_client.dart';
import '../services/control_server.dart';
import '../utils/file_name_sanitizer.dart';
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
  /// 헤드리스 중심부 — 상태·서비스·가져오기 파이프라인·재생을 소유한다.
  /// 화면은 위임 getter로 기존 이름을 유지해 위젯 배선을 바꾸지 않는다.
  final _app = AppController();
  late final _controlServer = ControlServer(_app);

  SongRepository get _repo => _app.repo;
  SongLibraryService get _libraryService => _app.libraryService;
  late final _backupService = BackupService(_repo);
  late final _songActions = SongActionCoordinator(_repo, _libraryService);
  ScrollController get _lyricsScrollController => _app.lyricsScrollController;
  final _practiceLog = PracticeLogService();
  LyricsSyncService get _lyricsSync => _app.lyricsSync;
  ImportJobController get _importJobs => _app.importJobs;
  final _recordingLibrary = RecordingLibraryService();
  final _dailyGoals = DailyGoalService();
  late final RecordingController _recording;
  late final _takePlayer = PrompterAudioService(_repo);
  AudioBindings? _takeBindings;

  String _recordingQuery = '';
  RecordingFilterMode _recordingFilterMode = RecordingFilterMode.all;
  String? _playingTakeId;
  String? _playingCompositionId;
  Song? _recordingSong;
  int? _recordingSlot;
  int _recordingPitch = 0;
  int _recordingAlignMs = 0;
  // 녹음 당시 실제 재생 파일(변형본 포함)·템포 — 반주 조각을 자르는 데 쓴다.
  String? _recordingSourcePath;
  double _recordingTempo = 1.0;

  bool get _ytDlpAvailable => _app.ytDlpAvailable;
  String? get _ytDlpMissingReason => _app.ytDlpMissingReason;
  String? get _ytDlpVersion => _app.ytDlpVersion;
  String get _separatorStatusLabel => _app.separatorStatusLabel;
  bool get _separatorOnline => _app.separatorOnline;

  PlaybackController get _playback => _app.playback;

  final _pendingDeleteTimers = <String, Timer>{};

  List<Song> get _songs => _app.songs;
  set _songs(List<Song> value) => _app.songs = value;
  List<QueueItem> get _queue => _app.queue;
  set _queue(List<QueueItem> value) => _app.queue = value;
  PrompterSettings get _settings => _app.settings;
  bool get _loading => _app.loading;

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
    _app.onMessage = _showSnack;
    _app.onPracticeSessionEnded = (snapshot, played) {
      unawaited(_recordPractice(snapshot, played));
    };
    _app.addListener(_onPlaybackStateChanged);
    // 재생 상태(저빈도)만 화면 재빌드에 연결한다. 위치(60Hz)는 구독 위젯이 직접 받는다.
    _playback.state.addListener(_onPlaybackStateChanged);
    _playback.lineIndex.addListener(_onPlaybackStateChanged);
    _importJobs.addListener(_onPlaybackStateChanged);
    _recording = RecordingController(
      pathBuilder: _buildRecordingPath,
    )..addListener(_onPlaybackStateChanged);
    // 아웃트로를 부르는 중에 다음 곡으로 넘어가지 않도록 막는다.
    _playback.isRecordingProvider = () => _recording.isRecording;
    _app.composeJobs.addListener(_onPlaybackStateChanged);
    // 테이크·생성곡 재생이 끝나면 '정지' 버튼이 '듣기'로 돌아오게 한다.
    _takeBindings = _takePlayer.bind(
      onPlayingChanged: (playing) {
        if (!playing &&
            (_playingTakeId != null || _playingCompositionId != null) &&
            mounted) {
          setState(() {
            _playingTakeId = null;
            _playingCompositionId = null;
          });
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
    _importJobs.removeListener(_onPlaybackStateChanged);
    _app.composeJobs.removeListener(_onPlaybackStateChanged);
    _recording.dispose();
    _takeBindings?.cancel();
    _takePlayer.dispose();
    unawaited(_controlServer.stop());
    _app.removeListener(_onPlaybackStateChanged);
    _app.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    // 화면 전용 저장소(연습 로그·녹음·일일 목표)를 먼저 읽고 중심부를 깨운다.
    await _practiceLog.load();
    await _recordingLibrary.load();
    await _dailyGoals.load();
    await _app.bootstrap();
    // MCP 제어 API — 루프백 전용, 실패해도 앱 동작에 영향 없음.
    await _controlServer.start();
    // 설정 화면의 입력 장치 목록을 미리 채워 둔다(실패해도 무시).
    unawaited(_recording.refreshDevices());
  }

  Future<void> _loadSong(Song song, {int? preferredSlot}) =>
      _playback.loadSong(song, preferredSlot: preferredSlot);

  Future<void> _togglePlayPause() => _playback.togglePlayPause();

  Future<void> _stopPlayback() => _playback.stop();

  Future<void> _restartPlayback() => _playback.restart();

  Future<void> _applyAccessibilityPreset(String preset) =>
      _updateSettings(PrompterSettingsService.preset(_settings, preset));

  Future<void> _updateSettings(PrompterSettings next) async {
    await _app.updateSettings(next);
    // 로컬AI를 끄면 작곡 탭이 비활성화되므로 그 화면에 남지 않게 한다.
    if (!next.localAiEnabled &&
        _destination == AppDestination.compose &&
        mounted) {
      setState(() => _destination = AppDestination.home);
    }
  }

  Future<void> _showCustomFontSizeDialog() async {
    final next = await CustomFontSizeDialog.pickSettings(context, _settings);
    if (!mounted) return;
    if (next != null) await _updateSettings(next);
  }

  Future<void> _selectTrackSlot(int slot) => _app.selectTrackSlot(slot);

  // ── 녹음 믹스다운 ───────────────────────────────────────

  Future<void> _mixTake(RecordingTake take) async {
    // 반주 소스 우선순위: 잘라 둔 반주 조각(정렬 0, 키 일치 보장) →
    // 녹음 당시 재생 파일 → 원본 슬롯 파일(구 테이크 폴백).
    String? backingPath;
    var alignMs = take.alignOffsetMs;
    if (take.hasAccompaniment) {
      final accPath =
          '${(await _recordingLibrary.directory()).path}/${take.accompanimentFileName}';
      if (await File(accPath).exists()) {
        backingPath = accPath;
        alignMs = 0;
      }
    }
    if (backingPath == null &&
        take.sourceAudioPath != null &&
        await File(take.sourceAudioPath!).exists()) {
      backingPath = take.sourceAudioPath;
    }
    backingPath ??= await _backingPathForTake(take);
    if (backingPath == null) {
      _showSnack('이 녹음의 반주를 찾을 수 없어 합칠 수 없습니다.');
      return;
    }

    _showSnack('반주와 합치는 중...');
    // 분리 보컬이 있으면 그것을 쓴다(스피커 녹음 정리본).
    final vocalPath = take.hasSeparatedVocal
        ? '${(await _recordingLibrary.directory()).path}/${take.separatedFileName}'
        : await _recordingLibrary.pathFor(take);
    final mixedName = '${take.id}_mix.m4a';
    final outputPath =
        '${(await _recordingLibrary.directory()).path}/$mixedName';
    final result = await TakeMixService().mix(
      backingPath: backingPath,
      vocalPath: vocalPath,
      outputPath: outputPath,
      alignMs: alignMs,
      mixBalance: take.mixBalance,
      reverbPreset: take.reverbPreset,
      noiseReduction: take.noiseReduction,
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

  /// 믹스 설정 다이얼로그 — 밸런스·리버브·노이즈 제거·보컬 분리.
  Future<void> _showTakeMixSettings(RecordingTake take) async {
    final result = await TakeMixDialog.show(
      context,
      take: take,
      localAiEnabled: _settings.localAiEnabled,
    );
    if (result == null || !mounted) return;
    await _recordingLibrary.update(result.take);
    if (!mounted) return;
    setState(() {});
    if (result.separate) {
      await _separateTakeVocal(result.take);
    } else if (result.remix) {
      await _mixTake(result.take);
    } else {
      _showSnack('믹스 설정을 저장했습니다. "다시 합치기"에 반영됩니다.');
    }
  }

  /// 분리 서버(8771)로 테이크 보컬을 정리한다 — 스피커 녹음의 반주 제거용.
  Future<void> _separateTakeVocal(RecordingTake take) async {
    if (!_settings.localAiEnabled) {
      _showSnack('설정에서 로컬AI를 켜면 사용할 수 있습니다.');
      return;
    }
    _showSnack('보컬 분리 중... (수십 초 걸립니다)');
    final client = VocalSeparationClient();
    try {
      final vocalPath = await _recordingLibrary.pathFor(take);
      final result = await client.separate(vocalPath);
      if (!mounted) return;
      if (!result.success || result.vocalsPath == null) {
        _showSnack(result.message ?? '보컬 분리에 실패했습니다.');
        return;
      }
      final sepName = '${take.id}_sep.wav';
      final destPath =
          '${(await _recordingLibrary.directory()).path}/$sepName';
      await File(result.vocalsPath!).copy(destPath);
      await _recordingLibrary.update(
        take.copyWith(separatedFileName: sepName),
      );
      if (!mounted) return;
      setState(() {});
      _showSnack('보컬을 정리했습니다. 다시 합치면 정리본이 쓰입니다.');
    } catch (e) {
      if (mounted) _showSnack('보컬 분리 중 오류가 났습니다: $e');
    } finally {
      client.close();
    }
  }

  /// 설정 패널 — 입력 장치 새로고침.
  Future<void> _refreshRecordingDevices() async {
    final devices = await _recording.refreshDevices();
    if (!mounted) return;
    setState(() {});
    _showSnack(devices.isEmpty
        ? '입력 장치를 찾지 못했습니다. 마이크 연결과 ffmpeg 설치를 확인해 주세요.'
        : '입력 장치 ${devices.length}개를 찾았습니다.');
  }

  /// 설정 패널 — 마이크 테스트 토글.
  Future<void> _toggleMicTest() async {
    if (_recording.isRecording) {
      _showSnack('녹음 중에는 마이크 테스트를 할 수 없습니다.');
      return;
    }
    if (_recording.isProbing) {
      await _recording.stopLevelProbe();
      return;
    }
    if (_settings.recordingDeviceName != null) {
      _recording.deviceName = _settings.recordingDeviceName;
    }
    final ok = await _recording.startLevelProbe(
      gain: _settings.recordingGain,
    );
    if (!mounted) return;
    if (!ok) {
      _showSnack('마이크 테스트를 시작하지 못했습니다. 입력 장치를 확인해 주세요.');
    }
  }

  Future<void> _playTakeAccompaniment(RecordingTake take) async {
    final acc = take.accompanimentFileName;
    if (acc == null || acc.isEmpty) return;
    final path = '${(await _recordingLibrary.directory()).path}/$acc';
    final ok = await _takePlayer.playFile(path);
    if (!mounted) return;
    if (!ok) {
      _showSnack('반주 파일을 재생할 수 없습니다.');
      return;
    }
    setState(() => _playingTakeId = take.id);
  }

  /// 보컬·반주·믹스 3파일을 사용자가 고른 폴더로 복사한다.
  Future<void> _exportTake(RecordingTake take) async {
    final folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '저장할 폴더 선택',
    );
    if (folder == null) return;
    if (!mounted) return;

    // 믹스가 없으면 먼저 만든다(반주가 있을 때만).
    if (!take.hasMix && (take.hasAccompaniment || take.sourceAudioPath != null)) {
      await _mixTake(take);
    }
    // 믹스 생성으로 테이크가 갱신됐을 수 있으니 최신본을 다시 찾는다.
    final current = _recordingLibrary.takes
        .where((t) => t.id == take.id)
        .toList();
    final fresh = current.isEmpty ? take : current.first;

    final dir = (await _recordingLibrary.directory()).path;
    final stamp =
        '${fresh.recordedAt.year}${fresh.recordedAt.month.toString().padLeft(2, '0')}${fresh.recordedAt.day.toString().padLeft(2, '0')}'
        '_${fresh.recordedAt.hour.toString().padLeft(2, '0')}${fresh.recordedAt.minute.toString().padLeft(2, '0')}';
    final base = sanitizeFileName('${fresh.songTitle}_$stamp', fallback: '녹음');

    var copied = 0;
    Future<void> copyIfExists(String? fileName, String suffix) async {
      if (fileName == null || fileName.isEmpty) return;
      final src = File('$dir/$fileName');
      if (!await src.exists()) return;
      final ext = fileName.contains('.')
          ? fileName.substring(fileName.lastIndexOf('.'))
          : '';
      await src.copy('$folder/${base}_$suffix$ext');
      copied++;
    }

    try {
      await copyIfExists(fresh.fileName, '보컬');
      await copyIfExists(fresh.accompanimentFileName, '반주');
      await copyIfExists(fresh.mixedFileName, '믹스');
    } catch (e) {
      if (mounted) _showSnack('내보내기에 실패했습니다: $e');
      return;
    }
    if (!mounted) return;
    _showSnack(copied == 0
        ? '내보낼 파일이 없습니다.'
        : '$copied개 파일을 내보냈습니다: $folder');
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

  // ── 작곡 (v3.0.0) ───────────────────────────────────────

  Future<void> _composeGenerate(ComposeRequest request) async {
    final outcome = await _app.enqueueCompose(request);
    if (!mounted) return;
    _showSnack(
      outcome.ok
          ? '생성을 시작했습니다. 진행 상황은 작곡 탭에 표시됩니다.'
          : (outcome.message ?? '생성을 시작하지 못했습니다.'),
    );
  }

  /// 같은 조건으로 seed만 랜덤인 변주 여러 개를 묶음(batchId)으로 생성한다.
  Future<void> _composeVariations(ComposeRequest request, int count) async {
    final batchId = const Uuid().v4();
    var started = 0;
    for (var i = 1; i <= count; i++) {
      final outcome = await _app.enqueueCompose(
        request.copyWith(
          title: request.title.trim().isEmpty
              ? ''
              : '${request.title.trim()} (변주 $i)',
          seed: -1,
          batchId: batchId,
        ),
      );
      if (!outcome.ok) {
        if (mounted) _showSnack(outcome.message ?? '변주 생성을 시작하지 못했습니다.');
        break;
      }
      started++;
    }
    if (!mounted || started == 0) return;
    _showSnack('변주 $started개 생성을 시작했습니다. 차례로 만들어집니다.');
  }

  Future<String?> _polishPrompt(String korean) async {
    final result = await _app.ollama.polishStylePrompt(
      korean,
      model: _settings.ollamaModel,
    );
    if (!result.ok) {
      if (mounted) {
        _showSnack(
          '${result.message ?? '다듬기에 실패했습니다.'} 다듬기 없이 그대로 생성할 수도 있습니다.',
        );
      }
      return null;
    }
    return result.text;
  }

  Future<String?> _tagComposeLyrics(String lyrics) async {
    final result = await _app.ollama.tagLyrics(
      lyrics,
      model: _settings.ollamaModel,
    );
    if (!result.ok) {
      if (mounted) _showSnack(result.message ?? '가사 태깅에 실패했습니다.');
      return null;
    }
    return result.text;
  }

  Future<void> _playComposition(Composition item) async {
    final path = await _app.composeLibrary.pathFor(item);
    final ok = await _takePlayer.playFile(path);
    if (!mounted) return;
    if (!ok) {
      _showSnack('생성곡 파일을 재생할 수 없습니다.');
      return;
    }
    setState(() {
      _playingCompositionId = item.id;
      _playingTakeId = null;
    });
  }

  Future<void> _stopComposition(Composition item) async {
    await _takePlayer.stop();
    if (!mounted) return;
    setState(() => _playingCompositionId = null);
  }

  Future<void> _renameComposition(Composition item, String newTitle) async {
    await _app.composeLibrary.update(item.copyWith(title: newTitle));
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _registerComposition(
    Composition item, {
    bool karaokeSet = false,
  }) async {
    final song = await _app.registerCompositionAsSong(item.id);
    if (song == null || !mounted) return;
    setState(() {});
    if (karaokeSet) {
      await _app.makeKaraokeSetForComposition(item.id);
      if (!mounted) return;
      setState(() {});
    }
  }

  /// 생성 BGM을 기존 곡의 빈 슬롯에 반주로 넣는다.
  Future<void> _attachCompositionToSong(Composition item) async {
    // 빈 슬롯이 있는 곡만 후보로 보여준다.
    final candidates = _songs
        .where(
          (s) =>
              s.availableTrackSlots.length < AppConstants.backingTrackSlots.length,
        )
        .toList();
    if (candidates.isEmpty) {
      _showSnack('빈 반주 슬롯이 있는 곡이 없습니다.');
      return;
    }
    final picked = await showDialog<Song>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('반주를 넣을 곡 선택'),
        children: candidates
            .map(
              (s) => SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(s),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(s.title, style: AppTypography.body),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
    if (picked == null || !mounted) return;

    final usedSlots = picked.availableTrackSlots.toSet();
    final freeSlot = AppConstants.backingTrackSlots
        .firstWhere((s) => !usedSlots.contains(s), orElse: () => -1);
    if (freeSlot < 0) {
      _showSnack('이 곡에는 빈 슬롯이 없습니다.');
      return;
    }
    final path = await _app.composeLibrary.pathFor(item);
    final updated = await _app.attachTrackToSong(
      songId: picked.id,
      slot: freeSlot,
      sourcePath: path,
      label: 'AI BGM',
    );
    if (!mounted) return;
    _showSnack(
      updated == null
          ? '반주 넣기에 실패했습니다.'
          : '"${picked.title}"의 슬롯 $freeSlot에 반주로 넣었습니다.',
    );
  }

  Future<void> _exportComposition(Composition item) async {
    final ext = item.fileName.contains('.')
        ? item.fileName.substring(item.fileName.lastIndexOf('.'))
        : '.mp3';
    final target = await FilePicker.platform.saveFile(
      dialogTitle: '내보낼 위치 선택',
      fileName: '${sanitizeFileName(item.title, fallback: 'AI작곡')}$ext',
    );
    if (target == null || !mounted) return;
    try {
      await File(await _app.composeLibrary.pathFor(item)).copy(target);
      if (mounted) _showSnack('내보냈습니다: $target');
    } catch (e) {
      if (mounted) _showSnack('내보내기에 실패했습니다: $e');
    }
  }

  Future<void> _deleteComposition(Composition item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('생성곡 삭제'),
        content: Text(
          '"${item.title}"을(를) 삭제할까요? 오디오 파일도 함께 지워집니다.\n'
          '(곡으로 등록한 사본에는 영향이 없습니다)',
          style: AppTypography.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (_playingCompositionId == item.id) await _takePlayer.stop();
    await _app.composeLibrary.remove(item);
    if (!mounted) return;
    setState(() => _playingCompositionId = null);
    _showSnack('삭제했습니다.');
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
    await _app.replaceSongInList(updated);
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

    // 설정에서 고른 입력 장치·볼륨을 적용한다.
    if (_settings.recordingDeviceName != null) {
      _recording.deviceName = _settings.recordingDeviceName;
    }

    final id = const Uuid().v4();
    final started = await _recording.start(
      '$id.wav',
      gain: _settings.recordingGain,
    );
    if (started == null) {
      if (mounted) _showSnack('녹음을 시작하지 못했습니다. 입력 장치를 확인해 주세요.');
      return;
    }

    _recordingSong = song;
    _recordingSlot = _selectedTrackSlot;
    _recordingPitch = _settings.pitchForSong(song.id, _selectedTrackSlot);
    // 반주와 합칠 때 쓸 정렬점 — 녹음 시작 순간의 재생 위치.
    _recordingAlignMs = _playback.position.value.inMilliseconds;
    // 실제 재생 중인 파일(키/템포 변형본 포함) — 종료 직후 반주 조각을 자른다.
    _recordingSourcePath = _playback.snapshot.activeAudioPath;
    _recordingTempo = _playback.snapshot.tempoScale;
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

    final take = RecordingTake(
      id: const Uuid().v4(),
      songId: song.id,
      songTitle: song.title,
      fileName: result.fileName,
      recordedAt: DateTime.now(),
      durationMs: result.duration.inMilliseconds,
      backingTrackSlot: _recordingSlot,
      pitchSemitones: _recordingPitch,
      alignOffsetMs: _recordingAlignMs,
      sourceAudioPath: _recordingSourcePath,
      tempoScale: _recordingTempo,
    );
    await _recordingLibrary.add(take);
    if (!mounted) return;
    setState(() {});
    _showSnack('녹음을 저장했습니다. 녹음 탭에서 들어볼 수 있어요.');
    // 변형본 캐시가 지워지기 전에 즉시 반주 조각을 잘라 자립시킨다.
    // 실패해도 테이크는 남는다(녹음 탭에서 재시도 가능).
    unawaited(_cutAccompanimentForTake(take, silent: true));
  }

  /// 녹음 당시 반주에서 녹음 구간과 같은 조각을 잘라 테이크에 붙인다.
  Future<void> _cutAccompanimentForTake(
    RecordingTake take, {
    bool silent = false,
  }) async {
    // 소스 우선순위: 녹음 당시 실제 재생 파일 → 원본 슬롯 파일.
    String? sourcePath = take.sourceAudioPath;
    if (sourcePath == null || !await File(sourcePath).exists()) {
      final backing = await _backingPathForTake(take);
      sourcePath = backing;
    }
    if (sourcePath == null) {
      if (!silent && mounted) {
        _showSnack('녹음 당시 반주 파일을 찾을 수 없어 반주를 만들지 못했습니다.');
      }
      return;
    }

    final accName = '${take.id}_acc.m4a';
    final outputPath =
        '${(await _recordingLibrary.directory()).path}/$accName';
    final result = await TakeMixService().cutAccompaniment(
      sourcePath: sourcePath,
      outputPath: outputPath,
      startMs: take.alignOffsetMs,
      durationMs: take.durationMs,
    );
    if (!result.success) {
      if (!silent && mounted) {
        _showSnack(result.message ?? '반주 잘라내기에 실패했습니다.');
      }
      return;
    }
    await _recordingLibrary.update(
      take.copyWith(accompanimentFileName: accName),
    );
    if (!mounted) return;
    setState(() {});
    if (!silent) _showSnack('반주를 만들었습니다. "반주 듣기"로 확인해 보세요.');
  }

  /// 테이크의 원본 슬롯 반주 파일 경로(없으면 null).
  Future<String?> _backingPathForTake(RecordingTake take) async {
    final songMatches = _songs.where((s) => s.id == take.songId).toList();
    final song = songMatches.isEmpty ? null : songMatches.first;
    final slot = take.backingTrackSlot;
    final track = (song != null && slot != null)
        ? song.trackForSlot(slot)
        : null;
    if (track == null) return null;
    return _repo.getBackingTrackPath(track.fileName);
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

  Future<void> _adjustPitch(int delta) => _app.adjustPitch(delta);

  // ── 싱크 가사 ───────────────────────────────────────────

  Future<void> _fetchSyncedLyrics() async {
    if (_selectedSong == null) {
      _showSnack('먼저 곡을 선택해 주세요.');
      return;
    }
    _showSnack('싱크 가사를 찾는 중...');
    final outcome = await _app.fetchSyncedLyricsFor();
    if (!mounted) return;
    _showSnack(outcome.message);
  }

  /// 원곡·MR을 비교해 가사 싱크를 맞춘다. 몇 초 걸리므로 안내를 먼저 띄운다.
  Future<void> _autoAlignLyrics() => _app.autoAlignLyrics();

  Future<void> _adjustLyricsOffset(int deltaMs) =>
      _app.adjustLyricsOffset(deltaMs);

  // ── 유튜브 가져오기 ─────────────────────────────────────

  Future<void> _refreshToolAvailability() => _app.refreshToolAvailability();

  Future<void> _updateYtDlp() => _app.updateYtDlpTool();

  Future<void> _locateYtDlp() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'yt-dlp 실행 파일 선택',
    );
    final files = picked?.files ?? const [];
    final path = files.isEmpty ? null : files.first.path;
    if (path == null) return;
    await _app.setYtDlpPath(path);
  }

  Future<void> _startYoutubeImport(
    String url,
    MrSourceMode mode, {
    bool fetchLyrics = true,
    ImportPlan plan = const ImportPlan.single(),
  }) async {
    if (!looksLikeYoutubeUrl(url)) {
      _showSnack('유튜브 주소가 아닙니다. 링크를 다시 확인해 주세요.');
      return;
    }
    if (!await _confirmYoutubeNotice()) return;
    final outcome = await _app.enqueueImport(
      url,
      mode,
      fetchLyrics: fetchLyrics,
      plan: plan,
    );
    if (!mounted) return;
    _showSnack(
      outcome.ok
          ? '가져오는 중입니다. 진행 상황은 홈 위쪽에 표시됩니다.'
          : (outcome.message ?? '가져오기를 시작하지 못했습니다.'),
    );
  }

  /// 저작권 방침: 최초 사용 시 1회 확인을 받는다. 이후에는 상시 문구만 보인다.
  /// 확인은 반드시 이 화면(사용자 본인)에서만 이뤄진다 — 제어 API는 세팅 불가.
  Future<bool> _confirmYoutubeNotice() async {
    if (await _app.hasYoutubeAck()) return true;
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
      await _app.ackYoutubeNotice();
      return true;
    }
    return false;
  }

  /// 기존 곡에 반주를 하나 더 붙인다(노래방 버전 등, 별도 링크).
  Future<void> _addTrackToSong(Song song) async {
    unawaited(_refreshToolAvailability());
    final choice = await AddTrackDialog.show(
      context,
      song: song,
      toolAvailable: _ytDlpAvailable,
      toolMissingReason: _ytDlpMissingReason,
      separatorStatusLabel: _separatorStatusLabel,
      separatorOnline: _separatorOnline,
      localAiEnabled: _settings.localAiEnabled,
    );
    if (choice == null) return;
    if (!await _confirmYoutubeNotice()) return;
    final outcome = await _app.enqueueTrackImport(
      songId: choice.songId,
      url: choice.url,
      mode: choice.mode,
      slot: choice.slot,
      label: choice.label,
    );
    if (!mounted) return;
    _showSnack(
      outcome.ok
          ? '반주를 가져오는 중입니다. 진행 상황은 홈 위쪽에 표시됩니다.'
          : (outcome.message ?? '반주를 가져오지 못했습니다.'),
    );
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
      localAiEnabled: _settings.localAiEnabled,
    );
    if (choice == null) return;
    await _startYoutubeImport(
      choice.url,
      choice.mode,
      fetchLyrics: choice.fetchLyrics,
      plan: choice.plan,
    );
  }

  Future<void> _editSong(Song song) async {
    final before = {
      for (final track in song.backingTracks) track.slot: track.fileName,
    };
    final outcome = await _songActions.editSong(
      context: context,
      songs: _songs,
      song: song,
      selectedSong: _selectedSong,
    );
    await _applySongActionOutcome(outcome, preferredSlot: _selectedTrackSlot);

    // 반주를 갈아끼웠는데 파일명이 같으면(같은 제목·슬롯) 예전 오디오의
    // 키 변형본·EQ 분석이 그대로 서빙된다. 그 캐시를 비운다.
    final updated = _app.songById(song.id);
    if (updated == null) return;
    for (final track in updated.backingTracks) {
      if (before[track.slot] == track.fileName) continue;
      unawaited(_app.trackAssets.invalidate(track.fileName));
    }
    for (final entry in before.entries) {
      final still = updated.trackForSlot(entry.key);
      if (still?.fileName == entry.value) continue;
      unawaited(_app.trackAssets.invalidate(entry.value));
    }
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

  Future<void> _toggleFavorite(Song song) => _app.toggleFavorite(song);

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

  Future<void> _reserveSong(Song song) => _app.reserveSong(song);

  Future<void> _removeQueueItem(int index) => _app.removeQueueItem(index);

  Future<void> _reorderQueue(int oldIndex, int newIndex) =>
      _app.reorderQueue(oldIndex, newIndex);

  Future<void> _clearQueue() => _app.clearQueue();

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
    await _app.reserveAll(songs);
  }

  void _openPrompter(Song song) {
    // 컨트롤러를 넘겨 전체화면도 살아 있는 재생 위치를 구독하게 한다.
    PrompterNavigation.open(
      context: context,
      song: song,
      settingsProvider: () => _settings,
      playback: _playback,
      fontSize: _settings.effectiveFontSizePt,
      lineHeight: _settings.effectiveLineHeight,
      fontFamily: PrompterSettingsService.resolvedFontFamily(_settings),
      onSettingsChanged: _updateSettings,
      onStepPitch: _app.nudgePitchDebounced,
      onStepTempo: _app.nudgeTempoDebounced,
      pendingPitch: _app.pendingPitch,
      songKey: _app.trackBaseKeyFor(song, _selectedTrackSlot),
      soundingKey: _app.soundingKeyFor(song, _selectedTrackSlot),
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
      onJumpToStart: _playback.jumpToStart,
      onJumpToEnd: _playback.jumpToEnd,
      onSeekRelative: _playback.seekRelative,
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
        onRetryImportJob: _importJobs.retry,
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
        onAutoAlignLyrics: _autoAlignLyrics,
        pitchSemitones: _selectedSong == null
            ? 0
            : _settings.pitchForSong(_selectedSong!.id, _selectedTrackSlot),
        onAdjustPitch: _adjustPitch,
        tempoScale: _selectedSong == null
            ? 1
            : _app.effectiveTempoFor(_selectedSong!, _selectedTrackSlot),
        onAdjustTempo: _app.nudgeTempoDebounced,
        onStepPitch: _app.nudgePitchDebounced,
        pendingPitch: _app.pendingPitch,
        pendingTempo: _app.pendingTempo,
        soundingKey: _selectedSong == null
            ? null
            : _app.soundingKeyFor(_selectedSong!, _selectedTrackSlot),
        pitchBaseKey: _selectedSong == null
            ? null
            : _app.trackBaseKeyFor(_selectedSong!, _selectedTrackSlot),
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
        onPlayTakeAccompaniment: _playTakeAccompaniment,
        onCutTakeAccompaniment: _cutAccompanimentForTake,
        onTakeMixSettings: _showTakeMixSettings,
        onExportTake: _exportTake,
        recordingDevices: _recording.devices,
        onRefreshRecordingDevices: _refreshRecordingDevices,
        micTesting: _recording.isProbing,
        micLevel: _recording.level,
        micLevelLabel: _recording.levelLabel,
        onToggleMicTest: _toggleMicTest,
        composeJobs: _app.composeJobs.jobs,
        compositions: _app.composeLibrary.items,
        composeStatusLabel: _app.composeStatusLabel,
        bgmStatusLabel: _app.bgmStatusLabel,
        playingCompositionId: _playingCompositionId,
        onPolishPrompt: _polishPrompt,
        onTagLyrics: _tagComposeLyrics,
        onCompose: _composeGenerate,
        onComposeVariations: _composeVariations,
        onCancelComposeJob: _app.composeJobs.cancel,
        onRetryComposeJob: _app.composeJobs.retry,
        onClearFinishedComposeJobs: _app.composeJobs.clearFinished,
        onPlayComposition: _playComposition,
        onStopComposition: _stopComposition,
        onRenameComposition: _renameComposition,
        onRegisterComposition: _registerComposition,
        onAttachCompositionToSong: _attachCompositionToSong,
        onExportComposition: _exportComposition,
        onDeleteComposition: _deleteComposition,
        bgmPresetsLoader: _app.bgmCompose.presets,
        disabledDestinations: _settings.localAiEnabled
            ? const <AppDestination>{}
            : const {AppDestination.compose},
        onDisabledDestinationTap: (_) =>
            _showSnack('설정에서 로컬AI를 켜면 사용할 수 있습니다.'),
        onCheckOllamaModels: _app.ollama.listModels,
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
        onAddTrack: _addTrackToSong,
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
