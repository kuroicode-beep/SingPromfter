// file: lib/controllers/app_controller.dart
//
// 앱의 헤드리스 중심부. 곡 목록·큐·설정 상태와 서비스, 가져오기 파이프라인,
// 재생 컨트롤러를 소유한다. BuildContext가 없어 화면(UI)과 로컬 제어
// API(MCP) 양쪽에서 같은 동작을 부를 수 있다.
//
// 화면은 이 컨트롤러를 구독(addListener)하고, 대화상자·스낵바·파일 선택 등
// UI 전용 흐름만 자기 몫으로 남긴다.
//
// 스레딩 주석: dart:io HttpServer 콜백은 메인 isolate 이벤트 루프에서
// 실행되므로, 제어 서버가 이 컨트롤러의 메서드를 직접 불러도 락이 필요 없다.
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import '../models/import_plan.dart';
import '../models/mr_source_mode.dart';
import '../models/prompter_display_mode.dart';
import '../models/prompter_settings.dart';
import '../models/queue_item.dart';
import '../models/song.dart';
import '../models/song_draft.dart';
import '../models/track_levels.dart';
import '../models/track_variant.dart';
import '../repository/song_repository.dart';
import '../services/key_detection_service.dart';
import '../services/level_analysis_service.dart';
import '../services/lyrics_align_service.dart';
import '../services/lyrics_sync_service.dart';
import '../services/pitch_variant_service.dart';
import '../services/track_asset_service.dart';
import '../services/process/external_tool_locator.dart';
import '../services/process/process_runner.dart';
import '../services/process/tool_progress_parsers.dart';
import '../services/prompter_audio_service.dart';
import '../services/song_library_service.dart';
import '../services/song_list_bootstrap_service.dart';
import '../services/song_queue_service.dart';
import '../models/vocal_segments.dart';
import '../services/vocal_segments_service.dart';
import '../services/vocal_separation_client.dart';
import '../services/youtube_import_service.dart';
import '../utils/key_label.dart';
import '../utils/lrc_retime.dart';
import '../utils/tempo_label.dart';
import '../utils/music_key.dart';
import '../utils/pitch_math.dart';
import '../utils/youtube_title_cleaner.dart';
import 'import_job_controller.dart';
import 'playback_controller.dart';

/// 가져오기 요청 결과. 실패 시 [errorCode]로 사유를 기계가 읽을 수 있게 준다.
class ImportEnqueueOutcome {
  final String? jobId;

  /// null=성공, 'not_youtube_url', 'notice_not_acked'
  final String? errorCode;
  final String? message;

  const ImportEnqueueOutcome.ok(String this.jobId)
    : errorCode = null,
      message = null;

  const ImportEnqueueOutcome.error(this.errorCode, this.message)
    : jobId = null;

  bool get ok => jobId != null;
}

class AppController extends ChangeNotifier {
  static const _kYtNoticeAckKey = 'yt_notice_ack';

  // ── 서비스 (전부 헤드리스) ──────────────────────────────
  final SongRepository repo = SongRepository.instance;
  late final SongQueueService queueService = SongQueueService(repo);
  late final SongListBootstrapService bootstrapService =
      SongListBootstrapService(repo);
  late final SongLibraryService libraryService = SongLibraryService(repo);
  final LyricsSyncService lyricsSync = LyricsSyncService();
  final ExternalToolLocator toolLocator = ExternalToolLocator();
  late final PitchVariantService pitchVariants = PitchVariantService(
    locator: toolLocator,
  );
  late final LevelAnalysisService levelAnalysis = LevelAnalysisService(
    locator: toolLocator,
  );
  late final KeyDetectionService keyDetection = KeyDetectionService(
    locator: toolLocator,
  );
  late final LyricsAlignService lyricsAlign = LyricsAlignService(
    locator: toolLocator,
  );
  late final VocalSegmentsService vocalSegments = VocalSegmentsService(
    align: lyricsAlign,
  );
  late final TrackAssetService trackAssets = TrackAssetService(
    pitch: pitchVariants,
    levels: levelAnalysis,
    keys: keyDetection,
    vocalSegments: vocalSegments,
  );
  late final YoutubeImportService youtubeImport = YoutubeImportService(
    tmpDirProvider: repo.getTmpDir,
    locator: toolLocator,
  );
  final VocalSeparationClient separation = VocalSeparationClient();
  late final PrompterAudioService audio = PrompterAudioService(repo);
  final ScrollController lyricsScrollController = ScrollController();
  late final ImportJobController importJobs;
  late final PlaybackController playback;

  // ── UI 연결점 (화면이 설정; 없어도 동작한다) ─────────────
  void Function(String message)? onMessage;
  void Function(PlaybackSnapshot snapshot, Duration played)?
  onPracticeSessionEnded;

  // ── 상태 ────────────────────────────────────────────────
  List<Song> songs = [];
  List<QueueItem> queue = [];
  PrompterSettings settings = const PrompterSettings();
  bool loading = true;

  bool ytDlpAvailable = false;
  String? ytDlpMissingReason;
  String? ytDlpVersion;
  String separatorStatusLabel = '분리 서버: 확인 중';
  bool separatorOnline = false;

  Timer? _statusRefreshTimer;
  bool _disposed = false;

  AppController() {
    playback = PlaybackController(
      audio: audio,
      queueService: queueService,
      repo: repo,
      lyricsScrollController: lyricsScrollController,
      songsProvider: () => songs,
      queueProvider: () => queue,
      settingsProvider: () => settings,
      onQueueChanged: (next) {
        queue = next;
        _notify();
      },
      onMessage: _emit,
      timedLyricsLoader: lyricsSync.loadFor,
      trackVariantResolver: _resolveTrackVariant,
      levelsLoader: loadTrackLevels,
      vocalSegmentsLoader: loadVocalSegments,
      onSongReady: (song, duration) =>
          unawaited(ensureSongKey(song, duration: duration)),
      onPracticeSessionEnded: (snapshot, played) =>
          onPracticeSessionEnded?.call(snapshot, played),
    )..init();
    importJobs = ImportJobController(runner: _runImportJob);
  }

  @override
  void dispose() {
    _disposed = true;
    _statusRefreshTimer?.cancel();
    _pitchApplyTimer?.cancel();
    _tempoApplyTimer?.cancel();
    pendingPitch.dispose();
    pendingTempo.dispose();
    importJobs.dispose();
    playback.dispose();
    audio.dispose();
    lyricsScrollController.dispose();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _emit(String message) => onMessage?.call(message);

  Song? get selectedSong => playback.snapshot.song;
  int? get selectedTrackSlot => playback.snapshot.trackSlot;

  Song? songById(String id) {
    for (final song in songs) {
      if (song.id == id) return song;
    }
    return null;
  }

  // ── 부팅 ────────────────────────────────────────────────

  Future<void> bootstrap() async {
    final initial = await bootstrapService.load();
    if (_disposed) return;
    songs = initial.songs;
    queue = initial.queue;
    settings = initial.settings;
    loading = false;
    _notify();

    unawaited(refreshToolAvailability());
    _startStatusRefresh();

    final schemaError = repo.schemaLoadError;
    if (schemaError != null) _emit(schemaError);

    await audio.setVolume(settings.volume);
    final initialSong = initial.initialSong;
    if (initialSong != null) {
      await playback.loadSong(
        initialSong,
        preferredSlot:
            settings.trackSlotForSong(initialSong.id) ??
            settings.lastSelectedTrackSlot,
      );
    }
  }

  // ── 설정 (단일 쓰기 경로) ───────────────────────────────

  Future<void> updateSettings(PrompterSettings next) async {
    settings = next;
    _notify();
    await repo.saveSettings(next);
    await playback.applySettings(next);
  }

  Future<void> selectTrackSlot(int slot) async {
    final song = selectedSong;
    if (song == null) return;
    if (!song.availableTrackSlots.contains(slot)) return;
    await updateSettings(settings.withSongTrackSlot(song.id, slot));
    await playback.selectTrackSlot(slot);
  }

  // ── 키(피치) ────────────────────────────────────────────

  /// 키를 바꾼 반주를 준비한다. 처음 쓰는 키는 여기서 렌더링된다.
  /// 키·템포를 구운 반주 경로. 캐시가 있으면 즉시, 없으면 렌더 후 반환.
  Future<String?> _resolveTrackVariant(
    Song song,
    int slot,
    int semitones,
    double tempoScale,
  ) async {
    final track = song.trackForSlot(slot);
    if (track == null) return null;
    final sourcePath = await repo.getBackingTrackPath(track.fileName);
    if (sourcePath == null) return null;

    final cached = await pitchVariants.cachedPath(
      sourceFileName: track.fileName,
      semitones: semitones,
      tempoScale: tempoScale,
    );
    if (cached != null) return cached;

    _emit('${_variantLabel(semitones, tempoScale)} 반주를 준비하는 중...');
    final result = await pitchVariants.render(
      sourcePath: sourcePath,
      sourceFileName: track.fileName,
      semitones: semitones,
      tempoScale: tempoScale,
      total: playback.snapshot.duration,
    );
    if (!result.success) {
      _emit(result.message ?? '키·템포 변경에 실패했습니다.');
      return null;
    }
    return result.path;
  }

  /// 준비 안내에 쓸 짧은 이름. 둘 다 바뀌었으면 함께 적는다.
  String _variantLabel(int semitones, double tempoScale) {
    final parts = <String>[
      if (semitones != 0) formatKeyLabel(semitones),
      if (!isDefaultTempo(tempoScale)) formatTempoLabel(tempoScale),
    ];
    return parts.isEmpty ? '원본' : parts.join(' · ');
  }

  // ── 템포 ────────────────────────────────────────────────

  /// 휠로 굴리는 동안 화면에 보여 줄 임시 템포. 키와 같은 구조다.
  final ValueNotifier<double?> pendingTempo = ValueNotifier(null);
  Timer? _tempoApplyTimer;

  /// 지금 화면에 보여 줄 템포 — 적용 대기 중이면 그 값이 우선.
  double effectiveTempoFor(Song song, int? slot) {
    final pending = pendingTempo.value;
    if (pending != null && selectedSong?.id == song.id) return pending;
    return settings.tempoForSong(song.id, slot);
  }

  /// 현재 선택 곡·슬롯의 템포를 [delta]만큼 밀되, 적용은 미룬다.
  ///
  /// 키와 같은 이유로 디바운스한다 — 한 칸마다 렌더하면 곡 전체를 몇 번이고
  /// 다시 인코딩하게 된다. 화면에는 즉시 반영되고 오디오는 손을 멈춘 뒤 바뀐다.
  void nudgeTempoDebounced(double delta) {
    final song = selectedSong;
    final slot = selectedTrackSlot;
    if (song == null || slot == null) {
      _emit('먼저 곡과 반주를 선택해 주세요.');
      return;
    }
    final base = pendingTempo.value ?? settings.tempoForSong(song.id, slot);
    final next = quantizeTempo(base + delta);
    pendingTempo.value = next;

    _tempoApplyTimer?.cancel();
    _tempoApplyTimer = Timer(_pitchApplyDelay, () async {
      final target = pendingTempo.value;
      if (target == null) return;
      await setTempo(song.id, target, slot: slot, keepPosition: true);
      if (!_disposed) pendingTempo.value = null;
    });
  }

  /// 절대값으로 템포를 지정한다 (0.5~1.5 클램프). MCP 제어의 기본형.
  Future<bool> setTempo(
    String songId,
    double scale, {
    int? slot,
    bool keepPosition = false,
  }) async {
    final song = songById(songId);
    if (song == null) return false;
    final resolvedSlot =
        slot ??
        (selectedSong?.id == songId ? selectedTrackSlot : null) ??
        settings.trackSlotForSong(songId) ??
        (song.availableTrackSlots.isNotEmpty
            ? song.availableTrackSlots.first
            : null);
    if (resolvedSlot == null) return false;

    final next = quantizeTempo(scale);
    final current = settings.tempoForSong(songId, resolvedSlot);
    if ((next - current).abs() < tempoStep / 2) return true;

    await updateSettings(settings.withSongTempo(songId, resolvedSlot, next));
    if (selectedSong?.id == songId && selectedTrackSlot == resolvedSlot) {
      await playback.prepareAudioForSelection(keepPosition: keepPosition);
    }
    _emit('템포: ${formatTempoLabel(next)}');
    return true;
  }

  Future<void> adjustPitch(int delta) async {
    final song = selectedSong;
    final slot = selectedTrackSlot;
    if (song == null || slot == null) {
      _emit('먼저 곡과 반주를 선택해 주세요.');
      return;
    }
    final current = settings.pitchForSong(song.id, slot);
    await setPitch(song.id, current + delta, slot: slot);
  }

  /// 절대값으로 키를 지정한다 (±6 반음 클램프). MCP 제어의 기본형.
  Future<bool> setPitch(
    String songId,
    int semitones, {
    int? slot,
    bool keepPosition = false,
  }) async {
    final song = songById(songId);
    if (song == null) return false;
    final resolvedSlot =
        slot ??
        (selectedSong?.id == songId ? selectedTrackSlot : null) ??
        settings.trackSlotForSong(songId) ??
        (song.availableTrackSlots.isNotEmpty
            ? song.availableTrackSlots.first
            : null);
    if (resolvedSlot == null) return false;

    final next = clampSemitones(semitones);
    final current = settings.pitchForSong(songId, resolvedSlot);
    if (next == current) return true;

    await updateSettings(settings.withSongPitch(songId, resolvedSlot, next));
    // 지금 재생 중인 곡·슬롯이면 새 키로 다시 준비한다(필요 시 렌더링).
    if (selectedSong?.id == songId && selectedTrackSlot == resolvedSlot) {
      await playback.prepareAudioForSelection(keepPosition: keepPosition);
    }
    _emit('키: ${formatKeyLabel(next)}');
    return true;
  }

  /// 휠로 굴리는 동안 화면에 보여 줄 임시 키 값.
  /// 실제 렌더는 손을 멈춘 뒤에 한 번만 한다(한 단계마다 렌더하면
  /// 곡 전체를 몇 번이고 다시 인코딩하게 된다).
  final ValueNotifier<int?> pendingPitch = ValueNotifier(null);
  Timer? _pitchApplyTimer;
  static const _pitchApplyDelay = Duration(milliseconds: 550);

  /// 현재 선택 곡·슬롯의 키를 [delta]만큼 밀되, 적용은 미룬다.
  /// 화면에는 즉시 반영되고 오디오는 손을 멈춘 뒤 바뀐다.
  void nudgePitchDebounced(int delta) {
    final song = selectedSong;
    final slot = selectedTrackSlot;
    if (song == null || slot == null) {
      _emit('먼저 곡과 반주를 선택해 주세요.');
      return;
    }
    final base = pendingPitch.value ?? settings.pitchForSong(song.id, slot);
    final next = clampSemitones(base + delta);
    pendingPitch.value = next;

    _pitchApplyTimer?.cancel();
    _pitchApplyTimer = Timer(_pitchApplyDelay, () async {
      final target = pendingPitch.value;
      if (target == null) return;
      await setPitch(song.id, target, slot: slot, keepPosition: true);
      if (!_disposed) pendingPitch.value = null;
    });
  }

  /// 지금 화면에 보여 줄 키 — 적용 대기 중이면 그 값이 우선.
  int effectivePitchFor(Song song, int? slot) {
    final pending = pendingPitch.value;
    if (pending != null && selectedSong?.id == song.id) return pending;
    return settings.pitchForSong(song.id, slot);
  }

  // ── 싱크 가사 ───────────────────────────────────────────

  /// LRCLIB에서 싱크 가사를 찾아 붙인다. [songId] 생략 시 현재 곡.
  Future<LyricsFetchOutcome> fetchSyncedLyricsFor({String? songId}) async {
    final song = songId == null ? selectedSong : songById(songId);
    if (song == null) {
      return const LyricsFetchOutcome(
        success: false,
        message: '곡을 찾을 수 없습니다. 먼저 곡을 선택해 주세요.',
      );
    }
    final isCurrent = selectedSong?.id == song.id;
    final outcome = await lyricsSync.fetchFor(
      song,
      duration: isCurrent ? playback.snapshot.duration : null,
    );
    if (_disposed) return outcome;

    if (outcome.success && outcome.song != null) {
      final updated = outcome.song!;
      await replaceSongInList(updated);
      if (isCurrent) {
        // 새로 받은 가사를 즉시 반영하고 싱크 모드로 전환한다.
        playback.timedLyrics.value = await lyricsSync.loadFor(updated);
        await updateSettings(
          settings.copyWith(displayMode: PrompterDisplayMode.timed),
        );
        // 결정 사항: 싱크 가사는 기본으로 1초 먼저 띄워 읽을 시간을 준다.
        // 사용자가 이미 조절해 둔 값(0이 아님)은 건드리지 않는다.
        final slot = selectedTrackSlot;
        final track = slot == null ? null : updated.trackForSlot(slot);
        if (track != null && track.lyricsOffsetMs == 0) {
          await adjustLyricsOffset(-1000);
        }
      }
    }
    return outcome;
  }

  /// 원곡과 MR을 비교해 가사 오프셋을 자동으로 맞춘다.
  ///
  /// 보컬 = 원곡 − MR 이라는 점을 이용해 실제 발성 시작을 찾아 LRC 줄 시각과
  /// 비교한다. 원곡·MR 두 슬롯이 모두 있고 싱크 가사가 있어야 한다.
  ///
  /// 여러 줄에서 못 찾거나 편차가 크면 값을 밀어 넣지 않고 그대로 둔다 —
  /// 잘못 맞춘 싱크는 안 맞춘 것보다 나쁘다.
  Future<bool> autoAlignLyrics({String? songId}) async {
    final song = songId == null ? selectedSong : songById(songId);
    if (song == null) {
      _emit('먼저 곡을 선택해 주세요.');
      return false;
    }
    final lyrics = await lyricsSync.loadFor(song);
    if (lyrics == null || lyrics.isEmpty) {
      _emit('싱크 가사가 있어야 자동으로 맞출 수 있습니다.');
      return false;
    }

    final originalSlot = TrackVariant.original.preferredSlot;
    final mrSlot = TrackVariant.mr.preferredSlot;
    final original = song.trackForSlot(originalSlot);
    final mr = song.trackForSlot(mrSlot);
    if (original == null || mr == null) {
      _emit('원곡과 MR이 모두 있어야 합니다. 둘을 비교해 목소리를 찾습니다.');
      return false;
    }
    final originalPath = await repo.getBackingTrackPath(original.fileName);
    final mrPath = await repo.getBackingTrackPath(mr.fileName);
    if (originalPath == null || mrPath == null) return false;

    _emit('노래와 가사를 맞추는 중...');
    final outcome = await lyricsAlign.measure(
      originalPath: originalPath,
      mrPath: mrPath,
      lyrics: lyrics,
    );
    if (_disposed) return false;
    final result = outcome.result;
    if (result == null) {
      // 드리프트 곡은 오프셋으로 못 맞추지만 재타이밍으로는 맞출 수 있다.
      final retimeNote = await _maybeRetimeDrift(song, outcome);
      if (retimeNote != null) {
        _emit(retimeNote);
        return true;
      }
      _emit(_alignFailureMessage(outcome));
      return false;
    }

    final next = await _applyAlignedOffset(song.id, result.offsetMs);

    final seconds = (next.abs() / 1000).toStringAsFixed(1);
    final direction = next < 0 ? '먼저' : '늦게';
    _emit('가사를 $seconds초 $direction 띄우도록 맞췄습니다 (${result.samples}곳 비교).');
    return true;
  }

  /// 측정된 오프셋을 곡의 모든 반주에 적용하고, 실제 적용값(클램프 후)을 돌려준다.
  Future<int> _applyAlignedOffset(String songId, int offsetMs) async {
    final next = offsetMs.clamp(
      -AppConstants.maxLyricsOffsetMs,
      AppConstants.maxLyricsOffsetMs,
    );
    final fresh = songById(songId);
    if (fresh == null) return next;
    final updatedTracks = fresh.backingTracks
        .map((t) => t.copyWith(lyricsOffsetMs: next))
        .toList(growable: false);
    await replaceSongInList(
      fresh.copyWith(backingTracks: updatedTracks, updatedAt: DateTime.now()),
    );
    if (selectedSong?.id == songId) playback.applyLyricsOffset(next);
    return next;
  }

  /// 가져오기의 마지막 단계 — 방금 붙인 가사의 싱크를 바로 맞춘다.
  ///
  /// "링크 하나 = 부를 수 있는 곡" 계약의 일부다. 가사를 붙여 놓고 싱크는
  /// 사용자가 따로 버튼을 눌러야 한다면 절반짜리 자동화다.
  /// 실패해도 곡 등록은 그대로 두고, 결과는 완료 메시지 꼬리표로만 알린다.
  Future<String> _autoAlignNoteFor(Song song) async {
    try {
      // 측정은 원곡−MR 포락선 비교라 둘 다 있어야 한다. 없으면 조용히 넘어간다.
      final original = song.trackForSlot(TrackVariant.original.preferredSlot);
      final mr = song.trackForSlot(TrackVariant.mr.preferredSlot);
      if (original == null || mr == null) return '';
      final lyrics = await lyricsSync.loadFor(song);
      if (lyrics == null || lyrics.isEmpty) return '';
      final originalPath = await repo.getBackingTrackPath(original.fileName);
      final mrPath = await repo.getBackingTrackPath(mr.fileName);
      if (originalPath == null || mrPath == null) return '';

      final outcome = await lyricsAlign.measure(
        originalPath: originalPath,
        mrPath: mrPath,
        lyrics: lyrics,
      );
      if (_disposed) return '';
      final result = outcome.result;
      if (result == null) {
        if (outcome.failure == LyricsAlignFailure.inconsistent) {
          final note = await _maybeRetimeDrift(song, outcome);
          if (note != null) return ' · $note';
          return ' · 가사 판본 속도가 달라 싱크 자동 보정 불가';
        }
        // 표본 부족 등은 알리지 않는다 — 사용자가 할 일이 없다.
        return '';
      }
      // 이 안이면 사람 귀에 안 어긋난다 — 건드리지 않는 편이 안전하다.
      if (result.offsetMs.abs() <= 200) return ' · 싱크 확인됨';
      final next = await _applyAlignedOffset(song.id, result.offsetMs);
      final seconds = (next.abs() / 1000).toStringAsFixed(1);
      final direction = next < 0 ? '앞으로' : '뒤로';
      return ' · 싱크 $seconds초 $direction 보정(${result.samples}곳)';
    } catch (e) {
      debugPrint('가져오기 싱크 자동 보정 실패: $e');
      return '';
    }
  }

  /// 드리프트 곡(속도가 다른 LRC 판본)이면 재타이밍해 다시 쓴다.
  ///
  /// 원본은 .bak으로 백업하고, 재타이밍이 오프셋까지 흡수하므로 수동
  /// 오프셋은 0으로 되돌린다. 보정할 수 없으면(직선이 아니거나 속도 차가
  /// 상식 밖) null — 호출부가 기존 실패 안내를 그대로 낸다.
  Future<String?> _maybeRetimeDrift(
    Song song,
    LyricsAlignOutcome outcome,
  ) async {
    final fit = outcome.drift;
    if (outcome.failure != LyricsAlignFailure.inconsistent || fit == null) {
      return null;
    }
    try {
      final raw = await lyricsSync.rawFor(song);
      if (raw == null) return null;
      final retimed = retimeLrcContent(
        raw,
        scale: fit.scale,
        offsetMs: fit.offsetMs,
      );
      await lyricsSync.backupLrc(song);
      final saved = await lyricsSync.save(song, retimed);
      if (saved == null) return null;
      await replaceSongInList(saved);
      await _applyAlignedOffset(saved.id, 0);
      if (selectedSong?.id == song.id) {
        // 재생 중인 곡이면 다시 물려 새 타임스탬프를 즉시 반영한다.
        await playback.loadSong(
          songById(song.id) ?? saved,
          preferredSlot: selectedTrackSlot,
        );
      }
      final pct = fit.speedDiffPercent.toStringAsFixed(1);
      return '가사 판본의 속도 차이($pct%)를 보정해 다시 썼습니다 '
          '(${outcome.samples}곳 기준, 원본은 .bak으로 백업).';
    } catch (e) {
      debugPrint('가사 재타이밍 실패: $e');
      return null;
    }
  }

  /// 못 맞춘 이유를 사람 말로. 무엇이 부족한지 알려 줘야 다음 수를 정할 수 있다.
  String _alignFailureMessage(LyricsAlignOutcome outcome) {
    switch (outcome.failure) {
      case LyricsAlignFailure.inconsistent:
        final spread = (outcome.spreadMs / 1000).toStringAsFixed(1);
        return '이 가사 파일은 곡과 속도가 달라 한 값으로 맞출 수 없습니다 '
            '(어긋남이 곡마다 $spread초까지 벌어집니다). 손으로 조절해 주세요.';
      case LyricsAlignFailure.notEnoughSamples:
        return '기준 삼을 지점이 부족합니다(${outcome.samples}곳). '
            '노래가 쉬는 구간이 있어야 맞출 수 있습니다.';
      case LyricsAlignFailure.noSignal:
      case null:
        return '소리를 재지 못했습니다. 원곡과 MR 파일을 확인해 주세요.';
    }
  }

  /// 곡별 가사 선행/지연 오프셋을 바꾼다. 음수면 가사가 먼저 나온다.
  Future<void> adjustLyricsOffset(int deltaMs) async {
    final snapshotSong = selectedSong;
    final slot = selectedTrackSlot;
    if (snapshotSong == null || slot == null) return;
    // 재생 스냅샷의 곡은 오래됐을 수 있다 — 목록의 최신 인스턴스를 쓴다.
    final song = songs.firstWhere(
      (s) => s.id == snapshotSong.id,
      orElse: () => snapshotSong,
    );
    final track = song.trackForSlot(slot);
    if (track == null) return;

    final next = (track.lyricsOffsetMs + deltaMs).clamp(
      -AppConstants.maxLyricsOffsetMs,
      AppConstants.maxLyricsOffsetMs,
    );
    final updatedTracks = song.backingTracks
        .map((t) => t.slot == slot ? t.copyWith(lyricsOffsetMs: next) : t)
        .toList(growable: false);
    final updatedSong = song.copyWith(
      backingTracks: updatedTracks,
      updatedAt: DateTime.now(),
    );

    await replaceSongInList(updatedSong);
    playback.applyLyricsOffset(next);
  }

  // ── EQ 레벨 ─────────────────────────────────────────────

  /// EQ 미터용 밴드 레벨. 캐시가 있으면 즉시, 없으면 분석 후 반환.
  Future<TrackLevels?> loadTrackLevels(Song song, int slot) async {
    final track = song.trackForSlot(slot);
    if (track == null) return null;
    final cached = await levelAnalysis.cached(track.fileName);
    if (cached != null) return cached;
    final sourcePath = await repo.getBackingTrackPath(track.fileName);
    if (sourcePath == null || !await File(sourcePath).exists()) return null;
    return levelAnalysis.analyze(
      sourcePath: sourcePath,
      sourceFileName: track.fileName,
    );
  }

  /// 곡의 노래 구간(원곡−MR 비교). 둘 중 하나가 없으면 null —
  /// 그 곡은 균등 배분으로 폴백한다.
  Future<VocalSegments?> loadVocalSegments(Song song) async {
    final original = song.trackForSlot(TrackVariant.original.preferredSlot);
    final mr = song.trackForSlot(TrackVariant.mr.preferredSlot);
    if (original == null || mr == null) return null;
    final originalPath = await repo.getBackingTrackPath(original.fileName);
    final mrPath = await repo.getBackingTrackPath(mr.fileName);
    if (originalPath == null || mrPath == null) return null;
    return vocalSegments.analyze(
      originalPath: originalPath,
      mrPath: mrPath,
      cacheKey: mr.fileName,
    );
  }

  // ── 조성(키) ────────────────────────────────────────────

  /// 조성은 **MR**에서 잰다. 보컬이 살아 있는 원곡은 멜로디가 상관을 흔들어
  /// 딸림음으로 끌려간다(실측: 같은 곡의 MR은 A♭, 원곡은 E♭).
  int? keyAnalysisSlotFor(Song song) {
    final slots = song.availableTrackSlots;
    if (slots.isEmpty) return null;
    const preference = [
      TrackVariant.mr,
      TrackVariant.karaoke,
      TrackVariant.pitch,
      TrackVariant.original,
    ];
    for (final variant in preference) {
      if (slots.contains(variant.preferredSlot)) return variant.preferredSlot;
    }
    return slots.first;
  }

  /// 조성을 아직 모르는 곡이면 추정해 저장한다.
  /// 이미 값이 있으면 손대지 않는다 — 사용자가 고쳐 둔 값이 우선이다.
  Future<Song?> ensureSongKey(Song song, {Duration? duration}) async {
    if (song.musicalKey != null) return song;
    final slot = keyAnalysisSlotFor(song);
    if (slot == null) return null;
    final track = song.trackForSlot(slot);
    if (track == null) return null;
    final sourcePath = await repo.getBackingTrackPath(track.fileName);
    if (sourcePath == null || !await File(sourcePath).exists()) return null;

    final estimate = await keyDetection.analyze(
      sourcePath: sourcePath,
      sourceFileName: track.fileName,
      duration: duration,
    );
    if (estimate == null || _disposed) return null;

    // 잰 파일에 키가 구워져 있으면 그만큼 되돌려 '원곡 조성'으로 적는다.
    final base = estimate.key.transposed(-track.bakedSemitones);
    // 분석하는 동안 사용자가 직접 지정했을 수 있다 — 그 값을 이긴다고 보지 않는다.
    final fresh = songById(song.id);
    if (fresh == null || fresh.musicalKey != null) return fresh;
    final updated = fresh.copyWith(musicalKey: base, updatedAt: DateTime.now());
    await replaceSongInList(updated);
    return updated;
  }

  /// 조성을 손으로 지정하거나([key]가 null이면) 지운다.
  /// 지우면 다음 분석 때 다시 추정한다.
  Future<Song?> setSongKey(String songId, MusicKey? key) async {
    final song = songById(songId);
    if (song == null) return null;
    final updated = song.copyWith(
      musicalKey: key,
      clearMusicalKey: key == null,
      updatedAt: DateTime.now(),
    );
    await replaceSongInList(updated);
    _emit(key == null ? '조성 표시를 지웠습니다.' : '조성: ${key.label}');
    return updated;
  }

  /// 이 슬롯의 파일이 그 자체로 울리는 조성 — 곡 조성에 '구워진' 키만 얹는다.
  /// 사용자가 민 키는 빼고 준다. 키 HUD가 여기에 조절값을 더해 보여 주므로
  /// 사용자 키까지 섞으면 두 번 세게 된다.
  MusicKey? trackBaseKeyFor(Song song, int? slot) {
    final base = song.musicalKey;
    if (base == null) return null;
    final baked = slot == null
        ? 0
        : (song.trackForSlot(slot)?.bakedSemitones ?? 0);
    return base.transposed(baked);
  }

  /// 지금 들리는 조성 — 슬롯 기준 조성에 사용자가 민 키까지 얹은 값.
  MusicKey? soundingKeyFor(Song song, int? slot) =>
      trackBaseKeyFor(song, slot)?.transposed(effectivePitchFor(song, slot));

  // ── 외부 도구·서버 상태 ─────────────────────────────────

  /// 홈의 서버 상태 표시가 낡지 않도록 30초마다 가볍게 갱신한다.
  /// (분리 서버 status는 3초 타임아웃의 GET 하나 — 부담 없음)
  void _startStatusRefresh() {
    _statusRefreshTimer?.cancel();
    _statusRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_disposed) return;
      unawaited(refreshToolAvailability());
    });
  }

  Future<void> refreshToolAvailability() async {
    final tool = await toolLocator.locate(ExternalTool.ytDlp, refresh: true);
    final separator = await separation.status();
    if (_disposed) return;
    ytDlpAvailable = tool.found;
    ytDlpVersion = tool.version;
    ytDlpMissingReason = tool.found
        ? null
        : 'yt-dlp를 찾을 수 없습니다. 설치했다면 실행 파일 경로를 직접 지정해 주세요.';
    separatorStatusLabel = separator.label;
    separatorOnline = separator.online;
    _notify();
  }

  Future<void> updateYtDlpTool() async {
    final tool = await toolLocator.locate(ExternalTool.ytDlp);
    if (!tool.found) {
      _emit('yt-dlp를 찾을 수 없습니다.');
      return;
    }
    _emit('yt-dlp 업데이트를 확인하는 중...');
    final result = await const SystemProcessRunner().run(tool.path!, ['-U']);
    if (_disposed) return;
    final output = (result.stdout + result.stderr).trim();
    final lastLine = output.isEmpty
        ? (result.ok ? '완료' : '실패')
        : output.split(RegExp(r'\r?\n')).last;
    _emit('yt-dlp: $lastLine');
    await refreshToolAvailability();
  }

  Future<void> setYtDlpPath(String path) async {
    await toolLocator.setUserPath(ExternalTool.ytDlp, path);
    await refreshToolAvailability();
    _emit(ytDlpAvailable ? 'yt-dlp 경로를 저장했습니다.' : '해당 파일을 실행할 수 없습니다.');
  }

  // ── 저작권 확인 (최초 1회, 앱에서만 세팅 가능) ──────────

  Future<bool> hasYoutubeAck() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kYtNoticeAckKey) ?? false;
  }

  Future<void> ackYoutubeNotice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kYtNoticeAckKey, true);
  }

  // ── 유튜브 가져오기 파이프라인 ──────────────────────────

  /// 가져오기 큐에 넣는다. 저작권 확인(ack)이 안 돼 있으면 거절한다 —
  /// 제어 API가 이 확인을 우회할 수 없게 하기 위해서다.
  Future<ImportEnqueueOutcome> enqueueImport(
    String url,
    MrSourceMode mode, {
    bool fetchLyrics = true,
    ImportPlan plan = const ImportPlan.single(),
  }) async {
    if (!looksLikeYoutubeUrl(url)) {
      return const ImportEnqueueOutcome.error(
        'not_youtube_url',
        '유튜브 주소가 아닙니다. 링크를 다시 확인해 주세요.',
      );
    }
    if (!await hasYoutubeAck()) {
      return const ImportEnqueueOutcome.error(
        'notice_not_acked',
        '앱에서 최초 1회 저작권 확인이 필요합니다. 앱의 곡 추가에서 "확인했습니다"를 눌러 주세요.',
      );
    }
    if (plan.makeInstrumental &&
        mode == MrSourceMode.aiSeparate &&
        !separatorOnline) {
      return const ImportEnqueueOutcome.error(
        'separator_offline',
        '분리 서버가 꺼져 있어 MR을 만들 수 없습니다. SAW에서 켜 주세요.',
      );
    }
    final job = importJobs.enqueue(
      url: url,
      mode: mode,
      id: const Uuid().v4(),
      fetchLyrics: fetchLyrics,
      plan: plan,
    );
    return ImportEnqueueOutcome.ok(job.id);
  }

  /// 작업 1건 수행: 메타 조회 → 내려받기 → 곡으로 등록.
  Future<void> _runImportJob(
    ImportJob job, {
    required void Function(JobProgress progress) onProgress,
    required void Function(void Function() cancel) onCancel,
  }) async {
    onProgress(const JobProgress(label: '영상 정보 확인 중'));
    final metadata = await youtubeImport.fetchMetadata(job.url);
    if (metadata == null) {
      _failJob(job, '영상 정보를 가져오지 못했습니다. 링크와 yt-dlp 설치를 확인해 주세요.');
      return;
    }
    importJobs.update(
      importJobs.jobById(job.id)?.copyWith(title: metadata.title) ?? job,
    );

    final result = await youtubeImport.download(
      url: job.url,
      jobId: job.id,
      metadata: metadata,
      mode: job.mode,
      onProgress: onProgress,
      onCancel: onCancel,
    );

    // 사용자가 중간에 취소했으면 결과를 덮어쓰지 않는다.
    final current = importJobs.jobById(job.id);
    if (current == null || current.status != ImportJobStatus.running) {
      await youtubeImport.cleanupJob(job.id);
      return;
    }

    if (!result.success) {
      // 원인별 안내는 describeDownloadFailure가 이미 담았다.
      // 여기서 힌트를 덧붙이면 403(일시 차단)에도 "yt-dlp 업데이트" 같은
      // 엉뚱한 안내가 따라붙는다.
      _failJob(job, result.message ?? '가져오기에 실패했습니다.');
      await youtubeImport.cleanupJob(job.id);
      return;
    }

    // 내려받은 원본은 절대 덮어쓰지 않는다 — 원곡 슬롯이 여기서 나온다.
    final originalPath = result.audioPath!;

    // 기존 곡에 반주만 더하는 작업이면 여기서 갈라진다.
    final targetSongId = job.targetSongId;
    if (targetSongId != null) {
      await _runTrackImport(
        job,
        songId: targetSongId,
        originalPath: originalPath,
        onProgress: onProgress,
      );
      await youtubeImport.cleanupJob(job.id);
      return;
    }

    String? instrumentalPath;
    var separationNote = '';
    if (job.mode == MrSourceMode.aiSeparate) {
      onProgress(const JobProgress(label: 'AI 보컬 분리 중 (수십 초 걸립니다)'));
      final separated = await separation.separate(originalPath);
      if (separated.success && separated.instrumentalPath != null) {
        instrumentalPath = separated.instrumentalPath;
      } else {
        // 분리에 실패해도 원곡은 등록한다(부분 성공).
        separationNote = ' · MR 분리 실패';
      }
    }

    final plan = job.plan;
    final planned = resolveImportPlan(
      plan: ImportPlan(
        // 분리가 없거나 실패했으면 MR 슬롯을 만들 수 없다.
        makeInstrumental: plan.makeInstrumental && instrumentalPath != null,
        makeOriginal: plan.makeOriginal || instrumentalPath == null,
        pitchSemitones: plan.pitchSemitones,
      ),
      pitchLabel: plan.wantsPitch
          ? '키조절 ${formatKeyLabel(plan.pitchSemitones!)}'
          : null,
    );

    final slotPaths = <int, String>{};
    final slotLabels = <int, String>{};
    final slotBaked = <int, int>{};
    int? mrSlot;
    PlannedTrack? pitchPlanned;
    for (final track in planned.tracks) {
      switch (track.variant) {
        case TrackVariant.original:
          slotPaths[track.slot] = originalPath;
        case TrackVariant.mr:
          slotPaths[track.slot] = instrumentalPath ?? originalPath;
          mrSlot = track.slot;
        case TrackVariant.pitch:
          // 키조절본은 리포지토리에 복사된 MR을 원본으로 삼아야
          // 캐시 키가 안정적이다. 곡 등록 뒤 2단계로 만든다.
          pitchPlanned = track;
          continue;
        case TrackVariant.karaoke:
          slotPaths[track.slot] = originalPath;
      }
      slotLabels[track.slot] = track.label;
      slotBaked[track.slot] = track.bakedSemitones;
    }

    onProgress(const JobProgress(ratio: 1, label: '곡으로 등록 중'));
    var song = await _registerImportedSong(
      metadata: metadata,
      slotPaths: slotPaths,
      slotLabels: slotLabels,
      slotBaked: slotBaked,
    );
    await youtubeImport.cleanupJob(job.id);

    if (song == null) {
      _failJob(job, '곡 등록에 실패했습니다.');
      return;
    }

    // 키조절 슬롯 — MR(없으면 원곡)을 기준으로 구워 넣는다.
    var pitchNote = '';
    if (pitchPlanned != null) {
      onProgress(
        JobProgress(
          ratio: 1,
          label: '${formatKeyLabel(plan.pitchSemitones!)} 반주 만드는 중',
        ),
      );
      final baseSlot = mrSlot ?? song.availableTrackSlots.firstOrNull;
      final rendered = baseSlot == null
          ? null
          : await _renderPitchSlot(
              song: song,
              baseSlot: baseSlot,
              targetSlot: pitchPlanned.slot,
              semitones: pitchPlanned.bakedSemitones,
              label: pitchPlanned.label,
            );
      if (rendered != null) {
        song = rendered;
      } else {
        pitchNote = ' · 키조절본 실패';
      }
    }

    if (planned.dropped.isNotEmpty) {
      final names = planned.dropped.map((v) => v.label).join('·');
      pitchNote += ' · 슬롯 부족으로 $names 건너뜀';
    }

    // 첫 무대 진입 때 EQ가 바로 뜨도록 등록 직후 백그라운드로 선분석한다.
    for (final slot in song.availableTrackSlots) {
      unawaited(loadTrackLevels(song, slot));
    }
    // 노래 구간도 같은 자리에서 — 가사 없는 곡의 줄 배분에 바로 쓰인다.
    unawaited(loadVocalSegments(song));
    // 조성도 같은 자리에서 — 길이를 아는 지금이 표본 구간을 잡기 좋다.
    unawaited(ensureSongKey(song, duration: metadata.duration));

    // 가사까지 한 흐름에서 붙인다. 실패해도 곡 자체는 남긴다.
    var lyricsNote = '';
    if (job.fetchLyrics) {
      onProgress(const JobProgress(ratio: 1, label: '가사 찾는 중'));
      final outcome = await lyricsSync.fetchFor(
        song,
        duration: metadata.duration,
      );
      if (outcome.success && outcome.song != null) {
        song = outcome.song!;
        await replaceSongInList(song);
        lyricsNote = ' · 가사 포함';
        onProgress(const JobProgress(ratio: 1, label: '가사 싱크 맞추는 중'));
        lyricsNote += await _autoAlignNoteFor(song);
      } else {
        lyricsNote = ' · 가사는 찾지 못함';
      }
    }

    final extra = '$lyricsNote$separationNote$pitchNote';
    final slotNote = ' · 반주 ${song.availableTrackSlots.length}개';
    final finished = importJobs.jobById(job.id);
    if (finished == null) return;
    importJobs.update(
      finished.copyWith(
        status: ImportJobStatus.done,
        statusDetail: '재생목록에 추가했습니다$slotNote$extra.',
        songId: song.id,
        ratio: 1,
      ),
    );
    _emit('"${song.title}" 추가 완료$slotNote$extra');
  }

  /// 기존 곡의 한 슬롯에 내려받은 반주를 넣는다.
  Future<void> _runTrackImport(
    ImportJob job, {
    required String songId,
    required String originalPath,
    required void Function(JobProgress progress) onProgress,
  }) async {
    var audioPath = originalPath;
    if (job.mode == MrSourceMode.aiSeparate) {
      onProgress(const JobProgress(label: 'AI 보컬 분리 중 (수십 초 걸립니다)'));
      final separated = await separation.separate(originalPath);
      if (separated.success && separated.instrumentalPath != null) {
        audioPath = separated.instrumentalPath!;
      }
    }

    final song = songById(songId);
    if (song == null) {
      _failJob(job, '대상 곡을 찾을 수 없습니다.');
      return;
    }
    final slot = job.targetSlot ?? _firstFreeSlot(song);
    if (slot == null) {
      _failJob(job, '반주 슬롯이 모두 찼습니다.');
      return;
    }

    onProgress(const JobProgress(ratio: 1, label: '반주 넣는 중'));
    final updated = await attachTrackToSong(
      songId: songId,
      slot: slot,
      sourcePath: audioPath,
      label: job.trackLabel ?? TrackVariant.karaoke.label,
    );
    if (updated == null) {
      _failJob(job, '반주를 넣지 못했습니다.');
      return;
    }

    final finished = importJobs.jobById(job.id);
    if (finished == null) return;
    final label = updated.trackForSlot(slot)?.label ?? '반주';
    importJobs.update(
      finished.copyWith(
        status: ImportJobStatus.done,
        statusDetail: '슬롯 $slot에 "$label"을(를) 넣었습니다.',
        songId: updated.id,
        ratio: 1,
      ),
    );
    _emit('"${updated.title}" 슬롯 $slot에 $label 추가');
  }

  /// 이미 등록된 반주를 기준으로 키조절본을 만들어 다른 슬롯에 넣는다.
  Future<Song?> _renderPitchSlot({
    required Song song,
    required int baseSlot,
    required int targetSlot,
    required int semitones,
    required String label,
  }) async {
    try {
      final base = song.trackForSlot(baseSlot);
      if (base == null) return null;
      final sourcePath = await repo.getBackingTrackPath(base.fileName);
      if (sourcePath == null) return null;

      final rendered = await pitchVariants.render(
        sourcePath: sourcePath,
        sourceFileName: base.fileName,
        semitones: semitones,
      );
      if (!rendered.success || rendered.path == null) return null;

      return attachTrackToSong(
        songId: song.id,
        slot: targetSlot,
        sourcePath: rendered.path!,
        label: label,
        bakedSemitones: semitones,
      );
    } catch (e) {
      debugPrint('키조절 슬롯 생성 실패: $e');
      return null;
    }
  }

  /// 목록의 곡을 최신 인스턴스로 갈아끼우고 저장한다.
  Future<void> replaceSongInList(Song song) async {
    if (_disposed) return;
    songs = songs
        .map((s) => s.id == song.id ? song : s)
        .toList(growable: false);
    _notify();
    await repo.saveSongs(songs);
  }

  void _failJob(ImportJob job, String message) {
    final current = importJobs.jobById(job.id);
    if (current == null) return;
    importJobs.update(
      current.copyWith(
        status: ImportJobStatus.failed,
        statusDetail: message,
        clearRatio: true,
      ),
    );
  }

  /// 받은 오디오들을 슬롯에 배치해 곡을 만든다.
  /// 가사는 이어지는 단계에서 채운다. 실패하면 null.
  Future<Song?> _registerImportedSong({
    required YoutubeMetadata metadata,
    required Map<int, String> slotPaths,
    required Map<int, String> slotLabels,
    Map<int, int> slotBaked = const {},
  }) async {
    try {
      // 유튜브 제목의 MR/노래방/키 표기를 걷어내고 가수를 분리한다 —
      // 곡 목록 표기와 가사 검색 적중률 양쪽에 중요하다.
      final cleaned = cleanYoutubeSongName(
        metadata.title,
        uploader: metadata.uploader,
      );
      final title = libraryService.hasDuplicateTitle(songs, cleaned.title)
          ? '${cleaned.title} (가져오기)'
          : cleaned.title;
      final draft = SongDraft(
        title: title.isEmpty ? '제목 없음' : title,
        artist: cleaned.artist ?? metadata.uploader,
        trackPaths: slotPaths,
        trackLabels: slotLabels,
        trackBakedSemitones: slotBaked,
      );
      final result = await libraryService.addSong(
        songs: songs,
        draft: draft,
        lyrics: '',
      );
      if (_disposed) return null;
      songs = result.songs;
      _notify();
      // 방금 추가된 곡 — 가사 부착·선택에 이어 쓴다.
      return result.song;
    } catch (e) {
      debugPrint('가져온 곡 등록 실패: $e');
      return null;
    }
  }

  // ── 반주 슬롯 관리 ──────────────────────────────────────

  /// 기존 곡의 한 슬롯에 반주를 넣는다(있으면 갈아끼운다).
  ///
  /// 파일명이 슬롯마다 고정이라 같은 이름으로 다른 오디오가 들어간다 —
  /// 파생 캐시를 반드시 비워야 엉뚱한 키·파형이 서빙되지 않는다.
  Future<Song?> attachTrackToSong({
    required String songId,
    required int slot,
    required String sourcePath,
    required String label,
    int bakedSemitones = 0,
  }) async {
    final song = songById(songId);
    if (song == null) return null;
    try {
      final updated = await repo.addBackingTrack(
        song: song,
        slot: slot,
        sourcePath: sourcePath,
        label: label,
        bakedSemitones: bakedSemitones,
      );
      final track = updated.trackForSlot(slot);
      if (track != null) await trackAssets.invalidate(track.fileName);
      await replaceSongInList(updated);
      unawaited(loadTrackLevels(updated, slot));
      if (selectedSong?.id == songId) {
        await playback.loadSong(updated, preferredSlot: selectedTrackSlot);
      }
      return updated;
    } catch (e) {
      debugPrint('반주 추가 실패: $e');
      return null;
    }
  }

  /// 슬롯에서 반주를 빼고 파일·파생 캐시를 지운다.
  Future<Song?> removeTrackFromSong({
    required String songId,
    required int slot,
  }) async {
    final song = songById(songId);
    if (song == null) return null;
    final track = song.trackForSlot(slot);
    if (track == null) return null;
    final updated = await repo.removeBackingTrack(song: song, slot: slot);
    await trackAssets.invalidate(track.fileName);
    await replaceSongInList(updated);
    if (selectedSong?.id == songId && selectedTrackSlot == slot) {
      await playback.loadSong(updated);
    }
    return updated;
  }

  /// 기존 곡에 링크로 반주를 더하는 작업을 큐에 넣는다.
  Future<ImportEnqueueOutcome> enqueueTrackImport({
    required String songId,
    required String url,
    required MrSourceMode mode,
    int? slot,
    String? label,
  }) async {
    final song = songById(songId);
    if (song == null) {
      return const ImportEnqueueOutcome.error(
        'song_not_found',
        '곡을 찾을 수 없습니다.',
      );
    }
    if (!looksLikeYoutubeUrl(url)) {
      return const ImportEnqueueOutcome.error(
        'not_youtube_url',
        '유튜브 주소가 아닙니다. 링크를 다시 확인해 주세요.',
      );
    }
    if (!await hasYoutubeAck()) {
      return const ImportEnqueueOutcome.error(
        'notice_not_acked',
        '앱에서 최초 1회 저작권 확인이 필요합니다. 앱의 곡 추가에서 "확인했습니다"를 눌러 주세요.',
      );
    }
    final resolved = slot ?? _firstFreeSlot(song);
    if (resolved == null) {
      return const ImportEnqueueOutcome.error(
        'no_free_slot',
        '반주 슬롯이 모두 찼습니다. 덮어쓸 슬롯을 지정해 주세요.',
      );
    }
    final job = importJobs.enqueue(
      url: url,
      mode: mode,
      id: const Uuid().v4(),
      fetchLyrics: false,
      targetSongId: songId,
      targetSlot: resolved,
      trackLabel: label,
    );
    return ImportEnqueueOutcome.ok(job.id);
  }

  int? _firstFreeSlot(Song song) {
    final used = song.availableTrackSlots.toSet();
    for (final slot in AppConstants.backingTrackSlots) {
      if (!used.contains(slot)) return slot;
    }
    return null;
  }

  // ── 곡 관리 (헤드리스 — 확인 UI 없음, 제어 API용) ───────

  Future<void> toggleFavorite(Song song) async {
    final result = await libraryService.toggleFavorite(
      songs: songs,
      song: song,
    );
    if (_disposed) return;
    songs = result.songs;
    _notify();
    if (selectedSong?.id == song.id) {
      await playback.loadSong(result.song, preferredSlot: selectedTrackSlot);
    }
  }

  /// 확인 대화상자 없이 곡을 실제로 삭제한다(파일 포함, 되돌릴 수 없음).
  /// 제어 API 전용 — 화면의 삭제는 확인 대화상자 + 실행 취소 경로를 쓴다.
  Future<bool> removeSong(String songId) async {
    final song = songById(songId);
    if (song == null) return false;
    final result = await libraryService.deleteSong(
      songs: songs,
      queue: queue,
      song: song,
      selectedSong: selectedSong,
    );
    if (result.selectedSong == null) {
      await repo.saveLastSongId(null);
    }
    songs = result.songs;
    queue = result.queue;
    _notify();

    if (result.deletedSelectedSong) {
      await playback.stop();
      playback.clearSelection();
      if (result.selectedSong != null) {
        await playback.loadSong(result.selectedSong!);
      }
    }
    await libraryService.permanentlyDeleteSong(song);
    _emit('"${song.title}" 삭제됨');
    return true;
  }

  /// 제목·가수·가사만 고친다. 반주 파일은 건드리지 않는다.
  Future<Song?> updateSongFields(
    String songId, {
    String? title,
    String? artist,
    String? lyrics,
  }) async {
    final song = songById(songId);
    if (song == null) return null;
    final nextTitle = (title ?? song.title).trim();
    if (nextTitle != song.title &&
        libraryService.hasDuplicateTitle(songs, nextTitle,
            excludeId: song.id)) {
      _emit('같은 제목의 곡이 이미 있습니다.');
      return null;
    }
    final draft = SongEditDraft(
      title: nextTitle,
      artist: artist ?? song.artist,
      lyricsText: lyrics ?? song.lyricsText,
      trackPaths: const {},
    );
    final result = await libraryService.editSong(
      songs: songs,
      song: song,
      draft: draft,
    );
    if (_disposed) return result.song;
    songs = result.songs;
    _notify();
    if (selectedSong?.id == songId) {
      await playback.loadSong(result.song, preferredSlot: selectedTrackSlot);
    }
    return result.song;
  }

  // ── 예약 큐 ─────────────────────────────────────────────

  Future<void> reserveSong(Song song) async {
    await _applyQueueChange(
      queueService.addSong(queue: queue, song: song, settings: settings),
      message: '"${song.title}" 예약 완료',
    );
  }

  Future<void> reserveAll(List<Song> songsToAdd) async {
    await _applyQueueChange(
      queueService.addSongs(queue: queue, songs: songsToAdd, settings: settings),
      message: '${songsToAdd.length}곡 예약 완료',
    );
  }

  Future<void> removeQueueItem(int index) =>
      _applyQueueChange(queueService.removeAt(queue, index));

  Future<void> reorderQueue(int oldIndex, int newIndex) =>
      _applyQueueChange(queueService.reorder(queue, oldIndex, newIndex));

  Future<void> clearQueue() => _applyQueueChange(queueService.clear());

  Future<void> _applyQueueChange(
    Future<List<QueueItem>> queueTask, {
    String? message,
  }) async {
    final next = await queueTask;
    if (_disposed) return;
    queue = next;
    _notify();
    if (message != null) _emit(message);
  }
}
