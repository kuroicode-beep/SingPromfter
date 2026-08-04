import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, KeyEvent, LogicalKeyboardKey;

import '../controllers/app_controller.dart';
import '../controllers/import_job_controller.dart';
import '../controllers/playback_controller.dart';
import '../controllers/recording_controller.dart';
import '../controllers/training_session_controller.dart';
import '../coordinators/song_action_coordinator.dart';
import '../dialogs/add_song_dialog.dart';
import '../dialogs/add_track_dialog.dart';
import '../dialogs/custom_font_size_dialog.dart';
import '../dialogs/duet_mix_dialog.dart';
import '../dialogs/pick_song_dialog.dart';
import '../dialogs/pitch_report_dialog.dart';
import '../dialogs/regenerate_lyrics_dialog.dart';
import '../dialogs/youtube_import_dialog.dart';
import '../models/app_destination.dart';
import '../models/routine_step_spec.dart';
import '../models/vocal_course.dart' show VocalCourse;
import '../models/vocal_routine.dart' show VocalRoutines, dateKey;
import '../models/import_plan.dart';
import '../models/mr_source_mode.dart';
import '../models/prompter_display_mode.dart';
import '../models/prompter_settings.dart';
import '../models/queue_item.dart';
import '../models/recording_take.dart';
import '../models/song.dart';
import '../models/track_variant.dart';
import '../navigation/prompter_navigation.dart';
import '../repository/song_repository.dart';
import '../services/backup_service.dart';
import '../services/lyrics_sync_service.dart';
import '../services/practice_log_service.dart';
import '../services/daily_goal_service.dart';
import '../services/recording_library_service.dart';
import '../services/youtube_import_service.dart';
import '../services/youtube_data_client.dart';
import '../services/guide_audio_service.dart';
import '../services/prompter_audio_service.dart';
import '../services/prompter_settings_service.dart';
import '../services/song_library_service.dart';
import '../services/library_maintenance_service.dart';
import '../services/song_filter_service.dart';
import '../services/song_sort_service.dart';
import '../services/take_mix_service.dart';
import '../services/control_server.dart';
import '../widgets/song_list_screen_content.dart';
import '../widgets/training_session_card.dart';
import '../widgets/youtube_search_panel.dart';
import '../theme/app_theme.dart';
import '../widgets/snack_message.dart';
import '../widgets/prompter_keyboard_scope.dart';
import '../widgets/prompter_line_list_view.dart' show LineEditRequest;

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
  // 따라하기 세션 — 음성 안내(내장 TTS 클립)·피아노 런은 전용 플레이어로.
  final _guideAudio = GuideAudioService();
  late final _trainingSession = TrainingSessionController(
    audio: _guideAudio,
    voiceRange: () => TrainingVoiceRange.fromStorage(
      _settings.trainingVoiceRange,
    ),
    onStepCompleted: (stepId) async {
      await _dailyGoals.markStepDone(stepId);
      if (mounted) setState(() {});
    },
  );
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

  // 유튜브 탭의 검색·차트 상태.
  // 패널은 재생성되므로 여기(State)가 소유해야 결과·차트 캐시가 유지된다.
  final _ytClient = YoutubeDataClient();
  String _ytQuery = '';
  List<YoutubeVideo> _ytResults = const [];
  YoutubeFetchStatus _ytStatus = YoutubeFetchStatus.ok;
  String? _ytMessage;
  bool _ytLoading = false;
  YoutubeChartKind _ytChart = YoutubeChartKind.domestic;

  /// 연도별 차트의 연대·장르 선택.
  int _ytDecade = 2020;
  String _ytGenre = '전체';

  /// 차트는 세션 안에서 캐시한다 — 칩을 오갈 때마다 재호출하지 않게.
  /// 키는 종류(+연도별은 연대·장르 조합)로 만든다.
  final Map<String, List<YoutubeVideo>> _ytChartCache = {};

  String _chartCacheKey(YoutubeChartKind kind) => switch (kind) {
    YoutubeChartKind.decade => 'decade:$_ytDecade:$_ytGenre',
    _ => kind.name,
  };

  // 노래방 자동 검색의 대기 타깃 — 있으면 [가져오기]가 이 곡 4번 슬롯으로 간다.
  // 탭을 오가도 유지되고, 성공/취소/새 자동 검색 시작 때 해제된다.
  String? _karaokeTargetSongId;
  String? _karaokeTargetTitle;

  // 좌측 목록 자체의 검색·필터 (검색 화면과 독립)
  String _listQuery = '';
  SongListFilterMode _listFilterMode = SongListFilterMode.all;
  // 정렬 모드는 설정에 저장된다 — '내 순서'(드래그 재정렬)가 재실행 후에도
  // 유지돼야 하기 때문. 목록 순서 자체는 songs.json의 나열 순서가 정본이다.
  SongSortMode get _listSortMode => _settings.songSortMode;

  /// 홈과 무대가 똑같이 소비하는 동작 묶음 — 정의는 이 한 곳뿐이다.
  PrompterActions get _prompterActions => PrompterActions(
    togglePlayPause: _togglePlayPause,
    toggleRecording: _toggleRecording,
    resetLyricsSync: _resetLyricsSync,
    anchorFirstLine: _anchorFirstLine,
    nudgeLyricsOffset: _adjustLyricsOffset,
    nudgeLyricsFromCurrentLine: _app.adjustLyricsFromCurrentLine,
    toggleLyricsHold: _app.toggleLyricsHold,
    toggleSyncLock: _app.toggleSyncLock,
    deleteCurrentLine: _app.deleteCurrentLyricsLine,
    undoLyricsEdit: _app.undoLyricsEdit,
    restoreLyricsBackup: _confirmRestoreLyricsBackup,
    stepLine: _playback.stepLine,
    editLyricsLine: _editLyricsLine,
    jumpToStart: _playback.jumpToStart,
    jumpToEnd: _playback.jumpToEnd,
    seekRelative: _playback.seekRelative,
  );

  Song? get _selectedSong => _playback.snapshot.song;
  int? get _selectedTrackSlot => _playback.snapshot.trackSlot;

  @override
  void initState() {
    super.initState();
    _app.onMessage = _showSnack;
    _app.onNavigate = _handleRemoteNavigate;
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
    // 우하단 '녹음 중' 배지가 듣는 표시용 거울 — 잠금 배지와 같은 패턴.
    _recording.addListener(_syncRecordingView);
    // 창을 X로 닫아도 앱이 띄운 서버(분리·STT)가 남지 않게 — dispose는
    // 창 파괴 경로에서 안 불릴 수 있어 종료 요청 훅에서 먼저 끈다.
    _exitListener = AppLifecycleListener(
      onExitRequested: () async {
        _app.stopManagedServers();
        return AppExitResponse.exit;
      },
    );
    // 따라하기 세션 상태 변화 → 러너 카드 갱신.
    _trainingSession.addListener(_onPlaybackStateChanged);
    // 테이크 재생이 끝나면 '정지' 버튼이 '듣기'로 돌아오게 한다.
    _takeBindings = _takePlayer.bind(
      onPlayingChanged: (playing) {
        if (!playing && _playingTakeId != null && mounted) {
          setState(() => _playingTakeId = null);
        }
      },
      // 녹음 플레이어(시크바)용 — 재생 중일 때만 화면을 다시 그린다.
      onPositionChanged: (position) {
        if (_playingTakeId != null && mounted) {
          setState(() => _takePosition = position);
        }
      },
      onDurationChanged: (duration) {
        if (mounted) setState(() => _takeDuration = duration);
      },
      onCompleted: () async {},
    );
    _bootstrap();
  }

  void _onPlaybackStateChanged() {
    if (mounted) setState(() {});
  }

  void _syncRecordingView() {
    _playback.recordingView.value = _recording.isRecording;
  }

  AppLifecycleListener? _exitListener;

  @override
  void dispose() {
    for (final timer in _pendingDeleteTimers.values) {
      timer.cancel();
    }
    _playback.state.removeListener(_onPlaybackStateChanged);
    _playback.lineIndex.removeListener(_onPlaybackStateChanged);
    _importJobs.removeListener(_onPlaybackStateChanged);
    _exitListener?.dispose();
    _recording.removeListener(_syncRecordingView);
    _recording.dispose();
    _takeBindings?.cancel();
    _takePlayer.dispose();
    _trainingSession.removeListener(_onPlaybackStateChanged);
    _trainingSession.dispose();
    unawaited(_guideAudio.dispose());
    unawaited(_controlServer.stop());
    _ytClient.close();
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
    // 저장해 둔 녹음 입력 장치를 먼저 지정한 뒤 목록을 읽는다 —
    // refreshDevices는 미지정일 때만 첫 장치를 채우므로 순서가 중요하다.
    final savedDevice = _settings.recordingDevice;
    if (savedDevice != null && savedDevice.isNotEmpty) {
      _recording.deviceName = savedDevice;
    }
    unawaited(_recording.refreshDevices());
    // MCP 제어 API — 루프백 전용, 실패해도 앱 동작에 영향 없음.
    await _controlServer.start();
  }

  /// 녹음 입력 장치 선택 — 즉시 적용하고 설정에 저장한다.
  Future<void> _selectRecordingDevice(String device) async {
    _recording.deviceName = device;
    await _updateSettings(_settings.copyWith(recordingDevice: device));
    if (!mounted) return;
    setState(() {});
    _showSnack('녹음 입력 장치: $device');
  }

  Future<void> _loadSong(Song song, {int? preferredSlot}) =>
      _playback.loadSong(song, preferredSlot: preferredSlot);

  Future<void> _togglePlayPause() => _playback.togglePlayPause();

  Future<void> _stopPlayback() => _playback.stop();

  Future<void> _restartPlayback() => _playback.restart();

  Future<void> _applyAccessibilityPreset(String preset) =>
      _updateSettings(PrompterSettingsService.preset(_settings, preset));

  Future<void> _updateSettings(PrompterSettings next) =>
      _app.updateSettings(next);

  Future<void> _showCustomFontSizeDialog() async {
    final next = await CustomFontSizeDialog.pickSettings(context, _settings);
    if (!mounted) return;
    if (next != null) await _updateSettings(next);
  }

  Future<void> _selectTrackSlot(int slot) => _app.selectTrackSlot(slot);

  // ── 녹음 믹스다운 ───────────────────────────────────────

  // ── 음정 코치 (v3.0.0) ──────────────────────────────────

  /// 채점·보정의 공통 준비물 — (녹음 경로, 기준 보컬 경로, 전조).
  /// 실패하면 스낵바로 사유를 알리고 null.
  Future<(String, String, int)?> _pitchCoachInputs(RecordingTake take) async {
    final song = _app.songById(take.songId);
    if (song == null) {
      _showSnack('원본 곡이 삭제돼 채점 기준을 만들 수 없습니다.');
      return null;
    }
    if (!await _app.pitchCoach.isOnline()) {
      _showSnack('음정 코치 서버가 꺼져 있습니다(포트 8773). 켜고 다시 시도해 주세요.');
      return null;
    }
    _showSnack('채점 기준(원곡 보컬) 준비 중… 처음이면 수십 초 걸립니다.');
    final reference = await _app.vocalStemForSong(song);
    if (reference == null) return null;
    final recording = await _buildRecordingPath(take.fileName);
    if (!await File(recording).exists()) {
      _showSnack('녹음 파일을 찾을 수 없습니다.');
      return null;
    }
    return (recording, reference, _app.takeTranspose(song, take));
  }

  /// [음정 체크] — 녹음을 원곡 보컬과 비교해 점수와 틀린 곳을 보여 준다.
  Future<void> _analyzeTake(RecordingTake take) async {
    final inputs = await _pitchCoachInputs(take);
    if (inputs == null || !mounted) return;
    final (recording, reference, transpose) = inputs;

    _showSnack('음정·박자 분석 중… (수십 초)');
    final result = await _app.pitchCoach.analyze(
      recordingPath: recording,
      referencePath: reference,
      alignMs: take.alignOffsetMs,
      transpose: transpose,
    );
    if (!mounted) return;
    if (!result.success) {
      _showSnack(result.message ?? '분석에 실패했습니다.');
      return;
    }
    await PitchReportDialog.show(
      context,
      songTitle: take.songTitle,
      analysis: result.analysis!,
    );
  }

  /// [AI 보정] — 음정(과 전체 박자)을 보정해 새 테이크로 저장한다.
  /// 목소리만 저장하거나, 이어서 반주와 믹싱까지 할 수 있다.
  Future<void> _correctTake(RecordingTake take) async {
    final mix = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI 보정 저장'),
        content: const Text(
          '음정을 원곡 멜로디에 맞추고 전체 박자를 보정합니다.\n'
          '보정본을 어떻게 저장할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('목소리만'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('반주와 믹싱'),
          ),
        ],
      ),
    );
    if (mix == null || !mounted) return;

    final inputs = await _pitchCoachInputs(take);
    if (inputs == null || !mounted) return;
    final (recording, reference, transpose) = inputs;

    _showSnack('AI 보정 중… (수십 초)');
    final dir = await _recordingLibrary.directory();
    final fileName =
        '보정_${DateTime.now().millisecondsSinceEpoch}_${take.fileName}.wav';
    final outputPath = '${dir.path}/$fileName';
    final result = await _app.pitchCoach.correct(
      recordingPath: recording,
      referencePath: reference,
      outputPath: outputPath,
      alignMs: take.alignOffsetMs,
      transpose: transpose,
    );
    if (!mounted) return;
    if (!result.success) {
      _showSnack(result.message ?? '보정에 실패했습니다.');
      return;
    }

    // 보정본은 기준 타임라인(반주 t=0)에 맞춰 나온다 — align 0.
    var corrected = RecordingTake(
      id: const Uuid().v4(),
      songId: take.songId,
      songTitle: take.songTitle,
      fileName: fileName,
      recordedAt: DateTime.now(),
      durationMs: take.durationMs,
      backingTrackSlot: take.backingTrackSlot,
      pitchSemitones: take.pitchSemitones,
      alignOffsetMs: 0,
      comment: 'AI 보정'
          '${result.timingFixedMs != 0 ? ' · 박자 ${(result.timingFixedMs.abs() / 1000).toStringAsFixed(1)}초 ${result.timingFixedMs > 0 ? '당김' : '밀음'}' : ''}',
      correctedFrom: take.id,
    );
    await _recordingLibrary.add(corrected);
    setState(() {});

    if (mix) {
      await _mixTake(corrected);
    } else {
      _showSnack('보정본을 저장했습니다. 녹음 목록에서 들어보세요.');
    }
  }

  /// 현재 선택된 반주 mp3를 내보내기 폴더(설정)로 복사한다 — USB·폰으로
  /// 옮겨 외부 노래방·연습에 쓰기 위한 반출 경로.
  Future<void> _exportCurrentTrack() async {
    final song = _selectedSong;
    final slot = _selectedTrackSlot;
    final track = (song != null && slot != null)
        ? song.trackForSlot(slot)
        : null;
    if (song == null || track == null) {
      _showSnack('내보낼 반주가 없습니다. 곡과 반주를 먼저 선택해 주세요.');
      return;
    }
    final sourcePath = await _repo.getBackingTrackPath(track.fileName);
    if (sourcePath == null) {
      _showSnack('반주 파일을 찾을 수 없습니다.');
      return;
    }
    try {
      final dir = Directory(_settings.exportFolder);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      // 곡 제목·반주 라벨로 알아볼 수 있는 이름을 만든다(금지 문자는 _).
      final stem = '${song.title}_${track.label}'
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          .trim();
      var dest = File('${dir.path}\\$stem.mp3');
      // 같은 이름이 있으면 덮어쓰지 않고 번호를 붙인다.
      var n = 2;
      while (dest.existsSync()) {
        dest = File('${dir.path}\\$stem ($n).mp3');
        n++;
      }
      await File(sourcePath).copy(dest.path);
      if (!mounted) return;
      _showSnack('복사 완료: ${dest.path}');
    } catch (e) {
      if (!mounted) return;
      _showSnack('복사에 실패했습니다: $e');
    }
  }

  /// 듀엣 합성 — 남·여 파트 테이크 두 개를 (있으면) 반주와 한 곡으로 합쳐
  /// 새 테이크로 등록한다.
  Future<void> _duetMix() async {
    final takes = _recordingLibrary.takes;
    if (takes.length < 2) {
      _showSnack('듀엣 합성에는 테이크가 2개 이상 필요합니다.');
      return;
    }
    final picked = await DuetMixDialog.show(context, takes);
    if (picked == null || !mounted) return;
    final a = picked.partA;
    final b = picked.partB;

    // 반주는 남자 파트 테이크의 곡·슬롯을 따른다(없으면 여자 파트, 그래도
    // 없으면 보컬 둘만 겹친다).
    String? backingPath;
    for (final part in [a, b]) {
      final songMatches = _songs.where((s) => s.id == part.songId).toList();
      final song = songMatches.isEmpty ? null : songMatches.first;
      final slot = part.backingTrackSlot;
      final track = (song != null && slot != null)
          ? song.trackForSlot(slot)
          : null;
      if (track != null) {
        backingPath = await _repo.getBackingTrackPath(track.fileName);
        if (backingPath != null) break;
      }
    }

    _showSnack('듀엣 합성 중...');
    final vocalA = await _recordingLibrary.pathFor(a);
    final vocalB = await _recordingLibrary.pathFor(b);
    final duetName = '${const Uuid().v4()}_duet.m4a';
    final outputPath =
        '${(await _recordingLibrary.directory()).path}/$duetName';
    final result = await TakeMixService().duet(
      backingPath: backingPath,
      vocalAPath: vocalA,
      vocalBPath: vocalB,
      outputPath: outputPath,
      alignAMs: a.alignOffsetMs,
      alignBMs: b.alignOffsetMs,
    );
    if (!mounted) return;
    if (!result.success) {
      _showSnack(result.message ?? '듀엣 합성에 실패했습니다.');
      return;
    }

    final duetTake = RecordingTake(
      id: const Uuid().v4(),
      songId: a.songId,
      songTitle: a.songTitle,
      fileName: duetName,
      recordedAt: DateTime.now(),
      durationMs: a.durationMs > b.durationMs ? a.durationMs : b.durationMs,
      backingTrackSlot: a.backingTrackSlot,
      pitchSemitones: a.pitchSemitones,
      comment:
          '듀엣 합성 — 남: ${DuetMixDialog.takeLabel(a)} / '
          '여: ${DuetMixDialog.takeLabel(b)}',
    );
    await _recordingLibrary.add(duetTake);
    if (!mounted) return;
    setState(() {});
    _showSnack('듀엣 합성 완료 — 녹음 보관함 맨 위에 있습니다.');
  }

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

  /// 새 폴더 이름을 받아 설정의 폴더 순서에 등록한다(빈 폴더 허용).
  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('새 폴더'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '폴더 이름'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('만들기'),
          ),
        ],
      ),
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;
    final current = [
      ..._settings.folderOrder,
      ...Song.folderNames(_songs).where(
        (f) => !_settings.folderOrder.contains(f),
      ),
    ];
    if (current.contains(trimmed)) {
      _showSnack('"$trimmed" 폴더가 이미 있습니다.');
      return;
    }
    await _updateSettings(
      _settings.copyWith(folderOrder: [...current, trimmed]),
    );
    if (!mounted) return;
    setState(() {});
    _showSnack('"$trimmed" 폴더를 만들었습니다. 곡 수정에서 지정해 담습니다.');
  }

  /// 폴더를 위/아래로 옮긴다. 화면의 표시 순서를 그대로 저장해
  /// 곡에만 적혀 있던 폴더도 이때 순서에 편입된다.
  Future<void> _moveFolder(
    List<String> displayOrder,
    String name,
    int delta,
  ) async {
    final order = List<String>.from(displayOrder);
    final index = order.indexOf(name);
    final next = index + delta;
    if (index < 0 || next < 0 || next >= order.length) return;
    order.removeAt(index);
    order.insert(next, name);
    await _updateSettings(_settings.copyWith(folderOrder: order));
    if (!mounted) return;
    setState(() {});
  }

  /// 곡을 드래그해 폴더에 떨어뜨렸을 때. folder가 ''이면 폴더에서 꺼낸다.
  Future<void> _moveSongToFolder(String songId, String folder) async {
    final updated = await _app.updateSongFields(songId, folder: folder);
    if (!mounted || updated == null) return;
    setState(() {});
    _showSnack(
      folder.isEmpty
          ? '"${updated.title}" 폴더에서 꺼냈습니다'
          : '"${updated.title}" → "$folder" 폴더로 이동',
    );
  }

  /// 곡을 다른 곡 위에 떨어뜨림 — 순서를 그 자리로 바꾸고, 폴더가 다르면
  /// 대상 곡의 폴더로 함께 들어간다. 두 저장이 겹치지 않게 순차로 처리한다.
  Future<void> _dropSongOnSong(
    String draggedId,
    String targetId,
    List<String> visibleIds,
    int oldIndex,
    int newIndex,
  ) async {
    final dragged = _app.songById(draggedId);
    final target = _app.songById(targetId);
    if (dragged == null || target == null) return;
    if (dragged.folder != target.folder) {
      await _app.updateSongFields(draggedId, folder: target.folder);
    }
    await _reorderSongList(visibleIds, oldIndex, newIndex);
    if (!mounted) return;
    setState(() {});
  }

  /// 폴더 펼침 토글 — 설정에 저장해 재실행해도 유지된다.
  Future<void> _toggleFolder(String name) async {
    final expanded = List<String>.from(_settings.expandedFolders);
    expanded.contains(name) ? expanded.remove(name) : expanded.add(name);
    await _updateSettings(_settings.copyWith(expandedFolders: expanded));
    if (!mounted) return;
    setState(() {});
  }

  /// 4주 코스 시작 — 오늘을 1주차 첫날로 삼는다.
  Future<void> _startTrainingCourse() async {
    await _app.updateSettings(
      _settings.copyWith(trainingCourseStart: dateKey(DateTime.now())),
    );
    if (!mounted) return;
    setState(() {});
    _showSnack('4주 보컬 코스 시작 — 1주차: 호흡과 지지');
  }

  Future<void> _toggleRoutineStep(String stepId) async {
    await _dailyGoals.toggleStep(_dailyGoals.today(), stepId);
    if (!mounted) return;
    setState(() {});
  }

  // ── 따라하기 세션 ──────────────────────────────────────

  /// 러너 카드가 소비하는 불변 뷰 — 컨트롤러 상태의 스냅샷.
  TrainingSessionView get _trainingSessionView => TrainingSessionView(
    active: _trainingSession.active,
    finished: _trainingSession.phase == TrainingSessionPhase.finished,
    paused: _trainingSession.paused,
    stepTitle: _trainingSession.currentStep?.title ?? '',
    bigText: _trainingSession.bigText,
    remaining: _trainingSession.remaining,
    stepIndex: _trainingSession.stepIndex,
    stepCount: _trainingSession.routine?.steps.length ?? 0,
  );

  /// 오늘 루틴으로 따라하기 시작 — 코스 진행 중이면 주차 브리핑을 선행한다.
  Future<void> _startTrainingSession() async {
    final routine = VocalRoutines.byId(_dailyGoals.today().routineId);
    final start = DateTime.tryParse(_settings.trainingCourseStart ?? '');
    final week =
        start == null ? null : VocalCourse.weekFor(start, DateTime.now());
    await _trainingSession.start(routine, courseWeekNumber: week?.number);
  }

  /// 트레이닝 탭 전용 단축키 — 세션 중 Space=일시정지/재개, Home=섹션 재시작.
  /// 그 밖의 키는 skipRemainingHandlers로 기본 매핑(R·T 등)을 차단한다 —
  /// 트레이닝 탭에서 녹음·싱크 키가 먹으면 사고다.
  KeyEventResult _handleTrainingKey(KeyEvent event) {
    if (_destination != AppDestination.training) return KeyEventResult.ignored;
    if (!_trainingSession.active) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.space) {
        unawaited(_trainingSession.togglePause());
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.home) {
        unawaited(_trainingSession.restartStep());
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.skipRemainingHandlers;
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
  /// 곡 목록 드래그 재정렬. 다른 정렬 모드였다면 지금 보이는 전체 순서를
  /// 저장 순서로 굳히고 '내 순서'로 전환한다 — 안 그러면 끌어 놓은 곡이
  /// 정렬 규칙에 따라 제자리로 튕긴다.
  Future<void> _reorderSongList(
    List<String> visibleIds,
    int oldIndex,
    int newIndex,
  ) async {
    var base = _songs;
    if (_listSortMode != SongSortMode.manual) {
      base = SongSortService.sort(
        _songs,
        mode: _listSortMode,
        practiceCounts: SongSortService.practiceCountsFrom(
          _practiceLog.summaries,
        ),
      );
      await _updateSettings(
        _settings.copyWith(songSortMode: SongSortMode.manual),
      );
      _showSnack("정렬을 '내 순서'로 바꿨습니다. 끌어서 순서를 정할 수 있습니다.");
    }
    final next = SongSortService.applyVisibleReorder(
      all: base,
      visibleIds: visibleIds,
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
    await _app.setSongOrder(List<Song>.from(next));
  }

  Future<void> _autoAlignLyrics() => _app.autoAlignLyrics();

  /// 재생 중에 "지금이 첫 줄" — 사람이 직접 싱크를 맞추는 입구(버튼 전용).
  Future<void> _anchorFirstLine() => _app.anchorLyricsToCurrentPosition();

  /// T — 싱크를 원래대로(오프셋 0). 밀고 당기다 어긋나면 처음부터.
  Future<void> _resetLyricsSync() => _app.resetLyricsOffset();

  /// E — 현재 가사 줄을 프롬프터에서 바로 편집. 요청 번호를 올리면
  /// 가사 뷰가 그 줄을 입력창으로 바꾼다(ESC로 저장).
  void _editCurrentLine() {
    setState(() {
      _lineEditRequest = LineEditRequest(
        seq: (_lineEditRequest?.seq ?? 0) + 1,
        index: _playback.lineIndex.value,
      );
    });
  }

  LineEditRequest? _lineEditRequest;

  // 녹음 플레이어 상태 — 재생 중 테이크의 위치/길이.
  Duration _takePosition = Duration.zero;
  Duration _takeDuration = Duration.zero;

  /// 가사 다시 생성 — 옵션 다이얼로그를 거쳐 정밀 파이프라인을 돌린다.
  /// (보컬 분리 받아쓰기 + 환청 정리 + 선택적 DeepSeek 검증·정답 가사 대조)
  Future<void> _regenerateLyrics() async {
    final song = _selectedSong;
    if (song == null) {
      _showSnack('먼저 곡을 선택해 주세요.');
      return;
    }
    final options = await RegenerateLyricsDialog.show(
      context,
      hasExistingLyrics: (song.lrcFileName ?? '').isNotEmpty,
      deepSeekAvailable: _app.deepSeekLyrics.available,
      hasSourceUrl: (song.sourceUrl ?? '').trim().isNotEmpty,
    );
    if (options == null) return;
    await _app.regenerateLyrics(
      songId: song.id,
      useVocalStem: options.useVocalStem,
      useDeepSeek: options.useDeepSeek,
      useYoutubeSubs: options.useYoutubeSubs,
      referenceLyrics: options.referenceLyrics,
    );
  }

  Future<void> _editLyricsLine(int index, String text) async {
    final ok = await _app.editLyricsLine(index: index, text: text);
    if (!ok && mounted) _showSnack('그 줄을 고치지 못했습니다.');
  }

  Future<void> _adjustLyricsOffset(int deltaMs) =>
      _app.adjustLyricsOffset(deltaMs);

  /// G — 원본 복구는 되돌릴 게 많아서 확인을 받고 실행한다.
  Future<void> _confirmRestoreLyricsBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        title: const Text(
          '가사 원본 복구',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          '보관된 원본(.bak)으로 가사를 되돌립니다.\n'
          '그동안의 삭제·타이밍 보정이 모두 원본 시점으로 돌아갑니다.\n'
          '복구 직전 상태는 F(실행취소)로 되돌릴 수 있습니다.',
          style: TextStyle(color: AppColors.textPrimary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('원본으로 복구'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _app.restoreLyricsBackup();
  }

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

  // ── 유튜브 검색 (곡 검색 탭) ───────────────────────────

  YoutubeSearchViewState get _youtubeSearchState => YoutubeSearchViewState(
    query: _ytQuery,
    status: _ytStatus,
    results: _ytResults,
    loading: _ytLoading,
    chart: _ytChart,
    apiKeyAvailable: _ytClient.hasApiKey,
    message: _ytMessage,
    karaokeTargetTitle: _karaokeTargetTitle,
    decade: _ytDecade,
    genre: _ytGenre,
  );

  /// 탭 전환의 단일 통로 — 유튜브 탭 첫 진입 시 차트를 lazy로 한 번 채운다.
  void _changeDestination(AppDestination next) {
    setState(() => _destination = next);
    if (next == AppDestination.youtube &&
        _ytQuery.isEmpty &&
        _ytResults.isEmpty &&
        !_ytLoading) {
      unawaited(_loadYoutubeChart(_ytChart));
    }
  }

  Future<void> _searchYoutube(String query) async {
    if (query.isEmpty) {
      // 차트 모드로 복귀.
      setState(() => _ytQuery = '');
      await _loadYoutubeChart(_ytChart);
      return;
    }
    setState(() {
      _ytQuery = query;
      _ytLoading = true;
    });
    final result = await _ytClient.search(query);
    if (!mounted) return;
    // 로딩 중 사용자가 검색어를 지웠으면 낡은 결과를 얹지 않는다.
    if (_ytQuery != query) return;
    setState(() {
      _ytLoading = false;
      _ytStatus = result.status;
      _ytMessage = result.message;
      _ytResults = result.videos;
    });
  }

  Future<void> _loadYoutubeChart(YoutubeChartKind kind) async {
    final cacheKey = _chartCacheKey(kind);
    final cached = _ytChartCache[cacheKey];
    // 연도별은 검색 100유닛이라 자동으로 부르지 않는다 — 칩만 바꾸고
    // [불러오기]를 기다린다(캐시가 있으면 그걸 보여 준다).
    final autoFetch = kind != YoutubeChartKind.decade;
    setState(() {
      _ytChart = kind;
      if (cached != null) {
        _ytStatus = YoutubeFetchStatus.ok;
        _ytMessage = null;
        _ytResults = cached;
        _ytLoading = false;
      } else {
        _ytResults = const [];
        _ytStatus = YoutubeFetchStatus.ok;
        _ytMessage = null;
        _ytLoading = autoFetch;
      }
    });
    if (cached != null || !autoFetch) return;

    final result = switch (kind) {
      YoutubeChartKind.domestic =>
        await _ytClient.mostPopularTop100(koreanOnly: true),
      YoutubeChartKind.global =>
        await _ytClient.mostPopularTop100(regionCode: 'US'),
      YoutubeChartKind.karaoke => await _ytClient.karaokeChannelPopular(),
      YoutubeChartKind.decade => const YoutubeFetchResult.ok([]),
    };
    if (!mounted) return;
    // 로딩 중 다른 칩으로 옮겼거나 검색을 시작했으면 버린다.
    if (_ytChart != kind || _ytQuery.isNotEmpty) return;
    setState(() {
      _ytLoading = false;
      _ytStatus = result.status;
      _ytMessage = result.message;
      _ytResults = result.videos;
      if (result.status == YoutubeFetchStatus.ok) {
        _ytChartCache[cacheKey] = result.videos;
      }
    });
  }

  /// 연도별 차트 [불러오기] — 명시적 버튼에서만(검색 100유닛/회) + 조합 캐시.
  Future<void> _loadDecadeChart() async {
    final cacheKey = _chartCacheKey(YoutubeChartKind.decade);
    final cached = _ytChartCache[cacheKey];
    if (cached != null) {
      setState(() {
        _ytStatus = YoutubeFetchStatus.ok;
        _ytMessage = null;
        _ytResults = cached;
        _ytLoading = false;
      });
      return;
    }
    setState(() => _ytLoading = true);
    final result = await _ytClient.decadeChart(
      decade: _ytDecade,
      genre: _ytGenre,
    );
    if (!mounted) return;
    if (_ytChart != YoutubeChartKind.decade || _ytQuery.isNotEmpty) return;
    if (_chartCacheKey(YoutubeChartKind.decade) != cacheKey) return;
    setState(() {
      _ytLoading = false;
      _ytStatus = result.status;
      _ytMessage = result.message;
      _ytResults = result.videos;
      if (result.status == YoutubeFetchStatus.ok) {
        _ytChartCache[cacheKey] = result.videos;
      }
    });
  }

  /// 연대/장르 칩 — 선택만 바꾸고 결과는 캐시가 있을 때만 즉시 반영.
  void _changeDecade(int decade) {
    setState(() {
      _ytDecade = decade;
      _ytResults =
          _ytChartCache[_chartCacheKey(YoutubeChartKind.decade)] ?? const [];
    });
  }

  void _changeGenre(String genre) {
    setState(() {
      _ytGenre = genre;
      _ytResults =
          _ytChartCache[_chartCacheKey(YoutubeChartKind.decade)] ?? const [];
    });
  }

  /// [미리듣기] — 기본 브라우저 새 창으로 유튜브를 연다(앱 내 재생 아님).
  Future<void> _previewYoutube(YoutubeVideo video) async {
    final ok = await launchUrl(
      Uri.parse(video.url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) _showSnack('브라우저를 열지 못했습니다.');
  }

  /// [가져오기] — 구성 팝업(기본/남자키/4번슬롯)을 띄우고 선택대로 가져온다.
  /// 노래방 자동 검색 타깃이 대기 중이면 키 선택만 받고 그 곡으로 직행한다.
  /// 저작권 게이트·스낵바는 각 경로가 처리한다.
  Future<void> _importFromYoutubeSearch(YoutubeVideo video) async {
    final targetId = _karaokeTargetSongId;
    if (targetId != null) {
      final semitones = await YoutubeImportDialog.showKaraokeKey(
        context,
        videoTitle: video.title,
        songTitle: _karaokeTargetTitle ?? '',
      );
      if (semitones == null || !mounted) return;
      await _importKaraokeToSong(
        video,
        semitones: semitones,
        targetSongId: targetId,
      );
      return;
    }

    final choice = await YoutubeImportDialog.show(
      context,
      videoTitle: video.title,
    );
    if (choice == null || !mounted) return;

    if (choice.kind == YoutubeImportKind.karaoke) {
      await _importKaraokeToSong(video, semitones: choice.karaokeSemitones);
      return;
    }
    await _startYoutubeImport(
      video.url,
      MrSourceMode.aiSeparate,
      fetchLyrics: true,
      plan: choice.plan!,
    );
  }

  /// 4번슬롯 — 기존 곡을 골라 노래방 반주로 붙인다. 영상이 이미 반주라
  /// 분리 없이 그대로(asIs) 받고, 키를 골랐으면 파이프라인이 구워 넣는다.
  /// [targetSongId]가 오면(자동 검색 흐름) 곡 고르기를 건너뛴다.
  Future<void> _importKaraokeToSong(
    YoutubeVideo video, {
    int semitones = 0,
    String? targetSongId,
  }) async {
    if (_songs.isEmpty) {
      _showSnack('먼저 곡을 하나 등록해 주세요. 노래방 반주는 기존 곡에 붙습니다.');
      return;
    }
    Song? song;
    if (targetSongId != null) {
      for (final s in _songs) {
        if (s.id == targetSongId) {
          song = s;
          break;
        }
      }
      if (song == null) {
        _cancelKaraokeTarget();
        _showSnack('대상 곡을 찾을 수 없습니다. 곡을 다시 골라 주세요.');
        return;
      }
    } else {
      song = await PickSongDialog.show(context, songs: _songs);
    }
    if (song == null || !mounted) return;
    if (!await _confirmYoutubeNotice()) return;
    final outcome = await _app.enqueueTrackImport(
      songId: song.id,
      url: video.url,
      mode: MrSourceMode.asIs,
      slot: TrackVariant.karaoke.preferredSlot,
      label: TrackVariant.karaoke.label,
      semitones: semitones,
    );
    if (!mounted) return;
    if (outcome.ok && targetSongId != null) {
      // 자동 검색 타깃 완료 — 배너를 내리고 진행 표시가 있는 홈으로.
      _cancelKaraokeTarget();
      _changeDestination(AppDestination.home);
    }
    _showSnack(
      outcome.ok
          ? "'${song.title}'의 4번 슬롯으로 가져오는 중입니다."
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
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case AddTrackKaraokeSearch(:final song):
        await _startKaraokeAutoSearch(song);
      case AddTrackFromUrl():
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
  }

  /// 노래방 자동 검색 — 유튜브 탭을 열고 "제목 가수 노래방"으로 바로 검색.
  /// 결과에서 [가져오기]를 누르면 이 곡 4번 슬롯으로 붙는다(_importFromYoutubeSearch).
  Future<void> _startKaraokeAutoSearch(Song song) async {
    setState(() {
      _karaokeTargetSongId = song.id;
      _karaokeTargetTitle = song.title;
      // _changeDestination 대신 직접 — 차트 lazy-fetch가 검색과 겹치지 않게.
      _destination = AppDestination.youtube;
    });
    final query = '${song.title} ${song.artist} 노래방'
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    await _searchYoutube(query);
  }

  /// 노래방 자동 검색의 대기 타깃 해제 — 배너 [취소]와 성공 경로가 쓴다.
  void _cancelKaraokeTarget() {
    setState(() {
      _karaokeTargetSongId = null;
      _karaokeTargetTitle = null;
    });
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
      trackPitches: {
        for (final track in song.backingTracks)
          track.slot: _app.settings.pitchForSong(song.id, track.slot),
      },
      // 재생 키는 저장 버튼과 무관하게 조절 즉시 반영. setPitch가 저장·
      // 클램프와 '지금 재생 중인 트랙이면 새 키로 재준비'까지 처리한다.
      onTrackPitchChanged: (slot, semitones) => unawaited(
        _app.setPitch(song.id, semitones, slot: slot, keepPosition: true),
      ),
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

    SnackMessage.show(
      context,
      message ?? '"${song.title}" 삭제됨',
      duration: const Duration(seconds: 10),
      actionLabel: '실행 취소',
      onAction: () => _restoreDeletedSong(song),
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

  /// 제어 API(POST /api/view)의 화면 전환. 처리했으면 true.
  bool _handleRemoteNavigate(String view) {
    if (!mounted) return false;
    if (view == 'stage') {
      final song = _selectedSong;
      if (song == null) return false;
      _openPrompter(song);
      return true;
    }
    if (view == 'back') {
      final navigator = Navigator.of(context);
      if (navigator.canPop()) navigator.pop();
      return true;
    }
    for (final dest in AppDestination.values) {
      if (dest.name == view) {
        _changeDestination(dest);
        return true;
      }
    }
    return false;
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
      actions: _prompterActions,
    );
  }

  void _showSnack(String message) =>
      mounted ? SnackMessage.show(context, message) : null;

  @override
  Widget build(BuildContext context) {
    final snapshot = _playback.snapshot;
    return PrompterKeyboardScope(
      // 재생·녹음·싱크 단축키는 재생 화면이 보이는 탭(홈·즐겨찾기)에서만.
      // 곡 검색·설정 등 다른 탭에서 R·T·Space가 먹으면 사고다.
      // 전체화면 무대는 같은 actions를 자기 스코프에서 소비한다.
      // 트레이닝 탭은 따라하기 세션 중에만 켜지고, overrideHandler가
      // Space·Home만 세션 제어로 받고 나머지 기본 매핑은 차단한다.
      enabled: _destination == AppDestination.home ||
          _destination == AppDestination.favorites ||
          (_destination == AppDestination.training &&
              _trainingSession.active),
      overrideHandler: _handleTrainingKey,
      settings: _settings,
      onSettingsChanged: _updateSettings,
      actions: _prompterActions,
      onEditCurrentLine: _editCurrentLine,
      onOpenPrompter: () {
        final song = _selectedSong;
        if (song != null) _openPrompter(song);
      },
      child: SongListScreenContent(
        loading: _loading,
        onStartSeparator: _app.ensureSeparatorOnline,
        destination: _destination,
        onDestinationChanged: _changeDestination,
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
        onAnalyzeTake: _analyzeTake,
        onCorrectTake: _correctTake,
        onPlayTakeMix: _playTakeMix,
        takePosition: _takePosition,
        takeDuration: _takeDuration,
        onSeekTake: _takePlayer.seek,
        onFetchSyncedLyrics: _fetchSyncedLyrics,
        onAdjustLyricsOffset: _adjustLyricsOffset,
        onAutoAlignLyrics: _autoAlignLyrics,
        onAnchorFirstLine: _anchorFirstLine,
        onSttLyrics: _regenerateLyrics,
        onEditLyricsLine: _editLyricsLine,
        lineEditRequest: _lineEditRequest,
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
        todayGoal: _dailyGoals.today(),
        trainingStreak: _dailyGoals.streak(),
        trainingCompletedThisWeek: _dailyGoals.completedInLast(7),
        goalLogs: _dailyGoals.logs,
        trainingCourseStart: _settings.trainingCourseStart,
        onStartCourse: _startTrainingCourse,
        onRoutineChanged: _changeRoutine,
        onToggleRoutineStep: _toggleRoutineStep,
        trainingSession: _trainingSessionView,
        onStartTrainingSession: _startTrainingSession,
        onTogglePauseTrainingSession: _trainingSession.togglePause,
        onRestartTrainingStep: _trainingSession.restartStep,
        onSkipTrainingStep: _trainingSession.skipStep,
        onStopTrainingSession: _trainingSession.stop,
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
            _updateSettings(_settings.copyWith(songSortMode: value)),
        onReorderSongs: _reorderSongList,
        onRunMaintenance: _runMaintenance,
        onSearchQueryChanged: (value) => setState(() => _searchQuery = value),
        youtubeSearch: _youtubeSearchState,
        onYoutubeSearch: _searchYoutube,
        onYoutubeChartChanged: _loadYoutubeChart,
        onYoutubeImport: _importFromYoutubeSearch,
        onCancelKaraokeTarget: _cancelKaraokeTarget,
        onYoutubeDecadeChanged: _changeDecade,
        onYoutubeGenreChanged: _changeGenre,
        onLoadYoutubeDecadeChart: _loadDecadeChart,
        onYoutubePreview: _previewYoutube,
        onSearchFilterModeChanged: (value) =>
            setState(() => _searchFilterMode = value),
        onAddSong: _addSong,
        onExportTrack: _exportCurrentTrack,
        queueLengths: [for (final q in _app.queueSlots) q.length],
        activeQueueSlot: _app.activeQueueSlot,
        onSelectQueueSlot: (i) => _app.switchQueueSlot(i),
        folderOrder: _settings.folderOrder,
        expandedFolders: _settings.expandedFolders.toSet(),
        onToggleFolder: _toggleFolder,
        onCreateFolder: _createFolder,
        onMoveFolder: _moveFolder,
        onMoveSongToFolder: _moveSongToFolder,
        onDropSongOnSong: _dropSongOnSong,
        onDuetMix: _duetMix,
        recordingDevices: _recording.devices,
        recordingDevice: _recording.deviceName,
        onRecordingDeviceChanged: (d) => _selectRecordingDevice(d),
        onRefreshRecordingDevices: () => _recording.refreshDevices(),
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
