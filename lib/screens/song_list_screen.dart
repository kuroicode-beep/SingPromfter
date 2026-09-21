import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, LogicalKeyboardKey;

import '../constants/app_constants.dart';
import '../controllers/app_controller.dart';
import '../controllers/armed_capture_session.dart'
    show ArmedSessionState, TakeEndMark, TakeStartMark, armedSessionStatusLabel;
import '../controllers/armed_transport.dart';
import '../controllers/capture_session.dart' show InputLevelBucket;
import '../controllers/compose_job_controller.dart';
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
import '../dialogs/take_mix_dialog.dart';
import '../dialogs/youtube_import_dialog.dart';
import '../models/app_destination.dart';
import '../models/composition.dart';
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
import '../services/take_stitch_service.dart';
import '../services/vocal_separation_client.dart';
import '../services/control_server.dart';
import '../utils/file_name_sanitizer.dart';
import '../widgets/song_list_screen_content.dart';
import '../widgets/training_session_card.dart';
import '../widgets/youtube_search_panel.dart';
import '../theme/app_theme.dart';
import '../widgets/center_alert.dart';
import '../widgets/snack_message.dart';
import '../widgets/prompter_keyboard_scope.dart';
import '../widgets/prompter_space_background.dart'
    show nextSpaceBackgroundLevel, spaceBackgroundLevelLabel;
import '../widgets/prompter_line_list_view.dart' show LineEditRequest;
import '../utils/ai_gate.dart';
import '../utils/platform_capabilities.dart';
import '../services/sync_client.dart';
import '../widgets/sync_section.dart';

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
    voiceRange: () =>
        TrainingVoiceRange.fromStorage(_settings.trainingVoiceRange),
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
  String? _playingCompositionId;
  Song? _recordingSong;
  int? _recordingSlot;
  int _recordingPitch = 0;
  int _recordingAlignMs = 0;

  /// Ctrl+R로 방금 물린 테이크. 실행취소를 누르면 되살리고, 시간이 지나면
  /// 파일까지 치운다. 목록에서만 빼 둔 상태라 파일은 아직 남아 있다.
  RecordingTake? _discardedTake;
  Timer? _discardPurgeTimer;

  /// 녹음 고정(Alt+R). 켜 두면 Space 하나로 재생과 녹음이 함께 시작·정지한다.
  /// 한 줄씩 조각을 받을 때 Space·R을 따로 누르면 그 사이만큼 박이 흔들린다.
  ///
  /// v5.16.0: 켜는 순간 마이크를 열어 세션 파일에 계속 받아 둔다(상시 캡처 세션).
  /// 스페이스는 「표시」만 찍고 곧바로 재생을 걸고, 저장할 때 그 구간을 잘라 낸다 —
  /// 스페이스마다 장치를 여느라 첫 음절을 잃던 0.45초가 사라진다.
  bool _recordArmed = false;

  /// 고정 토글이 도는 중 — 끝나기 전의 Alt+R은 버린다(세션을 두 번 여닫지 않게).
  bool _armToggleBusy = false;

  /// 고정 세션을 여닫는 일(켜기·끄기·재기동·끊김 뒷정리)을 한 줄로 세운다.
  /// 닫기와 열기가 겹치면 뒤늦게 끝난 닫기가 **새로 연 세션**을 「꺼짐」으로 덮어쓴다.
  Future<void> _armedSessionOps = Future<void>.value();

  /// 지금 열려 있는 고정 조각(시작 마크 + 그 순간 굳힌 컨텍스트). 없으면 null.
  _ArmedOpenTake? _armedTake;

  /// 고정 조각 저장 줄 — 한 번에 하나씩 자르고 등록한다.
  /// 🔴 스페이스 경로에서는 절대 기다리지 않는다. 기다리면 다음 조각을 못 건다.
  Future<void> _armedSaveChain = Future<void>.value();

  /// 「고정 중에는 보컬 1채널」 안내를 이미 했는가(실행당 한 번이면 충분하다).
  bool _armedMonoNoticeShown = false;

  /// 장치·게인 변경 뒤의 세션 재기동을 잠깐 늦추는 타이머.
  Timer? _armedRestartTimer;

  /// 재기동 본체([_restartArmedSession])가 도는 중인가.
  bool _armedRestarting = false;

  /// 장치·게인 변경으로 재기동이 **예약됐거나 도는 중**인가. 옛 세션은 곧 닫히므로
  /// 그사이에는 마크를 받지 않는다 — 받으면 음악만 나오고, 닫히는 세션에 찍힌 조각은
  /// 아무도 자르지 않아 다음 부팅의 「복구됨」으로만 돌아온다.
  ///
  /// 플래그를 따로 세우지 않고 타이머를 직접 본다 — 고정 해제·끊김·종료가 타이머를
  /// 취소해도 「예약 중」으로 굳는 값이 없다(굳으면 스페이스가 영영 거절된다).
  bool get _armedRestartPending =>
      (_armedRestartTimer?.isActive ?? false) || _armedRestarting;

  /// Ctrl+R이 「저장 안 된 직전 시도」 대신 그 앞의 멀쩡한 테이크를 물리지 않게 한다.
  final LastTakeGuard _lastTakeGuard = LastTakeGuard();

  /// 이번 세션에서 입력이 살아 있는 걸 확인했는가. 매번 1초씩 재면 조각을
  /// 받는 흐름이 끊겨서, 한 번 확인하면 장치가 바뀔 때까지 믿는다.
  bool _inputVerified = false;
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
    discardLastRecording: _discardLastRecording,
    toggleRecordArm: _toggleRecordArm,
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
    _recording = RecordingController(pathBuilder: _buildRecordingPath)
      ..addListener(_onPlaybackStateChanged);
    // 캡처 즉사(장치 열기 실패 등)를 사용자에게 바로 알린다 — 유령 '녹음 중'
    // 상태로 남아 파일 없이 끝나던 실사고 방지(v5.4.1).
    _recording.onError = _showSnack;
    // 조각 파일의 t=0이 곡의 어디였는지는 컨트롤러가 프레임 줄마다 이 값을
    // 찍어 역산한다. 재생을 먼저 걸어 기다림을 없앴기 때문에 「녹음을 건
    // 순간의 위치」는 장치가 열리는 0.45초만큼 이르다.
    _recording.songPositionProbe = () => _playback.state.value.playing
        ? _playback.precisePosition.inMilliseconds
        : null;
    // 고정 세션이 죽으면(장치 뽑힘·멈춤) 끊긴 데까지 살리고 고정을 푼다.
    _recording.onSessionLost = _handleSessionLost;
    // 녹음 목록을 못 썼으면 큰 경고로 알린다 — 조용히 넘기면 다음 실행에서
    // 방금 녹음이 목록에 없다.
    _recordingLibrary.onSaveFailed = _alertRecordingIndexSaveFailed;
    // 아웃트로를 부르는 중에 다음 곡으로 넘어가지 않도록 막는다.
    // 고정 조각은 isRecording이 아니라 isTakeOpen으로 선다 — 둘을 함께 본다.
    _playback.isRecordingProvider = () => _isCapturing;
    // 우하단 '녹음 중' 배지가 듣는 표시용 거울 — 잠금 배지와 같은 패턴.
    _recording.addListener(_syncRecordingView);
    // 창을 X로 닫아도 앱이 띄운 서버(분리·STT)가 남지 않게 — dispose는
    // 창 파괴 경로에서 안 불릴 수 있어 종료 요청 훅에서 먼저 끈다.
    _exitListener = AppLifecycleListener(
      onExitRequested: () async {
        _app.stopManagedServers();
        await _shutdownCapture();
        return AppExitResponse.exit;
      },
    );
    // 따라하기 세션 상태 변화 → 러너 카드 갱신.
    _trainingSession.addListener(_onPlaybackStateChanged);
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
    _playback.recordingView.value = _isCapturing;
  }

  /// 테이크 녹음(R)이든 고정 조각이든 **지금 소리를 받고 있는가**.
  /// 배지·자동 다음곡 차단·조작판 표시가 모두 이 값을 본다.
  bool get _isCapturing => _recording.isRecording || _recording.isTakeOpen;

  /// 조작판 고정 글자에 넣을 문구. 고정이 꺼져 있으면 null.
  ///
  /// 세션이 잠깐 「꺼짐」인 순간(켜는 첫 프레임·장치 변경 재기동의 닫힌 틈)에도
  /// 고정은 켜져 있다 — 빈 글자 대신 「여는 중」으로 보여 준다. 그사이의 스페이스는
  /// 어차피 거절되므로 글자와 동작이 맞는다.
  String? get _armedStatusLabel {
    if (!_recordArmed) return null;
    final label = _recording.sessionStatusLabel;
    if (label.isNotEmpty) return label;
    return armedSessionStatusLabel(
      state: ArmedSessionState.opening,
      checked: false,
      bucket: InputLevelBucket.none,
    );
  }

  /// 앱 종료 직전 — 고정 세션의 ffmpeg를 확실히 끝낸다.
  ///
  /// 고아 ffmpeg를 이름·PID로 죽일 수 없는 PC다(다른 작업의 ffmpeg가 상시 돈다).
  /// 여기서 우리 핸들로 끝내지 못하면 `-t` 상한(45분)까지 마이크를 쥐고 남는다.
  Future<void> _shutdownCapture() async {
    _armedRestartTimer?.cancel();
    // 부르던 조각이 있으면 끝을 찍어 저장 줄에 올리고 기다린다. 못 끝내도 마크가
    // 사이드카에 남아(목록 등록을 확인한 뒤에만 뺀다) 다음 실행이 「복구됨」 조각으로
    // 되살린다.
    //
    // 상한이 3초인 이유: 긴 조각(수 분 = 수십 MB)은 자르고 목록에 올리는 데 0.3초를
    // 넘긴다. 짧게 끊으면 방금 부른 조각이 「복구됨」으로만 돌아온다. 저장 줄은 등록이
    // 끝나는 대로 풀리므로 짧은 조각은 체감 지연이 없다.
    _endArmedTake();
    await _armedSaveChain.timeout(const Duration(seconds: 3), onTimeout: () {});
    await _recording.shutdown(cap: const Duration(seconds: 1));
  }

  AppLifecycleListener? _exitListener;

  @override
  void dispose() {
    for (final timer in _pendingDeleteTimers.values) {
      timer.cancel();
    }
    // Ctrl+R로 물려 둔 테이크는 파일이 남아 있다 — 앱이 닫히면 치운다.
    _discardPurgeTimer?.cancel();
    final discarded = _discardedTake;
    if (discarded != null) {
      unawaited(_recordingLibrary.purgeFiles(discarded));
    }
    _playback.state.removeListener(_onPlaybackStateChanged);
    _playback.lineIndex.removeListener(_onPlaybackStateChanged);
    _importJobs.removeListener(_onPlaybackStateChanged);
    _exitListener?.dispose();
    _armedRestartTimer?.cancel();
    // 리스너를 먼저 뗀다 — 아래 shutdown이 상태를 바꾸며 알리는데, 폐기 중인
    // 화면에 setState가 들어가면 안 된다.
    _recording.removeListener(_onPlaybackStateChanged);
    _recording.removeListener(_syncRecordingView);
    _app.composeJobs.removeListener(_onPlaybackStateChanged);
    // dispose는 기다릴 수 없다. 'q'부터 보내 정상 종료할 틈을 주고(세션 파일·사이드카
    // 정리), 바로 아래 컨트롤러 dispose가 핸들로 확실히 끊는다. 못 치운 파일은
    // 다음 실행의 복구가 치운다.
    unawaited(_recording.shutdown(cap: const Duration(seconds: 1)));
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
    _reportRecordingIndexState();
    await _dailyGoals.load();
    await _app.bootstrap();
    // 저장해 둔 녹음 입력 장치를 먼저 지정한 뒤 목록을 읽는다 —
    // refreshDevices는 미지정일 때만 첫 장치를 채우므로 순서가 중요하다.
    final savedDevice = _settings.recordingDevice;
    if (savedDevice != null && savedDevice.isNotEmpty) {
      _recording.deviceName = savedDevice;
    }
    // 마이크 장치 열거는 ffmpeg DirectShow라 모바일에서는 시도하지 않는다.
    if (PlatformCapabilities.hasDeviceRecording) {
      unawaited(_recording.refreshDevices());
      // 지난 실행이 남긴 고정 세션(앱이 죽었거나 저장을 못 끝낸 조각)을 되살린다.
      // 녹음 목록·곡 목록을 읽은 **뒤**여야 등록과 반주 자르기가 된다. 파일 IO라
      // 부팅을 막지 않게 기다리지 않는다.
      unawaited(_recoverArmedSessions());
    }
    // MCP 제어 API — 루프백 전용, 실패해도 앱 동작에 영향 없음.
    // 모바일은 백그라운드 수명이 보장되지 않고 PC에서 폰 루프백에 닿지도
    // 못한다 — 서버를 띄우지 않는다.
    if (PlatformCapabilities.hasControlServer) {
      await _controlServer.start();
    }
  }

  Future<void> _loadSong(Song song, {int? preferredSlot}) =>
      _playback.loadSong(song, preferredSlot: preferredSlot);

  Future<void> _togglePlayPause() async {
    if (!_recordArmed) {
      await _playback.togglePlayPause();
      return;
    }
    // 🔴 분기의 기준은 동기 상태(isTakeOpen)다. `playing`은 이벤트로 늦게 서는
    // 값이라 그걸로 시작·정지를 가르면, 재생 직후의 스페이스가 조각을 또 열거나
    // **멈춘 화면에서 유령 녹음**이 돈다(실사고 — armed_transport.dart 참고).
    // 앞선 스페이스의 재생·정지 호출이 아직 안 끝났으면(busy) 버린다.
    final action = armedSpaceAction(
      busy: _armedTransportBusy,
      sessionReady: _recording.isSessionReady,
      takeOpen: _recording.isTakeOpen,
      playing: _playback.state.value.playing,
    );
    if (action == ArmedSpaceAction.ignore) return;
    _armedTransportBusy = true;
    try {
      await _armedSpace(action);
    } finally {
      _armedTransportBusy = false;
    }
  }

  bool _armedTransportBusy = false;

  /// 녹음 고정 중의 스페이스 — 「표시」만 찍고 곧바로 재생을 건다(설계 3.3).
  ///
  /// 마이크는 고정을 켤 때 이미 열려 세션 파일에 받고 있다. 예전에는 스페이스마다
  /// ffmpeg를 띄워서, 장치가 열리는 0.45초 동안 부른 첫 음절을 구할 수 없었다.
  Future<void> _armedSpace(ArmedSpaceAction action) async {
    switch (action) {
      case ArmedSpaceAction.ignore:
        return;
      case ArmedSpaceAction.refuseNotReady:
        // 🔴 재생도 걸지 않는다. 음악만 나오고 녹음은 안 되는 조용한 실패가
        // 제일 비싸다 — 다 부르고 나서야 안다.
        _showSnack(_kArmedNotReadyMessage);
        return;
      case ArmedSpaceAction.pauseOnly:
        // 조각 없이 재생만 돌고 있었다 — 그냥 멈춘다.
        await _playback.forcePause();
      case ArmedSpaceAction.endTake:
        // 끝 마크(동기) → 정지 → 저장은 줄에 올리고 **기다리지 않는다**.
        // 정지 호출을 저장보다 먼저 내보낸다 — 반주가 조각 뒤로 더 실리지 않게.
        final closed = _markArmedTakeEnd();
        final pausing = _playback.forcePause();
        if (closed != null) _enqueueArmedSave(closed.$1, closed.$2);
        await pausing;
      case ArmedSpaceAction.startTake:
        final song = _selectedSong;
        if (song == null) {
          _showSnack('먼저 곡을 선택해 주세요.');
          return;
        }
        // 시작 마크(동기) → 같은 스택에서 곧바로 재생. 첫 await 전에 isTakeOpen이
        // 뒤집히므로 재진입·유령 녹음이 구조적으로 없다.
        final open = _markArmedTakeStart(song, playbackAlreadyRunning: false);
        if (open == null) {
          _showSnack(_kArmedNotReadyMessage);
          return;
        }
        final started = await _playback.forcePlay();
        // 재생이 막혔다(반주 없음 등 — 사유는 재생 쪽이 알렸다). 음악 없이 혼자
        // 도는 조각을 남기지 않는다.
        if (!started && identical(_armedTake, open)) {
          _recording.cancelOpenTake();
          _armedTake = null;
          // 재생 사유 토스트만으로는 「녹음도 안 걸렸다」를 알 수 없다 — 예전(v5.15)에는
          // 같은 조작으로 녹음이 걸렸다. 고정 글자도 그대로 「마이크 열림」이라, 말해
          // 주지 않으면 다 부르고 나서야 안다.
          _showSnack(kArmedPlaybackBlockedMessage);
        }
    }
    if (mounted) setState(() {});
  }

  static const _kArmedNotReadyMessage = '마이크를 여는 중입니다 — 잠시만요';

  /// 고정 조각의 시작을 찍는다(**동기**). 준비가 안 됐으면 null.
  ///
  /// 컨텍스트(곡·슬롯·키·재생 파일·템포)는 여기서 굳힌다 — 저장은 한참 뒤에
  /// 도는데, 그때 화면 상태를 다시 읽으면 그사이 고른 다른 곡에 붙는다.
  /// 위치(P0)와 마크는 맨 끝에 붙여 찍어, 호출부가 곧바로 재생을 걸 수 있게 한다.
  _ArmedOpenTake? _markArmedTakeStart(
    Song song, {
    required bool playbackAlreadyRunning,
  }) {
    // 장치·게인 변경으로 곧 닫힐 세션이다 — 스페이스·R 모두 여기서 막힌다(호출부가
    // 「마이크를 여는 중」으로 알리고, 스페이스는 재생도 걸지 않는다).
    if (_armedRestartPending) return null;
    final snapshot = _playback.snapshot;
    final context = ArmedTakeContext(
      songId: song.id,
      songTitle: song.title,
      trackSlot: snapshot.trackSlot,
      pitchSemitones: _settings.pitchForSong(song.id, snapshot.trackSlot),
      activeAudioPath: snapshot.activeAudioPath,
      tempoScale: snapshot.tempoScale,
    );
    final contextJson = context.toJson();
    final mark = _recording.markTakeStart(
      // 틱을 기다리지 않은 지금의 위치 — position.value는 최대 17ms 낡아 있다.
      songPositionMs: _playback.precisePosition.inMilliseconds,
      playbackAlreadyRunning: playbackAlreadyRunning,
      context: contextJson,
    );
    if (mark == null) return null;
    return _armedTake = _ArmedOpenTake(mark, context);
  }

  /// 열린 고정 조각의 끝을 찍는다(**동기**). 저장할 것이 있으면 (조각, 끝 마크)를 준다.
  (_ArmedOpenTake, TakeEndMark)? _markArmedTakeEnd() {
    final open = _armedTake;
    _armedTake = null;
    final end = _recording.markTakeEnd();
    if (open == null || end == null) return null;
    return (open, end);
  }

  /// 열린 고정 조각을 끝내고 저장 줄에 올린다. 재생은 건드리지 않는다.
  /// 열린 조각이 없으면 아무것도 하지 않는다.
  void _endArmedTake() {
    final closed = _markArmedTakeEnd();
    if (closed != null) _enqueueArmedSave(closed.$1, closed.$2);
  }

  /// 조각 저장을 직렬 줄 끝에 붙인다. 앞의 저장이 실패해도 줄은 이어진다 —
  /// [_saveArmedTake]가 예외를 밖으로 내지 않는다.
  /// [lostMessage]는 세션이 죽어 끊긴 데까지 살리는 조각에만 준다(끊김 사유).
  void _enqueueArmedSave(
    _ArmedOpenTake open,
    TakeEndMark? end, {
    String? lostMessage,
  }) {
    _armedSaveChain = _armedSaveChain.then(
      (_) => _saveArmedTake(open, end, lostMessage: lostMessage),
    );
  }

  /// 고정 조각 하나를 세션 파일에서 잘라 테이크로 등록한다(저장 줄 안에서만 돈다).
  /// [end]가 null이면 세션이 죽어 끝을 못 찍은 조각 — 파일 끝까지 살린다.
  ///
  /// 🔴 테이크를 못 만들고 끝나는 길(너무 짧음·저장 실패)은 [_lastTakeGuard]에 남긴다.
  /// 안 남기면 곧이은 Ctrl+R이 **그 앞의 멀쩡한 조각**을 물린다.
  Future<void> _saveArmedTake(
    _ArmedOpenTake open,
    TakeEndMark? end, {
    String? lostMessage,
  }) async {
    try {
      final id = const Uuid().v4();
      final sliced = await _recording.sliceTake(
        open.mark,
        end,
        outputPath: await _buildRecordingPath('$id.wav'),
      );
      if (sliced == null) {
        // 마크 구간이 0.5초 미만 — 눌렀다 뗀 수준이다.
        _lastTakeGuard.noteDropped(kTakeDroppedTooShortNote);
        _showSnack('너무 짧아 저장하지 않았습니다');
        return;
      }
      if (!sliced.ok) {
        _lastTakeGuard.noteDropped(kTakeDroppedSaveFailedNote);
        _alertArmedSaveFailed(sliced.message, lostMessage: lostMessage);
        return;
      }
      if (sliced.truncated || sliced.filledGapMs > 0) {
        debugPrint('고정 조각 저장: ${sliced.message}');
      }
      final context = open.context;
      await _commitTake(
        songId: context.songId,
        songTitle: context.songTitle,
        fileName: sliced.fileName,
        durationMs: sliced.durationMs,
        trackSlot: context.trackSlot,
        pitchSemitones: context.pitchSemitones,
        songPositionMs: sliced.songPositionMs,
        sourceAudioPath: context.activeAudioPath,
        tempoScale: context.tempoScale,
        peakDbfs: sliced.peakDbfs,
        leadInMs: sliced.leadInMs,
        savedMessage: armedTakeSavedMessage(
          songPositionMs: sliced.songPositionMs,
          leadInMs: sliced.leadInMs,
          durationMs: sliced.durationMs,
          timelineSuspect: sliced.timelineSuspect,
          // 끝이 잘렸거나 구멍을 메웠으면 그 자리에서 알린다 — 평소 토스트와 똑같으면
          // 모르고 넘어가, 조각을 쌓은 뒤에야 들어 보고 안다.
          truncated: sliced.truncated,
          filledGapMs: sliced.filledGapMs,
        ),
        // 🔴 목록이 디스크에 닿은 **뒤에만** 세션의 저장 대기열에서 뺀다. 먼저 빼면
        // 그사이 앱이 끝났을 때 WAV는 있는데 목록에도 없고 복구도 안 된다.
        // 등록에 실패하면 마크가 남아 다음 실행이 「복구됨」으로 되살린다.
        onIndexed: () => _recording.confirmTakeSaved(open.mark),
      );
    } catch (e, stack) {
      debugPrint('고정 조각 저장 실패: $e\n$stack');
      _lastTakeGuard.noteDropped(kTakeDroppedSaveFailedNote);
      _alertArmedSaveFailed('$e', lostMessage: lostMessage);
    }
  }

  /// 녹음 목록(recordings.json) 저장이 실패했다 — 그대로 끄면 목록에서 빠진다.
  void _alertRecordingIndexSaveFailed(String message) {
    if (!mounted) return;
    CenterAlert.show(
      context,
      title: '녹음 목록을 저장하지 못했습니다',
      detail:
          '$message\n\n'
          '· 녹음 파일 자체는 녹음 폴더에 남아 있습니다\n'
          '· 다음 저장이 성공하면 목록도 함께 기록됩니다',
    );
  }

  /// 부팅 때 녹음 목록을 정본에서 못 읽었으면 알린다. 정상이면 아무것도 안 한다.
  void _reportRecordingIndexState() {
    final state = _recordingLibrary.loadState;
    if (state == RecordingIndexState.ok || !mounted) return;
    final recovered = state == RecordingIndexState.recoveredFromBackup;
    CenterAlert.show(
      context,
      title: recovered ? '녹음 목록을 백업에서 되살렸습니다' : '녹음 목록을 읽지 못했습니다',
      detail: recovered
          ? '목록 파일이 깨져 있어 직전 백업(recordings.json.bak)을 읽었습니다.\n\n'
                '· 가장 최근의 변경 한 번이 빠졌을 수 있습니다\n'
                '· 녹음 파일은 녹음 폴더에 그대로 있습니다'
          // 「못 읽음」에는 깨진 파일과 **지금 못 여는** 파일(잠김·오프라인)이 다 들어
          // 있다. 뒤쪽은 .corrupt 사본이 생기지 않으니 그렇게 약속하지 않는다.
          : '목록 파일을 지금 읽을 수 없어 빈 목록으로 시작합니다.\n\n'
                '· 목록 파일은 지우지 않았습니다 — 다음 저장 때 다시 읽어 합칩니다\n'
                '· 파일이 깨진 것이면 그때 .corrupt 사본으로 옆에 남깁니다\n'
                '· 녹음 파일은 녹음 폴더에 그대로 있습니다',
    );
  }

  /// 조각을 못 잘랐다 — 큰 경고로 멈춰 세운다. 세션 파일은 지우지 않았으므로
  /// (컨트롤러가 마크를 대기열에 남긴다) 다음 실행의 복구가 다시 시도한다.
  ///
  /// [lostMessage]는 끊김 뒤의 저장일 때 준다 — 큰 경고는 한 장뿐이라 이 경고가
  /// 끊김 경고를 덮는다. 끊김 사유와 「고정이 꺼졌다」를 여기에 다시 담는다.
  void _alertArmedSaveFailed(String reason, {String? lostMessage}) {
    if (!mounted) return;
    final alert = armedSaveFailedAlert(
      reason: reason,
      lostMessage: lostMessage,
    );
    CenterAlert.show(context, title: alert.title, detail: alert.detail);
  }

  /// 고정 세션이 죽었다(장치 뽑힘·멈춤·상한에서 조각이 끊김) — 설계 3.6.
  /// 끊긴 데까지 살려 저장 → 재생 정지 → 고정 해제 → 큰 경고.
  void _handleSessionLost(String message, {TakeStartMark? openTake}) {
    final open = _armedTake;
    _armedTake = null;
    if (openTake != null) {
      // 화면이 들고 있던 조각과 같은 마크면 그 컨텍스트를 쓴다. 아니면 마크에
      // 실려 있던 컨텍스트로 되살린다(어느 쪽이든 소리는 버리지 않는다).
      final same =
          open != null &&
          open.mark.id == openTake.id &&
          open.mark.sessionId == openTake.sessionId;
      _enqueueArmedSave(
        same ? open : _ArmedOpenTake.fromMark(openTake),
        null,
        // 저장까지 실패하면 그 경고가 아래의 끊김 경고를 덮는다 — 사유를 실어 보낸다.
        lostMessage: message,
      );
    }
    final wasArmed = _recordArmed;
    _recordArmed = false;
    _armedRestartTimer?.cancel();
    // 세션 뒷정리는 저장이 끝난 뒤에, 다른 세션 작업과 겹치지 않게 한 줄로 세운다.
    unawaited(
      _runArmedSessionOp(() async {
        await _armedSaveChain;
        await _recording.closeSession();
      }),
    );
    // 끄는 도중에 끊긴 것이면 이미 풀린 고정이다 — 알릴 것이 없다.
    if (!wasArmed) return;
    unawaited(_playback.forcePause());
    if (!mounted) return;
    setState(() {});
    // 제목은 사유에 중립이고(상한 도달·재기동 무음도 이 길이다), 조각 줄은 완료형이
    // 아니다 — 저장은 이 경고 뒤에 돌아, 「너무 짧음」이나 실패로 끝날 수 있다.
    final alert = armedSessionLostAlert(
      message: message,
      hadOpenTake: openTake != null,
    );
    CenterAlert.show(context, title: alert.title, detail: alert.detail);
  }

  /// 녹음 전 입력 점검 — 소리가 안 들어오면 **큰 경고로 막는다.**
  ///
  /// 무음은 헤드폰으로 확인이 안 된다. FLOW 8은 PC로 가는 소리만 마스터를
  /// 지나서, 마스터가 내려가 있으면 귀에는 멀쩡히 들리는데 녹음만 무음이다
  /// (2026-09-15·09-21 같은 원인으로 반복). 사후 경고만으로는 이미 늦어서
  /// 시작 전에 한 번 재고 막는다.
  Future<bool> _verifyInputOrBlock() async {
    if (_inputVerified) return true;
    if (_settings.recordingDevice != null) {
      _recording.deviceName = _settings.recordingDevice;
    }
    final peak = await _recording.probeInputLevel();
    if (!mounted) return false;
    if (peak == null) {
      // 프로브 자체를 못 띄웠다 — 알리되 막지는 않는다(녹음까지 막을 근거는 아니다).
      //
      // 🔴 다시 재지도 않는다. 예전에는 여기서 「확인 안 됨」으로 남겨 둬서
      // 스페이스를 누를 때마다 4.5초짜리 점검이 다시 돌았고, 그동안 마이크가
      // 안 열려 조각 앞부분이 통째로 비었다. 무음은 저장 직후 경고가 따로 잡는다.
      _inputVerified = true;
      _showSnack('입력을 미리 확인하지 못했습니다. 그대로 진행합니다.');
      return true;
    }
    if (!isSilentTake(peak)) {
      _inputVerified = true;
      return true;
    }
    _showSilentInputAlert();
    return false;
  }

  /// 「입력에 소리가 없다」 큰 경고 — R 녹음 전 점검과 고정 세션의 점검이 같이 쓴다.
  void _showSilentInputAlert() {
    if (!mounted) return;
    CenterAlert.show(
      context,
      title: '녹음 입력에 소리가 없습니다',
      detail:
          '지금 녹음하면 무음만 저장됩니다.\n\n'
          '· 설정 > 녹음에서 입력 장치를 확인해 주세요\n'
          '· FLOW 8이면 마스터 노브와 1번 마이크 슬라이더가 내려가 있는지 보세요 '
          '(헤드폰에는 들려도 PC로 가는 소리만 죽습니다)\n'
          '· Ctrl+Alt+. 로 방송 점검을 돌려도 같이 잡힙니다',
    );
  }

  /// Alt+R — 녹음 고정을 켜고 끈다.
  ///
  /// 켜면 마이크를 열어 세션 파일에 받기 시작하고, 끄면 열린 조각을 저장한 뒤 닫는다.
  Future<void> _toggleRecordArm() async {
    // 🔴 재진입 금지. 여는 데 1.5초쯤 걸리는데(장치 0.6초+입력 점검 0.9초) 그사이의
    // 두 번째 Alt+R이 닫기를 겹쳐 걸면 세션이 꼬인다.
    if (_armToggleBusy) return;
    _armToggleBusy = true;
    try {
      if (_recordArmed) {
        // 끄는 안내는 _disarm이 저장을 기다리기 **전에** 띄운다.
        await _runArmedSessionOp(_disarm);
        return;
      }
      if (_selectedSong == null) {
        _showSnack('먼저 곡을 선택해 주세요.');
        return;
      }
      // R 녹음이 마이크를 쥐고 있다 — 같은 장치는 두 번 못 연다. 그 녹음을 몰래
      // 끝내지도 않는다(부르던 테이크가 잘린다).
      if (_recording.isRecording) {
        _showSnack('녹음 중에는 녹음 고정을 켤 수 없습니다. R로 정지한 뒤에 켜 주세요.');
        return;
      }
      await _runArmedSessionOp(_arm);
    } finally {
      _armToggleBusy = false;
    }
  }

  /// 고정 세션을 여닫는 일을 한 줄로 세운다. 실패해도 줄은 이어진다.
  Future<void> _runArmedSessionOp(Future<void> Function() op) {
    return _armedSessionOps = _armedSessionOps.then((_) => op()).catchError((
      Object e,
    ) {
      debugPrint('고정 세션 작업 실패: $e');
    });
  }

  /// 고정을 켠다 — 글자부터 바꾸고(「마이크 여는 중」) 세션을 연다.
  Future<void> _arm() async {
    _recordArmed = true;
    if (mounted) setState(() {});
    if (!await _openArmedSession()) return;
    if (!mounted || !_recordArmed) return;
    // 고정 중에는 반주 장치(2채널)를 열지 않는다 — 세션은 보컬 하나만 받는다.
    // 설정에 반주 장치가 있으면 2채널을 기대할 테니 한 번은 알려 준다.
    final wantsDual = (_settings.recordingBackingDevice ?? '').isNotEmpty;
    if (wantsDual && !_armedMonoNoticeShown) {
      _armedMonoNoticeShown = true;
      _showSnack('녹음 고정 중에는 보컬 1채널로 받습니다 — 조각은 원본 반주에 얹습니다');
      return;
    }
    _showSnack('녹음 고정 — 스페이스로 재생과 녹음이 함께 시작되고 함께 멈춥니다.');
  }

  /// 고정 세션을 열고 입력 점검(0.9초)까지 기다린다. 통과하면 true.
  /// 못 열었거나 무음이면 큰 경고를 띄우고 세션을 닫아 고정을 끈다.
  ///
  /// 점검을 세션 자신의 레벨 줄로 하므로 별도 프로브가 없다 — 예전에는 프로브를
  /// 띄웠다 닫고 다시 녹음을 여느라 장치를 두 번 열었다.
  Future<bool> _openArmedSession() async {
    if (_settings.recordingDevice != null) {
      _recording.deviceName = _settings.recordingDevice;
    }
    final live = await _recording.openSession(gain: _settings.recordingGain);
    // 기다리는 사이 세션이 끊겨 고정이 풀렸으면 그쪽(_handleSessionLost)이 이미 알렸다.
    if (!_recordArmed) return false;
    if (!live) {
      final reason = _recording.sessionError ?? '입력 장치를 열지 못했습니다.';
      await _abortArming();
      if (mounted) {
        // 큰 경고인 이유: 고정이 켜진 줄 알고 스페이스를 누르면 음악만 나오고
        // 녹음은 안 된다 — 토스트는 놓치기 쉽다.
        CenterAlert.show(
          context,
          title: '마이크를 열지 못해 녹음 고정을 켜지 못했습니다',
          detail:
              '$reason\n\n'
              '· 마이크 연결과 설정 > 녹음의 입력 장치를 확인해 주세요\n'
              '· 다른 프로그램이 마이크를 단독으로 쥐고 있지 않은지 보세요',
        );
      }
      return false;
    }
    // 점검이 끝나기 전에는 컨트롤러가 마크를 거절한다(스페이스 = 「여는 중」 안내).
    final peak = await _recording.sessionInputCheck;
    if (!_recordArmed) return false;
    if (isSilentTake(peak)) {
      await _abortArming();
      _showSilentInputAlert();
      return false;
    }
    _inputVerified = true;
    if (mounted) setState(() {});
    return true;
  }

  /// 켜다 만 고정을 되돌린다 — 세션을 닫고 글자를 지운다.
  Future<void> _abortArming() async {
    await _recording.closeSession();
    _recordArmed = false;
    if (mounted) setState(() {});
  }

  /// 고정을 끈다 — 열린 조각은 끝을 찍어 저장하고, 저장 줄이 빈 뒤에 세션을 닫는다.
  /// (먼저 닫아도 소리는 안 잃지만, 저장을 기다려야 세션 파일이 곧바로 지워진다.)
  Future<void> _disarm() async {
    _recordArmed = false;
    _armedRestartTimer?.cancel();
    // 끄는 안내는 저장을 기다리기 **전에** 띄운다. 뒤에 띄우면 마지막 조각의 저장
    // 결과·무음 경고(12초)를 0.2초 만에 덮는다 — 토스트는 한 장뿐이다. 이렇게 하면
    // 열린 조각이 있을 때 「껐습니다」가 잠깐 보인 뒤 저장 결과가 마지막에 남는다.
    _showSnack('녹음 고정을 껐습니다.');
    _endArmedTake();
    if (mounted) setState(() {});
    await _armedSaveChain;
    await _recording.closeSession();
    if (mounted) setState(() {});
  }

  /// 입력 장치·게인이 바뀌었다 — 열린 조각을 곧바로 닫아 저장하고(옛 설정으로
  /// 받은 소리다), 세션 재기동은 잠깐 늦춘다.
  ///
  /// 늦추는 이유: 입력 볼륨 슬라이더는 끄는 동안 값을 연달아 보낸다. 그때마다
  /// 재기동하면(닫기 0.3초+열기 0.6초+점검 0.9초) 고정이 한참 먹통이 된다.
  void _scheduleArmedRestart() {
    _endArmedTake();
    _armedRestartTimer?.cancel();
    _armedRestartTimer = Timer(const Duration(milliseconds: 500), () {
      // 타이머가 끝난 순간부터 본체가 줄에서 차례를 받을 때까지도 「재기동 중」이다.
      // 본체는 반드시 돌고(줄은 실패해도 이어진다) finally에서 내린다.
      _armedRestarting = true;
      unawaited(_runArmedSessionOp(_restartArmedSession));
    });
  }

  /// 새 장치·게인으로 세션을 다시 연다(입력 점검도 다시 돈다).
  /// 예약된 순간부터(디바운스 500ms 포함) 끝날 때까지 스페이스·R은 「마이크를 여는
  /// 중」으로 거절된다([_armedRestartPending]).
  Future<void> _restartArmedSession() async {
    _armedRestarting = true;
    try {
      if (!_recordArmed) return;
      _endArmedTake();
      if (mounted) setState(() {});
      await _armedSaveChain;
      await _recording.closeSession();
      if (!_recordArmed) return;
      await _openArmedSession();
    } finally {
      _armedRestarting = false;
    }
  }

  Future<void> _stopPlayback() => _playback.stop();

  Future<void> _restartPlayback() => _playback.restart();

  Future<void> _applyAccessibilityPreset(String preset) =>
      _updateSettings(PrompterSettingsService.preset(_settings, preset));

  /// PC에서 곡을 받아온다(폰 전용). 주소·코드는 다이얼로그에서 받는다.
  Future<void> _pullFromPc() async {
    await SyncPullDialog.show(
      context,
      initialAddress: _settings.syncServerAddress,
      onPull: (address, code, onProgress) async {
        final outcome = await SyncClient().pull(
          address: address,
          pairingCode: code,
          pendingFavorites: _settings.pendingFavorites,
          onProgress: onProgress,
          onPushed: () {
            // 올라간 것만 비운다. 실패하면 남겨 다음에 다시 시도한다.
            _updateSettings(_settings.copyWith(pendingFavorites: const {}));
          },
        );
        if (outcome.ok) {
          // 성공한 주소는 기억해 둔다 — 매번 IP를 외워 적게 하지 않는다.
          await _updateSettings(
            _settings.copyWith(syncServerAddress: address.trim()),
          );
          // 받은 곡을 화면에 반영한다(백업 반입과 같은 흐름).
          final songs = await _repo.loadSongs();
          if (mounted) setState(() => _songs = songs);
          final next = _selectedSong ?? (songs.isNotEmpty ? songs.first : null);
          if (next != null) await _loadSong(next);
        }
        return outcome.message;
      },
    );
  }

  Future<void> _updateSettings(PrompterSettings next) async {
    final syncChanged =
        next.syncServerEnabled != _settings.syncServerEnabled;
    // 입력 장치를 바꾸면 이전 확인은 무효다 — 새 장치로 다시 재야 한다.
    if (next.recordingDevice != _settings.recordingDevice ||
        next.recordingBackingDevice != _settings.recordingBackingDevice) {
      _inputVerified = false;
    }
    // 고정 세션은 장치·게인을 ffmpeg 인자로 물고 떠 있다 — 바뀌면 다시 열어야 먹는다.
    // (반주 장치는 세션과 무관하다: 고정 중에는 보컬 1채널만 받는다.)
    final captureChanged =
        next.recordingDevice != _settings.recordingDevice ||
        next.recordingGain != _settings.recordingGain;
    await _app.updateSettings(next);
    if (captureChanged && _recordArmed) _scheduleArmedRestart();
    // 동기화 토글은 바인딩 주소를 바꾼다 — 재기동하지 않으면 다음 실행에야
    // 반영된다(껐는데 LAN에 열려 있는 상태가 더 위험하다).
    if (syncChanged && PlatformCapabilities.hasControlServer) {
      await _controlServer.applySettings();
    }
    // 로컬AI를 끄면 작곡 탭이 비활성화되므로 그 화면에 남지 않게 한다.
    if (!next.localAiActive &&
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
      comment:
          'AI 보정'
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
      var dest = File('${dir.path}${Platform.pathSeparator}$stem.mp3');
      // 같은 이름이 있으면 덮어쓰지 않고 번호를 붙인다.
      var n = 2;
      while (dest.existsSync()) {
        dest = File('${dir.path}${Platform.pathSeparator}$stem ($n).mp3');
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

  Future<void> _mixTake(RecordingTake take, {bool silent = false}) async {
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

    if (!silent) _showSnack('반주와 합치는 중...');
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
    _showSnack(silent ? '합친 곡이 준비됐습니다. "듣기"로 바로 들어보세요.' : '합쳤습니다. "합친 곡 듣기"로 확인해 보세요.');
  }

  /// 믹스 설정 다이얼로그 — 밸런스·리버브·노이즈 제거·보컬 분리.
  Future<void> _showTakeMixSettings(RecordingTake take) async {
    final result = await TakeMixDialog.show(
      context,
      take: take,
      localAiEnabled: _settings.localAiActive,
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
    if (!_settings.localAiActive) {
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
      final destPath = '${(await _recordingLibrary.directory()).path}/$sepName';
      await File(result.vocalsPath!).copy(destPath);
      await _recordingLibrary.update(take.copyWith(separatedFileName: sepName));
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
    _showSnack(
      devices.isEmpty
          ? '입력 장치를 찾지 못했습니다. 마이크 연결과 ffmpeg 설치를 확인해 주세요.'
          : '입력 장치 ${devices.length}개를 찾았습니다.',
    );
  }

  /// 설정 패널 — 마이크 테스트 토글.
  Future<void> _toggleMicTest() async {
    if (_recording.isRecording) {
      _showSnack('녹음 중에는 마이크 테스트를 할 수 없습니다.');
      return;
    }
    // 고정 세션이 같은 장치를 쥐고 있다 — 두 번 열면 세션이 흔들린다.
    // 입력 상태는 조작판의 고정 글자(입력 좋음·작음·없음)가 이미 보여 준다.
    if (_recording.isSessionOpen) {
      _showSnack('녹음 고정 중에는 마이크 테스트를 할 수 없습니다 — 입력 상태는 조작판의 고정 글자에 나옵니다.');
      return;
    }
    if (_recording.isProbing) {
      await _recording.stopLevelProbe();
      return;
    }
    if (_settings.recordingDevice != null) {
      _recording.deviceName = _settings.recordingDevice;
    }
    // 2채널이면 반주 채널도 같이 연다 — 실제 녹음과 같은 조건으로 확인한다.
    _recording.backingDeviceName = _settings.recordingBackingDevice;
    final ok = await _recording.startLevelProbe(
      gain: _settings.recordingGain,
      includeBacking: true,
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
    if (!take.hasMix &&
        (take.hasAccompaniment || take.sourceAudioPath != null)) {
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
    _showSnack(copied == 0 ? '내보낼 파일이 없습니다.' : '$copied개 파일을 내보냈습니다: $folder');
  }

  Future<void> _playTakeMix(RecordingTake take) async {
    final mixed = take.mixedFileName;
    if (mixed == null || mixed.isEmpty) return;
    final path = '${(await _recordingLibrary.directory()).path}/$mixed';
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
              s.availableTrackSlots.length <
              AppConstants.backingTrackSlots.length,
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
    final freeSlot = AppConstants.backingTrackSlots.firstWhere(
      (s) => !usedSlots.contains(s),
      orElse: () => -1,
    );
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
      ...Song.folderNames(
        _songs,
      ).where((f) => !_settings.folderOrder.contains(f)),
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
    final week = start == null
        ? null
        : VocalCourse.weekFor(start, DateTime.now());
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
    if (_isCapturing) {
      _showSnack('녹음 중에는 다음 곡으로 넘어가지 않습니다. 녹음을 먼저 정지해 주세요.');
      return;
    }
    await _playback.onSongCompleted();
  }

  Future<void> _toggleRecording() async {
    // 고정 중의 R은 세션에 마크만 찍는다 — 마이크는 이미 세션이 쥐고 있다.
    if (_recordArmed) {
      _armedRecordKey();
      return;
    }
    if (_recording.isRecording) {
      await _finishRecording();
      return;
    }
    // 고정을 끄는 중(저장 줄을 비우고 세션을 닫는 1초 남짓)에는 장치가 아직 세션
    // 몫이다. 여기서 녹음을 걸면 「시작하지 못했습니다」만 뜬다 — 이유를 말해 준다.
    if (_recording.isSessionOpen) {
      _showSnack('녹음 고정을 정리하는 중입니다 — 잠시 뒤에 다시 눌러 주세요.');
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
    // 이번 세션 첫 녹음이면 입력을 한 번 재고 시작한다.
    if (!await _verifyInputOrBlock()) return;

    // 설정에서 고른 입력 장치·볼륨을 적용한다.
    if (_settings.recordingDevice != null) {
      _recording.deviceName = _settings.recordingDevice;
    }
    // 반주(PC 재생) 장치가 설정돼 있으면 독립 2채널로 녹음한다.
    _recording.backingDeviceName = _settings.recordingBackingDevice;
    final wantsDual = (_settings.recordingBackingDevice ?? '').isNotEmpty;
    final dual = wantsDual && _recording.canRecordDual;

    final id = const Uuid().v4();
    final started = await _recording.start(
      '$id.wav',
      gain: _settings.recordingGain,
      backingFileName: dual ? '${id}_acc.wav' : null,
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
    if (dual) {
      _showSnack('2채널 녹음을 시작했습니다 — 보컬과 반주를 따로 받습니다.');
    } else if (wantsDual) {
      _showSnack('반주 입력 장치를 찾지 못해 보컬 1채널로 녹음합니다. 설정에서 장치를 확인해 주세요.');
    } else {
      _showSnack('녹음을 시작했습니다. 스피커로 들으면 반주가 섞이니 헤드폰을 권장합니다.');
    }
  }

  Future<void> _finishRecording() async {
    final result = await _recording.stop();
    final song = _recordingSong;
    _recordingSong = null;
    if (result == null || song == null) return;
    // 프레임 줄로 역산한 좌표가 있으면 그게 정본이다. 없으면(멈춘 채 녹음)
    // 녹음을 건 순간의 위치를 그대로 쓴다.
    final anchor = result.songAnchorMs;
    if (anchor != null) _recordingAlignMs = anchor < 0 ? 0 : anchor;

    // 실수로 누른 R만 걸러낸다.
    //
    // 예전 기준은 3초였는데, 한 줄씩 끊어 녹음하면 조각이 1~2초라
    // **정상 녹음이 통째로 삭제됐다**(2026-09-21 실사고 — 한 줄씩 받은 조각이
    // 거의 다 사라졌다). 실수로 누른 것은 이제 Ctrl+R로 물릴 수 있으니
    // 자동 삭제는 「눌렀다 뗀 수준」만 거른다.
    if (result.duration < kMinimumTakeDuration) {
      await RecordingStore().deleteFile(result.fileName);
      final tooShortBacking = result.backingFileName;
      if (tooShortBacking != null) {
        await RecordingStore().deleteFile(tooShortBacking);
      }
      // 곧이은 Ctrl+R이 그 앞의 멀쩡한 테이크를 물리지 않게 한다(고정 조각과 같은 구멍).
      _lastTakeGuard.noteDropped(kRecordingDroppedTooShortNote);
      if (mounted) _showSnack('녹음이 너무 짧아 저장하지 않았습니다.');
      return;
    }

    // 2채널로 받았으면 반주 채널이 곧 테이크의 반주다 — 같은 프로세스가
    // 동시에 시작했으므로 정렬 보정이 0이고, 잘라낼 필요도 없다.
    final recordedBacking = result.backingFileName;
    final dual = recordedBacking != null && recordedBacking.isNotEmpty;

    // 반주 장치가 늦게 열린 만큼 앞에 무음을 덧대 보컬과 시작점을 맞춘다.
    // 안 맞추면 반주가 수백 ms 앞서 들린다(2026-09-21 실측 790ms).
    if (dual && result.backingSkewMs > 0) {
      final accPath =
          '${(await _recordingLibrary.directory()).path}/$recordedBacking';
      final aligned = await TakeMixService().padHead(
        path: accPath,
        delayMs: result.backingSkewMs,
      );
      if (!aligned.success) {
        debugPrint('반주 채널 정렬 실패: ${aligned.message}');
      }
    }

    await _commitTake(
      songId: song.id,
      songTitle: song.title,
      fileName: result.fileName,
      durationMs: result.duration.inMilliseconds,
      trackSlot: _recordingSlot,
      pitchSemitones: _recordingPitch,
      songPositionMs: _recordingAlignMs,
      sourceAudioPath: _recordingSourcePath,
      tempoScale: _recordingTempo,
      peakDbfs: result.peakDbfs,
      recordedBacking: dual ? recordedBacking : null,
      savedMessage: dual
          ? '2채널 녹음을 저장했습니다. 합친 곡을 만드는 중...'
          : '녹음을 저장했습니다. 녹음 탭에서 들어볼 수 있어요.',
    );
  }

  /// 받은 소리 하나를 테이크로 등록한다 — R 녹음·고정 조각·부팅 복구가 같은 길을 탄다.
  ///
  /// 등록 → 무음 경고 → 반주 붙이기(2채널이면 합치기, 1채널이면 원본 반주에서
  /// 같은 구간 자르기). [songPositionMs]는 파일 t=0의 곡 좌표다 — 1채널에서는
  /// 그대로 반주 정렬점(alignOffsetMs)이 된다.
  /// [leadInMs]는 고정 조각만 준다(파일 머리에 담긴 리드인).
  /// [savedMessage]가 null이면 저장 안내를 띄우지 않는다(부팅 복구는 한 번에 모아 알린다).
  /// [onIndexed]는 목록(recordings.json)이 **디스크에 닿았을 때만** 불린다 — 고정 조각과
  /// 부팅 복구가 그제야 세션 쪽 기록을 지운다(먼저 지우면 그사이 앱이 끝났을 때
  /// 조각이 목록에도 없고 복구도 안 된다).
  Future<RecordingTake> _commitTake({
    required String songId,
    required String songTitle,
    required String fileName,
    required int durationMs,
    required int? trackSlot,
    required int pitchSemitones,
    required int songPositionMs,
    required String? sourceAudioPath,
    required double tempoScale,
    required double? peakDbfs,
    String? recordedBacking,
    int? leadInMs,
    String comment = '',
    String? savedMessage,
    bool warnIfSilent = true,
    Future<void> Function()? onIndexed,
  }) async {
    // 2채널로 받았으면 반주 채널이 곧 테이크의 반주다 — 정렬 보정이 0이다.
    final dual = recordedBacking != null && recordedBacking.isNotEmpty;
    final take = RecordingTake(
      id: const Uuid().v4(),
      songId: songId,
      songTitle: songTitle,
      fileName: fileName,
      recordedAt: DateTime.now(),
      durationMs: durationMs,
      backingTrackSlot: trackSlot,
      pitchSemitones: pitchSemitones,
      alignOffsetMs: dual ? 0 : songPositionMs,
      comment: comment,
      sourceAudioPath: sourceAudioPath,
      tempoScale: tempoScale,
      accompanimentFileName: dual ? recordedBacking : null,
      dualChannel: dual,
      // 채널 수와 무관하게 「곡의 어디였는지」를 남긴다 — 조각 이어붙이기의 좌표.
      songPositionMs: songPositionMs,
      leadInMs: leadInMs,
      // 이어붙이기가 무음 조각을 가려내는 근거 — 파일을 다시 열지 않아도 된다.
      peakDbfs: peakDbfs,
    );
    final indexed = await _recordingLibrary.add(take);
    // 새 테이크가 목록의 맨 앞에 올라왔다 — Ctrl+R이 물릴 「직전 녹음」이 다시 맞다.
    _lastTakeGuard.noteCommitted();
    if (indexed) await onIndexed?.call();
    if (!mounted) return take;
    setState(() {});

    // 🔴 소리가 안 들어왔으면 그 자리에서 알린다. 2026-09-21에 같은 사고가
    // 두 번 났다 — 잘못된 장치(꺼진 무선 헤드셋·믹서 루프백)를 녹음해
    // 디지털 무음이 저장됐는데, 저장까지 정상으로 끝나서 들어 보기 전에는
    // 알 수가 없었다. 조각을 여러 개 쌓은 뒤에 알면 전부 다시 불러야 한다.
    if (warnIfSilent && isSilentTake(peakDbfs)) {
      SnackMessage.show(
        context,
        '녹음에 소리가 없습니다 — 입력 장치를 확인해 주세요. '
        '설정 > 녹음에서 마이크를 직접 고르고 [마이크 테스트]로 막대가 '
        '움직이는지 본 뒤 다시 받으세요.',
        duration: const Duration(seconds: 12),
      );
      return take;
    }

    if (savedMessage != null) _showSnack(savedMessage);
    if (dual) {
      // 미리 듣기는 합친 한 곡이 기본이라 저장 직후 바로 만들어 둔다.
      unawaited(_mixTake(take, silent: true));
    } else {
      // 변형본 캐시가 지워지기 전에 즉시 반주 조각을 잘라 자립시킨다.
      // 실패해도 테이크는 남는다(녹음 탭에서 재시도 가능).
      unawaited(_cutAccompanimentForTake(take, silent: true));
    }
    return take;
  }

  /// 녹음 고정 중의 R — 같은 세션에 마크만 찍는다.
  ///
  /// 🔴 재생은 절대 건드리지 않는다. 반주를 틀어 둔 채 중간부터 받거나 반주 없이
  /// 받을 때 쓰는 키라, 여기서 재생을 걸거나 멈추면 스페이스와 뜻이 겹친다.
  /// 이미 재생 중에 찍은 마크는 「재생 시작 지연」을 빼지 않는다(playbackAlreadyRunning).
  void _armedRecordKey() {
    if (_recording.isTakeOpen) {
      _endArmedTake();
      if (mounted) setState(() {});
      return;
    }
    final song = _selectedSong;
    if (song == null) {
      _showSnack('먼저 곡을 선택해 주세요.');
      return;
    }
    final open = _markArmedTakeStart(
      song,
      playbackAlreadyRunning: _playback.state.value.playing,
    );
    if (open == null) _showSnack(_kArmedNotReadyMessage);
    if (mounted) setState(() {});
  }

  /// 지난 실행이 남긴 고정 세션에서, 저장하지 못한 조각을 「복구됨」 테이크로 되살린다.
  ///
  /// 앱이 죽었거나(열린 조각), 저장 줄을 못 비우고 닫힌 경우다. 컨트롤러가 세션
  /// 사이드카의 마크대로 잘라 주고, 여기서는 목록에 올리기만 한다.
  Future<void> _recoverArmedSessions() async {
    try {
      final slices = await _recording.recoverStaleSessions(
        fileNameFor: (_, _) => '${const Uuid().v4()}.wav',
        // 🔴 조각마다 **목록에 올린 뒤에** 성공 여부를 돌려준다. 컨트롤러는 전부
        // 등록된 세션만 지운다 — 세션을 먼저 지우면, 그사이 앱이 끝났을 때 되살린
        // 조각이 목록에도 세션에도 없다.
        onSlice: (slice) async {
          // 컨텍스트를 못 읽은 조각도 버리지 않는다 — 곡을 모르는 채로 올린다.
          final context = ArmedTakeContext.fromJsonOrUnknown(slice.context);
          var indexed = false;
          await _commitTake(
            songId: context.songId,
            songTitle: context.songTitle,
            fileName: slice.fileName,
            durationMs: slice.durationMs,
            trackSlot: context.trackSlot,
            pitchSemitones: context.pitchSemitones,
            songPositionMs: slice.songPositionMs,
            sourceAudioPath: context.activeAudioPath,
            tempoScale: context.tempoScale,
            peakDbfs: slice.peakDbfs,
            leadInMs: slice.leadInMs,
            comment: '복구됨',
            // 조각마다 토스트를 띄우면 서로 지운다 — 끝에 한 번만 알린다.
            warnIfSilent: false,
            onIndexed: () async => indexed = true,
          );
          return indexed;
        },
      );
      if (slices.isEmpty) return;
      _showSnack(
        '지난번에 저장하지 못한 조각 ${slices.length}개를 되살렸습니다 — '
        '녹음 탭에서 「복구됨」 코멘트로 찾을 수 있어요.',
      );
    } catch (e) {
      // 복구 실패가 부팅을 막을 이유는 없다. 세션 파일은 남아 다음에 다시 시도된다.
      debugPrint('고정 세션 복구 실패: $e');
    }
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
    final outputPath = '${(await _recordingLibrary.directory()).path}/$accName';
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
          decoration: const InputDecoration(hintText: '이번 녹음에서 느낀 점을 적어 두세요'),
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

  /// 같은 곡의 조각들을 한 벌의 보컬로 잇고 반주에 얹는다.
  ///
  /// 랩처럼 빠른 구간은 두 줄씩 끊어 녹음하게 된다(펀치인). 조각마다 곡
  /// 재생 위치가 남아 있어 이어붙이기는 귀로 맞추는 일이 아니라 계산이다.
  Future<void> _stitchTakes(RecordingTake take) async {
    // 템포가 다른 조각은 시간축 자체가 다르다(같은 곡 시각이 다른 ms에 놓인다) —
    // 한 타임라인에 올릴 수 없으니 고른 테이크와 같은 템포만 모은다.
    final siblings = _recordingLibrary.takes
        .where(
          (t) =>
              t.songId == take.songId &&
              t.hasSongPosition &&
              isSameStitchTimeline(t.tempoScale, take.tempoScale),
        )
        .toList();
    if (siblings.length < 2) {
      _showSnack('이어붙이려면 같은 곡 조각이 둘 이상 필요합니다.');
      return;
    }

    final dir = (await _recordingLibrary.directory()).path;
    // 분리 보컬이 있으면 그걸 쓴다(스피커 녹음 정리본).
    final segments = [
      for (final t in siblings)
        StitchSegment(
          vocalPath:
              '$dir/${t.hasSeparatedVocal ? t.separatedFileName : t.fileName}',
          songPositionMs: t.songPositionMs!,
          durationMs: t.durationMs,
          // 고정 조각 머리의 리드인(키를 누르기 전 소리). 300 고정이 아니다 —
          // 곡 앞머리에서 찍은 조각은 더 짧다.
          leadInMs: t.leadInMs ?? 0,
          peakDbfs: t.peakDbfs,
        ),
    ];

    if (!mounted) return;
    _showSnack('조각 ${segments.length}개를 잇는 중...');
    final stitcher = TakeStitchService();
    // 리드인 무음을 재서 내용이 실제로 시작하는 자리를 찾는다. 소리가 없는 조각은
    // 여기서 빠진다 — 끼워 두면 앞 조각의 꼬리만 잘라 놓고 자기는 무음이다.
    final measured = await stitcher.withDetectedOffsets(segments);
    final silentCount = segments.length - measured.length;
    final silentNote = silentCount > 0 ? ' (무음 조각 $silentCount개 제외)' : '';
    if (measured.length < 2) {
      if (mounted) _showSnack('소리가 있는 조각이 둘 이상 필요합니다$silentNote.');
      return;
    }

    // 이음새를 박 위에 두려고 싱크 가사 줄 경계를 쓴다(있을 때만).
    // 🔴 조각 좌표(songPositionMs)와 **같은 축**이어야 한다. 그 좌표는 플레이어
    // 축이라, 줄 시각도 이 테이크를 받은 슬롯의 가사 오프셋·트림과 녹음 당시
    // 템포로 옮긴다. LRC 원본 축 그대로 넘기면 가사 오프셋(이 곡은 1800ms)만큼
    // 어긋나 ±200ms 스냅이 엉뚱한 줄을 잡는다.
    var lineStarts = const <int>[];
    final matches = _songs.where((x) => x.id == take.songId).toList();
    if (matches.isNotEmpty) {
      final song = matches.first;
      final timed = await _app.lyricsSync.loadFor(song);
      if (timed != null && timed.lines.isNotEmpty) {
        final slot = take.backingTrackSlot;
        final track = slot == null ? null : song.trackForSlot(slot);
        lineStarts = stitchLineStartsMs(
          lyrics: timed,
          trackStartMs: track?.startMs,
          lyricsOffsetMs: track?.lyricsOffsetMs ?? 0,
          tempoScale: take.tempoScale,
        );
      }
    }

    final spans = computeStitchSpans(
      segments: measured,
      lineStartsMs: lineStarts,
    );
    if (spans.length < 2) {
      if (mounted) _showSnack('조각들이 서로 겹쳐서 이을 구간이 없습니다.');
      return;
    }

    final newId = const Uuid().v4();
    final vocalName = '$newId.wav';
    final result = await stitcher.stitchVocals(
      segments: measured,
      outputPath: '$dir/$vocalName',
      lineStartsMs: lineStarts,
    );
    if (!mounted) return;
    if (!result.success) {
      _showSnack(result.message ?? '조각 이어붙이기에 실패했습니다.');
      return;
    }

    // 이어붙인 보컬은 이미 곡 타임라인 위에 놓였다 — 정렬 보정이 0이고,
    // 반주 조각이 아니라 **원본 반주 한 벌**에 얹어야 한다.
    final stitched = RecordingTake(
      id: newId,
      songId: take.songId,
      songTitle: take.songTitle,
      fileName: vocalName,
      recordedAt: DateTime.now(),
      durationMs: spans.last.endMs,
      backingTrackSlot: take.backingTrackSlot,
      pitchSemitones: take.pitchSemitones,
      alignOffsetMs: 0,
      sourceAudioPath: take.sourceAudioPath,
      tempoScale: take.tempoScale,
      songPositionMs: 0,
      comment: '조각 ${spans.length}개 이어붙임',
    );
    await _recordingLibrary.add(stitched);
    // 목록의 맨 앞이 이 이어붙인 곡이 됐다 — Ctrl+R 가드는 더 막을 것이 없다.
    _lastTakeGuard.noteCommitted();
    if (!mounted) return;
    setState(() {});
    _showSnack('조각 ${spans.length}개를 이었습니다$silentNote. 반주와 합치는 중...');
    await _mixTake(stitched, silent: true);
  }

  /// Ctrl+R — 직전 녹음을 물린다. 조각을 여러 번 다시 받을 때,
  /// 맘에 안 든 것을 그 자리에서 버려 **최종본만 순서대로 쌓이게** 한다.
  ///
  /// 파일은 바로 지우지 않는다 — 잘못 눌렀을 때 되돌릴 수 없으면 안 된다.
  Future<void> _discardLastRecording() async {
    // 방금 스페이스로 멈춘 조각은 아직 저장 줄에 있을 수 있다 — 그게 「직전 녹음」이다.
    // 안 기다리면 그 앞의 조각을 물려 버린다.
    await _armedSaveChain;
    if (!mounted) return;
    if (_recording.isTakeOpen) {
      _showSnack('스페이스로 멈춘 뒤에 취소해 주세요');
      return;
    }
    if (_recording.isRecording) {
      _showSnack('녹음 중입니다. R로 정지한 뒤에 취소해 주세요.');
      return;
    }
    // 🔴 직전 시도가 목록에 안 올라갔으면(0.5초 미만이라 버림·저장 실패) 물릴 것이
    // 없다. 그대로 가면 목록의 맨 앞 = **그 앞의 멀쩡한 조각**이 물리고 6초 뒤
    // 파일까지 지워진다. 가드는 저장 줄 안에서 서므로 위의 await 뒤에 읽으면 맞다.
    // 한 번만 막는다 — 정말 앞 조각을 물리려면 한 번 더 누르면 된다.
    final blocked = _lastTakeGuard.consumeBlock();
    if (blocked != null) {
      _showSnack(blocked);
      return;
    }
    final takes = _recordingLibrary.takes; // 최신순
    if (takes.isEmpty) {
      _showSnack('취소할 녹음이 없습니다.');
      return;
    }
    // 앞서 물려 둔 게 있으면 이제 확정 — 파일을 치운다.
    await _purgeDiscarded();

    final take = takes.first;
    await _recordingLibrary.removeRecordOnly(take);
    _discardedTake = take;
    if (!mounted) return;
    setState(() {});

    // 저장 토스트·녹음 목록과 같은 숫자(스페이스를 누른 자리)로 말한다 — 리드인을
    // 뺀 파일 좌표를 그대로 쓰면 1초 어긋나, 다른 조각을 지운 것으로 읽힌다.
    final at = take.displayPositionMs;
    final where = at == null ? '' : ' (${formatSongPosition(at)} 조각)';
    // 토스트가 사라지면 확정 — 그때까지는 되살릴 수 있다.
    _discardPurgeTimer?.cancel();
    _discardPurgeTimer = Timer(
      const Duration(milliseconds: 6000),
      () => unawaited(_purgeDiscarded()),
    );
    SnackMessage.show(
      context,
      '직전 녹음을 취소했습니다$where.',
      actionLabel: '실행취소',
      onAction: _restoreDiscarded,
    );
  }

  /// 물려 둔 테이크를 목록에 되돌린다.
  Future<void> _restoreDiscarded() async {
    final take = _discardedTake;
    if (take == null) return;
    _discardPurgeTimer?.cancel();
    _discardPurgeTimer = null;
    _discardedTake = null;
    await _recordingLibrary.add(take);
    if (!mounted) return;
    setState(() {});
    _showSnack('녹음을 되살렸습니다.');
  }

  /// 물려 둔 테이크의 파일을 실제로 치운다(되살릴 기회가 지났다).
  Future<void> _purgeDiscarded() async {
    final take = _discardedTake;
    _discardPurgeTimer?.cancel();
    _discardPurgeTimer = null;
    _discardedTake = null;
    if (take == null) return;
    await _recordingLibrary.purgeFiles(take);
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
      deepSeekAvailable:
          _app.deepSeekLyrics.available && _settings.cloudAiActive,
      deepSeekOffReason: _settings.cloudAiActive
          ? null
          : '설정 > AI·작곡에서 클라우드AI를 켜면 사용할 수 있습니다.',
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
    if (!await _confirmSameVideoAgain(url)) return;
    if (!mounted) return;
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

  /// 같은 영상이 이미 등록돼 있거나 가져오는 중이면 확인을 받는다.
  /// true = 계속 진행. 실수로 직전 곡을 또 추가하던 사고 방지(v5.5.0).
  Future<bool> _confirmSameVideoAgain(String url) async {
    final id = youtubeVideoId(url);
    if (id == null) return true;

    // 아직 안 끝난 잡에 같은 영상이 있으면 중복 시작을 막는다(확인 불필요).
    final importing = _importJobs.jobs.any(
      (j) => !j.status.isFinished && youtubeVideoId(j.url) == id,
    );
    if (importing) {
      _showSnack('이 영상은 이미 가져오는 중이에요. 진행 상황은 홈 위쪽에 있어요.');
      return false;
    }

    Song? existing;
    for (final song in _songs) {
      final source = song.sourceUrl;
      if (source != null && youtubeVideoId(source) == id) {
        existing = song;
        break;
      }
    }
    if (existing == null) return true;
    if (!mounted) return false;

    final again = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이미 추가한 곡이에요'),
        content: Text(
          "이 영상은 '${existing!.title}'(으)로 이미 등록돼 있어요.\n"
          '같은 영상을 한 번 더 가져올까요?',
          style: AppTypography.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              minimumSize: const Size(84, AppConstants.minTouchTarget),
            ),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              minimumSize: const Size(140, AppConstants.minTouchTarget),
            ),
            child: const Text('다시 가져오기'),
          ),
        ],
      ),
    );
    return again == true;
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
      YoutubeChartKind.domestic => await _ytClient.mostPopularTop100(
        koreanOnly: true,
      ),
      YoutubeChartKind.global => await _ytClient.mostPopularTop100(
        regionCode: 'US',
      ),
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
            Text('개인이 저작권을 소유한 링크만 사용해야 합니다.', style: AppTypography.body),
            const SizedBox(height: 8),
            Text(
              '개인적 용도의 사용에 대한 책임은 사용자 본인에게 있습니다.',
              style: AppTypography.body,
            ),
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
      localAiEnabled: _settings.localAiActive,
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
      localAiEnabled: _settings.localAiActive,
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

  Future<void> _toggleFavorite(Song song) async {
    await _app.toggleFavorite(song);
    // 폰은 PC를 정본으로 삼아 덮어쓴다 — 여기서 누른 별을 따로 적어 두지
    // 않으면 다음 동기화에 그냥 사라진다. 올리고 나면 비운다.
    if (!PlatformCapabilities.isMobile) return;
    final next = _app.songById(song.id);
    if (next == null) return;
    await _updateSettings(
      _settings.copyWith(
        pendingFavorites: {
          ..._settings.pendingFavorites,
          song.id: next.isFavorite,
        },
      ),
    );
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
    // AI 진입점의 숨김·라벨 정책은 전부 AiGate 한 곳에서 결정한다.
    final gate = AiGate(_settings);
    return PrompterKeyboardScope(
      // 재생·녹음·싱크 단축키는 재생 화면이 보이는 탭(홈·즐겨찾기)에서만.
      // 곡 검색·설정 등 다른 탭에서 R·T·Space가 먹으면 사고다.
      // 전체화면 무대는 같은 actions를 자기 스코프에서 소비한다.
      // 트레이닝 탭은 따라하기 세션 중에만 켜지고, overrideHandler가
      // Space·Home만 세션 제어로 받고 나머지 기본 매핑은 차단한다.
      enabled:
          _destination == AppDestination.home ||
          _destination == AppDestination.favorites ||
          (_destination == AppDestination.training && _trainingSession.active),
      overrideHandler: _handleTrainingKey,
      onToggleSpaceBackground: () {
        final next = nextSpaceBackgroundLevel(_settings.spaceBackgroundLevel);
        _updateSettings(_settings.copyWith(spaceBackgroundLevel: next));
        _showSnack('우주 배경: ${spaceBackgroundLevelLabel(next)}');
      },
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
        onStartSeparator: gate.local ? _app.ensureSeparatorOnline : null,
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
        ytDlpEjsVersion: _app.ytDlpEjsVersion,
        onUpdateYtDlp: _updateYtDlp,
        separatorStatusLabel: _separatorStatusLabel,
        onImportLrcFile: _importLrcFile,
        onMixTake: _mixTake,
        onAnalyzeTake: gate.local ? _analyzeTake : null,
        onCorrectTake: gate.local ? _correctTake : null,
        onPlayTakeMix: _playTakeMix,
        takePosition: _takePosition,
        takeDuration: _takeDuration,
        onSeekTake: _takePlayer.seek,
        onFetchSyncedLyrics: _fetchSyncedLyrics,
        onAdjustLyricsOffset: _adjustLyricsOffset,
        onAutoAlignLyrics: _autoAlignLyrics,
        onAnchorFirstLine: _anchorFirstLine,
        onSttLyrics: gate.local ? _regenerateLyrics : null,
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
        // 고정 조각도 「녹음 중」이다 — 컨트롤러의 isRecording은 R 녹음만 가리킨다.
        isRecording: _isCapturing,
        recordArmed: _recordArmed,
        onToggleRecordArm: _toggleRecordArm,
        armedStatusLabel: _armedStatusLabel,
        recordingLevelLabel: _recording.levelLabel,
        recordingElapsed: _recording.isTakeOpen
            ? _recording.sessionTakeElapsed
            : _recording.elapsed,
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
        onStitchTakes: _stitchTakes,
        recordingDevices: _recording.devices,
        onRefreshRecordingDevices: _refreshRecordingDevices,
        micTesting: _recording.isProbing,
        micLevel: _recording.level,
        micLevelLabel: _recording.levelLabel,
        backingTesting: _recording.isProbingBacking,
        backingLevel: _recording.backingLevel,
        backingLevelLabel: _recording.backingLevelLabel,
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
        disabledDestinations: gate.composeTab == AiVisibility.shown
            ? const <AppDestination>{}
            : const {AppDestination.compose},
        onDisabledDestinationTap: (_) => _showSnack(AiGate.offReason),
        onCheckOllamaModels: _app.ollama.listModels,
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
        // 곡 추가는 유튜브 링크 → yt-dlp 다운로드가 전부다. 모바일에는
        // 그 경로가 없으므로 버튼 자체를 감춘다(백업 반입으로 대체).
        onAddSong: PlatformCapabilities.hasExternalTools ? _addSong : null,
        // 임의 폴더로 파일을 쓰는 기능 — 모바일은 Scoped Storage라 불가.
        onExportTrack: PlatformCapabilities.hasFreeFileExport
            ? _exportCurrentTrack
            : null,
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
        onPullFromPc: PlatformCapabilities.isMobile ? _pullFromPc : null,
        onMessage: _showSnack,
        onClearQueue: _clearQueue,
        onReorderQueue: _reorderQueue,
        onRemoveQueueItem: _removeQueueItem,
      ),
    );
  }
}

/// 열려 있는 고정 조각 — 시작 마크와 그 순간 굳힌 컨텍스트의 짝.
///
/// 불변이다. 저장은 직렬 줄에서 한참 뒤에 도는데, 그때 화면 상태(선택 곡·슬롯·키)를
/// 다시 읽으면 그사이 바뀐 값이 조각에 붙는다.
@immutable
class _ArmedOpenTake {
  const _ArmedOpenTake(this.mark, this.context);

  /// 세션이 넘겨준 마크만으로 되살린다(끊김 복구). 마크에 실린 컨텍스트를 못 읽어도
  /// 소리는 버리지 않는다 — 곡을 모르는 조각으로 올린다.
  factory _ArmedOpenTake.fromMark(TakeStartMark mark) =>
      _ArmedOpenTake(mark, ArmedTakeContext.fromJsonOrUnknown(mark.context));

  final TakeStartMark mark;
  final ArmedTakeContext context;
}
