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
import '../models/recording_take.dart';
import '../models/backing_track.dart';
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
import '../services/deepseek_lyrics_client.dart';
import '../services/stt_lyrics_client.dart';
import '../services/pitch_coach_client.dart';
import '../models/vocal_segments.dart';
import '../services/vocal_segments_service.dart';
import '../services/vocal_separation_client.dart';
import '../services/youtube_import_service.dart';
import '../utils/key_label.dart';
import '../utils/lrc_edit.dart';
import '../utils/lyrics_refine.dart';
import '../utils/lrc_retime.dart';
import '../utils/lyrics_line_utils.dart';
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
  static const _kSeparatorCmdKey = 'separator_start_command';
  static const _kSttCmdKey = 'stt_start_command';

  /// 이 PC의 분리 서버 기동 스크립트. 부팅 시 값이 없으면 이걸 심는다.
  /// 값을 비우면 자동 기동을 끈 것으로 본다.
  static const defaultSeparatorStartCommand =
      r'C:\Projects\svil-ai-work\separator_system\start.bat';

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
  final SttLyricsClient sttLyrics = SttLyricsClient();
  final DeepSeekLyricsClient deepSeekLyrics = DeepSeekLyricsClient();
  final PitchCoachClient pitchCoach = PitchCoachClient();
  late final PrompterAudioService audio = PrompterAudioService(repo);
  final ScrollController lyricsScrollController = ScrollController();
  late final ImportJobController importJobs;
  late final PlaybackController playback;

  // ── UI 연결점 (화면이 설정; 없어도 동작한다) ─────────────
  void Function(String message)? onMessage;

  /// 제어 API의 화면 전환 요청(home/search/favorites/training/recordings/
  /// jobs/settings/stage/back). 화면(State)이 부팅 때 연결한다.
  /// 처리했으면 true — 모르는 이름이면 false를 돌려 API가 422로 알린다.
  bool Function(String view)? onNavigate;
  void Function(PlaybackSnapshot snapshot, Duration played)?
  onPracticeSessionEnded;

  // ── 상태 ────────────────────────────────────────────────
  List<Song> songs = [];

  /// 예약 큐 3슬롯. [queue]는 활성 슬롯의 별칭이라 기존 코드(서비스·API)가
  /// 슬롯을 모른 채 그대로 동작한다 — 저장도 저장소가 활성 슬롯을 따라간다.
  List<List<QueueItem>> queueSlots = [[], [], []];
  int activeQueueSlot = 0;

  List<QueueItem> get queue => queueSlots[activeQueueSlot];
  set queue(List<QueueItem> next) => queueSlots[activeQueueSlot] = next;

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
    stopManagedServers(); // 앱이 띄운 서버는 앱과 함께 끈다.
    _statusRefreshTimer?.cancel();
    _pitchApplyTimer?.cancel();
    _tempoApplyTimer?.cancel();
    _partialShiftTimer?.cancel();
    pendingPitch.dispose();
    pendingTempo.dispose();
    importJobs.dispose();
    sttLyrics.close();
    deepSeekLyrics.close();
    pitchCoach.close();
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
    queueSlots = List.of(initial.queueSlots);
    activeQueueSlot = initial.activeQueueSlot;
    settings = initial.settings;
    loading = false;
    _notify();

    unawaited(refreshToolAvailability());
    _startStatusRefresh();

    // 분리 서버 자동 기동 명령 — 처음이면 이 PC의 기본 경로를 심는다.
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_kSeparatorCmdKey)) {
      await prefs.setString(_kSeparatorCmdKey, defaultSeparatorStartCommand);
    }

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

  /// LRC 원문을 곡에 직접 붙인다 — LRCLIB에 없는 곡(로컬 전사 등)의 입구.
  /// 해석에 실패하거나 곡이 없으면 null.
  Future<Song?> attachLrc({
    required String songId,
    required String content,
  }) async {
    final song = songById(songId);
    if (song == null) return null;
    final updated = await lyricsSync.save(song, content);
    if (updated == null) return null;
    // 새 가사가 부착됐다 — 옛 .bak은 남의 판본이라 복구(G) 대상이 아니다.
    await lyricsSync.invalidateBackup(updated);
    _lyricsUndoStack.remove(songId);
    await replaceSongInList(updated);
    if (selectedSong?.id == songId) {
      // 화면에 즉시 반영하고 싱크 모드로 전환한다(가져오기와 같은 규약).
      playback.timedLyrics.value = await lyricsSync.loadFor(updated);
      await updateSettings(
        settings.copyWith(displayMode: PrompterDisplayMode.timed),
      );
    }
    return updated;
  }

  /// 가사 다시 생성 — 정밀 파이프라인(사용자 지정, 2026-07-31).
  ///
  /// 받아쓰기(v2.15)와의 차이: ① 보컬 스템으로 전사(반주 환청 원천 차단)
  /// ② 단어 타임스탬프·신뢰도·보컬 에너지 근거로 환청 줄 자동 정리
  /// ③ (선택) DeepSeek 텍스트 교차 검증 ④ (선택) 정답 가사 대조 —
  /// 타이밍은 STT, 텍스트는 정답. 실패 근거는 전부 스낵으로 알린다.
  Future<bool> regenerateLyrics({
    String? songId,
    bool useVocalStem = true,
    bool useDeepSeek = true,
    bool useYoutubeSubs = true,
    String? referenceLyrics,
  }) async {
    if (_syncLockBlocked()) return false;
    final song = songId == null ? selectedSong : songById(songId);
    if (song == null) {
      _emit('먼저 곡을 선택해 주세요.');
      return false;
    }

    // 유튜브 수동 자막 — 타이밍까지 있는 정답이라 받아쓰기보다 우선.
    // (정답 가사를 직접 붙여넣었으면 그 의도를 존중해 받아쓰기 경로로 간다)
    final url = song.sourceUrl?.trim() ?? '';
    if (useYoutubeSubs &&
        url.isNotEmpty &&
        (referenceLyrics?.trim() ?? '').isEmpty) {
      _emit('유튜브 자막 확인 중…');
      final subs = await youtubeImport.fetchManualSubtitles(url);
      if (_disposed) return false;
      if (subs != null && subs.isNotEmpty) {
        final isCurrentSong = selectedSong?.id == song.id;
        final lrc = lrcFromSttSegments(
          subs,
          title: song.title,
          artist: song.artist,
          duration:
              isCurrentSong && playback.snapshot.duration > Duration.zero
                  ? playback.snapshot.duration
                  : null,
        );
        final attached = await attachLrc(songId: song.id, content: lrc);
        if (attached != null) {
          _emit('유튜브 자막으로 가사 ${subs.length}줄 생성 완료');
          return true;
        }
      }
      _emit('수동 자막이 없어 받아쓰기로 진행합니다.');
    }

    // 음원 — 보컬 스템 우선. 분리가 안 되면 원곡 풀믹스로 폴백.
    String? audioPath;
    if (useVocalStem) {
      _emit('보컬 분리 중… (수십 초 걸립니다)');
      audioPath = await vocalStemForSong(song);
      if (_disposed) return false;
      if (audioPath == null) _emit('보컬 분리를 못 해 원곡으로 받아씁니다.');
    }
    if (audioPath == null) {
      final track =
          song.trackForSlot(TrackVariant.original.preferredSlot) ??
          song.backingTracks.firstOrNull;
      if (track == null) {
        _emit('받아쓸 음원이 없습니다. 먼저 반주를 등록해 주세요.');
        return false;
      }
      audioPath = await repo.getBackingTrackPath(track.fileName);
      if (audioPath == null) {
        _emit('음원 파일을 찾을 수 없습니다.');
        return false;
      }
    }

    if (!await sttLyrics.isOnline()) {
      _emit('STT 서버 켜는 중… (최대 1~2분)');
      if (!await ensureSttOnline()) {
        _emit('STT 서버를 켜지 못했습니다(8769). start.bat 경로를 확인해 주세요.');
        return false;
      }
    }
    _emit('AI 받아쓰기 중… (수십 초 걸립니다)');
    final result = await sttLyrics.transcribe(audioPath);
    if (_disposed) return false;
    if (!result.success) {
      _emit(result.message ?? '받아쓰기에 실패했습니다.');
      return false;
    }

    final isCurrent = selectedSong?.id == song.id;
    final durationMs =
        isCurrent && playback.snapshot.duration > Duration.zero
            ? playback.snapshot.duration.inMilliseconds
            : null;

    // 근거 ①·② — 신뢰도 + 보컬 에너지 구간(없으면 신뢰도만).
    final vocal = await loadVocalSegments(song);
    final refined = refineSttSegments(
      result.segments,
      vocalSegments: [
        for (final v in vocal?.segments ?? const <VocalSegment>[])
          (startMs: v.startMs, endMs: v.endMs),
      ],
      durationMs: durationMs,
    );
    var kept = refined.kept;
    var cutCount = refined.dropped.length;

    // 근거 ③ — DeepSeek 텍스트 검증(키 있을 때만, 실패해도 계속).
    if (useDeepSeek && deepSeekLyrics.available && kept.isNotEmpty) {
      _emit('AI 텍스트 검증 중… (DeepSeek)');
      final flags = await deepSeekLyrics.flagSuspiciousLines(
        [for (final s in kept) s.text],
      );
      if (_disposed) return false;
      if (flags != null && flags.isNotEmpty) {
        final survivors = <SttSegment>[];
        for (var i = 0; i < kept.length; i++) {
          if (flags.containsKey(i)) {
            cutCount++;
            continue;
          }
          survivors.add(kept[i]);
        }
        kept = survivors;
      }
    }

    // ④ — 정답 가사 대조: 타이밍은 STT, 텍스트는 정답.
    final ref = referenceLyrics?.trim() ?? '';
    if (ref.isNotEmpty && kept.isNotEmpty) {
      if (!deepSeekLyrics.available) {
        _emit('정답 가사 대조에는 DEEPSEEK_API_KEY가 필요해요 — 대조 없이 진행합니다.');
      } else {
        _emit('정답 가사 대조 중…');
        final matches = await deepSeekLyrics.alignWithReference(
          [for (final s in kept) s.text],
          ref,
        );
        if (_disposed) return false;
        if (matches == null) {
          _emit('정답 가사 대조에 실패했어요 — 받아쓴 텍스트 그대로 진행합니다.');
        } else {
          final applied = applyReferenceLyrics(kept, matches);
          kept = applied.kept;
          cutCount += applied.dropped.length;
        }
      }
    }

    if (kept.isEmpty) {
      _emit('필터를 통과한 가사 줄이 없습니다 — 기존 가사를 그대로 둡니다.');
      return false;
    }
    final lrc = lrcFromSttSegments(
      kept,
      title: song.title,
      artist: song.artist,
      duration: durationMs == null ? null : Duration(milliseconds: durationMs),
    );
    final attached = await attachLrc(songId: song.id, content: lrc);
    if (attached == null) {
      _emit('가사를 붙이지 못했습니다.');
      return false;
    }
    _emit(
      '가사 ${kept.length}줄 생성 완료 — 정리 $cutCount줄'
      '${ref.isNotEmpty ? ' · 정답 가사 반영' : ''}',
    );
    return true;
  }

  /// 로컬 STT(faster-whisper)로 노래를 받아써 싱크 가사를 만든다 —
  /// LRCLIB에 없는 곡의 마지막 수단. 받아쓰기라 오탈자가 있을 수 있고,
  /// 그건 프롬프터에서 줄을 길게 눌러 고친다([editLyricsLine]).
  Future<bool> generateSttLyrics({String? songId, Duration? duration}) async {
    final song = songId == null ? selectedSong : songById(songId);
    if (song == null) {
      _emit('먼저 곡을 선택해 주세요.');
      return false;
    }
    // 보컬이 들어 있는 원곡(1번)을 우선한다 — MR을 받아쓰면 아무것도 없다.
    final track =
        song.trackForSlot(TrackVariant.original.preferredSlot) ??
        song.backingTracks.firstOrNull;
    if (track == null) {
      _emit('받아쓸 음원이 없습니다. 먼저 반주를 등록해 주세요.');
      return false;
    }
    final path = await repo.getBackingTrackPath(track.fileName);
    if (path == null) {
      _emit('음원 파일을 찾을 수 없습니다.');
      return false;
    }
    if (!await sttLyrics.isOnline()) {
      _emit('STT 서버 켜는 중… (최대 1~2분)');
      if (!await ensureSttOnline()) {
        _emit('STT 서버를 켜지 못했습니다(8769). start.bat 경로를 확인해 주세요.');
        return false;
      }
    }

    _emit('AI 받아쓰기 중… 수십 초 걸립니다.');
    final result = await sttLyrics.transcribe(path);
    if (_disposed) return false;
    if (!result.success) {
      _emit(result.message ?? '받아쓰기에 실패했습니다.');
      return false;
    }

    final isCurrent = selectedSong?.id == song.id;
    final lrc = lrcFromSttSegments(
      result.segments,
      title: song.title,
      artist: song.artist,
      // 곡 길이 밖의 환청 가사를 걸러낸다(페이드아웃에서 지어내는 일이 있다).
      // 가져오기 흐름은 메타데이터 길이를 넘겨준다(아직 재생 전이라).
      duration:
          duration ??
          (isCurrent && playback.snapshot.duration > Duration.zero
              ? playback.snapshot.duration
              : null),
    );
    final lineCount = result.segments.where((s) => s.text.isNotEmpty).length;
    if (lineCount == 0) {
      _emit('노래에서 가사를 알아듣지 못했습니다.');
      return false;
    }
    final attached = await attachLrc(songId: song.id, content: lrc);
    if (attached == null) {
      _emit('받아쓴 가사를 붙이지 못했습니다.');
      return false;
    }
    _emit('가사 $lineCount줄을 받아썼습니다. 틀린 줄은 가사를 길게 눌러 고칠 수 있습니다.');
    return true;
  }

  /// 현재 곡의 표시 줄 [index]의 텍스트를 고친다 — 프롬프터 인라인 수정.
  ///
  /// 싱크 가사(LRC)가 있으면 타임스탬프는 그대로 두고 그 줄의 텍스트만
  /// 바꾼다. 없으면 일반 가사 텍스트의 해당 줄을 바꾼다.
  Future<bool> editLyricsLine({required int index, required String text}) async {
    final song = selectedSong == null ? null : songById(selectedSong!.id);
    if (song == null) return false;
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      _emit('빈 줄로는 바꿀 수 없습니다.');
      return false;
    }

    final synced = playback.timedLyrics.value;
    if (synced != null && !synced.isEmpty) {
      final raw = await lyricsSync.rawFor(song);
      if (raw == null) return false;
      final next = replaceLrcLineText(
        raw,
        displayIndex: index,
        newText: trimmed,
      );
      if (next == null) return false;
      _pushLyricsUndo(song.id, raw);
      final saved = await lyricsSync.save(song, next);
      if (saved == null) return false;
      await replaceSongInList(saved);
      playback.timedLyrics.value = await lyricsSync.loadFor(saved);
      return true;
    }

    // 일반 가사 — 표시 줄(빈 줄 제외)을 원본 줄 번호로 되돌려 바꾼다.
    final indexed = LyricsLineUtils.splitLinesIndexed(song.lyricsText);
    if (index < 0 || index >= indexed.length) return false;
    final sourceLines = song.lyricsText.split(RegExp(r'\r?\n'));
    sourceLines[indexed[index].sourceIndex] = trimmed;
    final updated = await updateSongFields(
      song.id,
      lyrics: sourceLines.join('\n'),
    );
    return updated != null;
  }

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
      // 새 가사가 부착됐다 — 옛 .bak·실행취소 스택은 예전 판본의 것이다.
      await lyricsSync.invalidateBackup(updated);
      _lyricsUndoStack.remove(updated.id);
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

  /// 측정된 오프셋을 **원곡 녹음을 쓰는 슬롯(1·2·3)에만** 적용하고,
  /// 실제 적용값(클램프 후)을 돌려준다.
  ///
  /// 측정 자체가 원곡−MR 비교라 그 녹음에만 유효한 값이다. 노래방(4번)은
  /// 다른 녹음이므로 여기 쓰면 안 된다 — 예전에는 전 슬롯에 덮어써서,
  /// 사용자가 노래방 슬롯에 T로 맞춰 둔 싱크를 자동 맞춤이 지웠다.
  Future<int> _applyAlignedOffset(String songId, int offsetMs) async {
    final next = offsetMs.clamp(
      -AppConstants.maxLyricsOffsetMs,
      AppConstants.maxLyricsOffsetMs,
    );
    final fresh = songById(songId);
    if (fresh == null) return next;
    final basisSlot = TrackVariant.original.preferredSlot;
    await replaceSongInList(fresh.withLyricsOffsetForSlot(basisSlot, next));
    // 지금 듣는 슬롯이 그 녹음일 때만 화면에 반영한다 — 노래방을 듣는 중에
    // 다른 녹음의 값을 얹으면 눈앞의 싱크가 틀어진다.
    if (selectedSong?.id == songId &&
        lyricsSyncSlotGroup(basisSlot).contains(selectedTrackSlot)) {
      playback.applyLyricsOffset(next);
    }
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
  /// 오프셋은 0으로 되돌린다(원곡 녹음 슬롯 1·2·3만 — 노래방 슬롯의 수동
  /// 싱크는 자동 처리가 건드리지 않는다는 규약. LRC 시간축이 바뀌었으니
  /// 노래방 쪽은 사용자가 T로 다시 잡는다). 보정할 수 없으면(직선이
  /// 아니거나 속도 차가 상식 밖) null — 호출부가 기존 실패 안내를 그대로 낸다.
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

  /// 싱크 잠금(L) — 다 맞춘 싱크를 오타로 망가뜨리지 않는 자물쇠.
  /// 곡에 저장되므로 재실행해도 유지된다.
  Future<void> toggleSyncLock() async {
    final song = selectedSong == null ? null : songById(selectedSong!.id);
    if (song == null) {
      _emit('먼저 곡을 선택해 주세요.');
      return;
    }
    final next = !song.syncLocked;
    await replaceSongInList(song.copyWith(syncLocked: next));
    playback.syncLockedView.value = next; // 좌상단 자물쇠 배지 즉시 갱신
    _emit(next ? '싱크 잠금 — 조절 키가 꺼졌습니다 (L로 해제)' : '싱크 잠금 해제 — 조절할 수 있습니다');
  }

  /// 잠긴 곡이면 알리고 true. 모든 싱크 조절 입구가 이 가드를 지난다.
  bool _syncLockBlocked() {
    final song = selectedSong == null ? null : songById(selectedSong!.id);
    if (song == null || !song.syncLocked) return false;
    _emit('싱크 잠금 중 — L로 해제한 뒤 조절해 주세요.');
    return true;
  }

  /// 곡별 가사 선행/지연 오프셋을 바꾼다. 음수면 가사가 먼저 나온다.
  Future<void> adjustLyricsOffset(int deltaMs) async {
    if (_syncLockBlocked()) return;
    final track = _selectedTrack();
    if (track == null) {
      _emit('먼저 곡과 반주를 선택해 주세요.');
      return;
    }
    final requested = track.lyricsOffsetMs + deltaMs;
    final applied = await _writeLyricsOffset(requested);
    // 0.2초 이동은 눈으로 못 느낀다 — 표시가 없으면 "단축키가 안 먹는다"로
    // 보인다(실사용 보고). 방향과 **실제 적용된** 누적값을 매번 알려 준다.
    final dir = deltaMs > 0 ? '늦춤' : '앞당김';
    final limit = applied == requested ? '' : ' · 한계값';
    _emit('가사 싱크 $dir — ${_formatOffsetLabel(applied)}$limit');
  }

  /// 싱크 대기(]) 토글 — 가사를 멈춰 두고 기다렸다가, 다시 누르면
  /// **기다린 시간만큼 늦춰서** 그 자리부터 이어간다. 이 판본의 간주가
  /// 원곡보다 길 때 가사가 먼저 달아나는 것을 사람 타이밍으로 잡는 도구.
  Future<void> toggleLyricsHold() async {
    if (_syncLockBlocked()) return;
    final song = selectedSong == null ? null : songById(selectedSong!.id);
    if (song == null) {
      _emit('먼저 곡을 선택해 주세요.');
      return;
    }
    if (_lyricsHoldStart == null) {
      _lyricsHoldStart = playback.position.value;
      _lyricsHoldSongId = song.id;
      playback.lyricsHold.value = true;
      _emit('싱크 대기 — 가사가 멈췄습니다. 나올 타이밍에 ]를 다시 누르세요');
      return;
    }
    final heldMs =
        (playback.position.value - _lyricsHoldStart!).inMilliseconds;
    final sameSong = _lyricsHoldSongId == song.id;
    _lyricsHoldStart = null;
    _lyricsHoldSongId = null;
    playback.lyricsHold.value = false;
    final track = _selectedTrack();
    if (!sameSong || heldMs <= 0 || track == null) {
      playback.refreshLineIndex();
      _emit('싱크 재개');
      return;
    }
    final applied = await _writeLyricsOffset(track.lyricsOffsetMs + heldMs);
    final heldLabel = (heldMs / 1000).toStringAsFixed(1);
    _emit('싱크 재개 — $heldLabel초 늦춤 반영 (${_formatOffsetLabel(applied)})');
  }

  Duration? _lyricsHoldStart;
  String? _lyricsHoldSongId;

  /// **현재 줄부터 아래만** [deltaMs]만큼 민다 — Alt+←(늦춤)/Alt+→(앞당김).
  ///
  /// 전체 오프셋과 달리 LRC 타임스탬프 자체를 고쳐 저장한다. 위 줄들은
  /// 그대로라 "밑에서 맞추면 위가 틀어지는" 문제가 없다. 같은 LRC를 쓰는
  /// 슬롯 전부에 영향이 간다는 점은 전체 오프셋과 다르니 주의.
  ///
  /// 연속입력은 **모았다가 한 번에** 적용한다 — 누를 때마다 파일을 다시
  /// 쓰고 가사를 리로드하면 화면이 깜빡이며 뒤집힌다(실사용 보고).
  /// 기준 줄은 첫 입력 순간의 줄로 고정한다(적용 후 줄이 밀려도 안 튄다).
  Future<void> adjustLyricsFromCurrentLine(int deltaMs) async {
    if (_syncLockBlocked()) return;
    final song = selectedSong == null ? null : songById(selectedSong!.id);
    if (song == null) {
      _emit('먼저 곡을 선택해 주세요.');
      return;
    }
    final synced = playback.timedLyrics.value;
    if (synced == null || synced.isEmpty) {
      _emit('싱크 가사가 있어야 줄 단위 보정이 됩니다.');
      return;
    }
    // 기준은 '아직 나오지 않은 다음 줄' — 간주에서 현재 줄(방금 부른 줄)을
    // 밀면 재생 위치 밑의 시각이 움직여 하이라이트가 널뛴다(실사용 보고).
    final anchor = _partialShiftLineIndex ??= playback.upcomingLineIndex();
    if (anchor >= (playback.timedLyrics.value?.lines.length ?? 0)) {
      _partialShiftLineIndex = null;
      _emit('이 뒤에 나올 줄이 없습니다.');
      return;
    }
    _partialShiftPendingMs += deltaMs;
    final line = anchor + 1;
    final pending = _partialShiftPendingMs;
    if (pending == 0) {
      _emit('$line번째 줄부터 — 예약 0초 (상쇄됨)');
    } else {
      final dir = pending > 0 ? '늦춤' : '앞당김';
      final amount = (pending.abs() / 1000).toStringAsFixed(1);
      _emit('$line번째 줄부터 $amount초 $dir 예약 — 입력을 멈추면 적용됩니다');
    }
    _partialShiftTimer?.cancel();
    _partialShiftTimer = Timer(
      const Duration(milliseconds: 500),
      () => unawaited(_commitPartialShift()),
    );
  }

  int _partialShiftPendingMs = 0;
  int? _partialShiftLineIndex;
  Timer? _partialShiftTimer;

  /// 모아 둔 부분 보정을 실제로 LRC에 쓴다 — 파일 쓰기·리로드는 여기 한 번.
  Future<void> _commitPartialShift() async {
    final deltaMs = _partialShiftPendingMs;
    final index = _partialShiftLineIndex;
    _partialShiftPendingMs = 0;
    _partialShiftLineIndex = null;
    _partialShiftTimer = null;
    if (_disposed || deltaMs == 0 || index == null) return;

    final song = selectedSong == null ? null : songById(selectedSong!.id);
    if (song == null) return;
    final raw = await lyricsSync.rawFor(song);
    if (raw == null) {
      _emit('가사 원문(LRC)을 읽지 못했습니다.');
      return;
    }
    final result = shiftLrcFromLine(raw, displayIndex: index, deltaMs: deltaMs);
    if (result == null) {
      _emit('밀 수 있는 줄이 없습니다.');
      return;
    }
    if (result.appliedDeltaMs == 0) {
      // 순서 보존 클램프 — 위 줄과 붙어 있어 더는 못 당긴다.
      _emit('바로 위 줄과 겹쳐서 더 당길 수 없습니다.');
      return;
    }
    // 첫 파괴적 편집 전에 원본을 남긴다(있으면 안 덮음) — 재타이밍과 같은
    // 예의. 백업이 없어 "리셋"이 불가능했던 실사용 사고의 재발 방지.
    await lyricsSync.backupLrc(song);
    _pushLyricsUndo(song.id, raw);
    final saved = await lyricsSync.save(song, result.lrc);
    if (saved == null) return;
    await replaceSongInList(saved);
    playback.timedLyrics.value = await lyricsSync.loadFor(saved);
    playback.refreshLineIndex();
    final applied = result.appliedDeltaMs;
    final dir = applied > 0 ? '늦춤' : '앞당김';
    final amount = (applied.abs() / 1000).toStringAsFixed(1);
    final limited = applied == deltaMs ? '' : ' (위 줄 직전까지만)';
    _emit('${index + 1}번째 줄부터 아래만 $amount초 $dir 적용$limited — 위 줄은 그대로');
  }

  /// 가사 편집 실행취소 스택 — 곡별 직전 LRC 원문(세션 한정, 최대 20단계).
  /// D 삭제·Alt 부분 보정·E 줄 편집이 저장 직전 상태를 쌓고, F가 되돌린다.
  final Map<String, List<String>> _lyricsUndoStack = {};
  static const int _lyricsUndoLimit = 20;

  void _pushLyricsUndo(String songId, String raw) {
    final stack = _lyricsUndoStack.putIfAbsent(songId, () => []);
    stack.add(raw);
    if (stack.length > _lyricsUndoLimit) stack.removeAt(0);
  }

  /// 가사 편집 실행취소 — 단축키 F. 방금 지운 줄·민 타이밍을 되돌린다.
  Future<void> undoLyricsEdit() async {
    if (_syncLockBlocked()) return;
    final song = selectedSong == null ? null : songById(selectedSong!.id);
    if (song == null) {
      _emit('먼저 곡을 선택해 주세요.');
      return;
    }
    final stack = _lyricsUndoStack[song.id];
    if (stack == null || stack.isEmpty) {
      _emit('되돌릴 가사 편집이 없습니다.');
      return;
    }
    final raw = stack.removeLast();
    final saved = await lyricsSync.save(song, raw);
    if (saved == null) return;
    await replaceSongInList(saved);
    playback.timedLyrics.value = await lyricsSync.loadFor(saved);
    playback.refreshLineIndex();
    _emit('가사 편집 실행취소 — 남은 ${stack.length}단계');
  }

  /// 가사를 보관된 원본(.bak)으로 복구한다 — 단축키 G(화면에서 확인 후).
  /// 복구 직전 상태는 실행취소 스택에 쌓여 F로 되돌릴 수 있다.
  Future<bool> restoreLyricsBackup() async {
    if (_syncLockBlocked()) return false;
    final song = selectedSong == null ? null : songById(selectedSong!.id);
    if (song == null) {
      _emit('먼저 곡을 선택해 주세요.');
      return false;
    }
    final backup = await lyricsSync.readBackup(song);
    if (backup == null) {
      _emit('보관된 원본(.bak)이 없습니다 — 가사를 고치면 그때 만들어집니다.');
      return false;
    }
    final current = await lyricsSync.rawFor(song);
    final saved = await lyricsSync.save(song, backup);
    if (saved == null) {
      _emit('원본을 해석하지 못했습니다.');
      return false;
    }
    if (current != null) _pushLyricsUndo(song.id, current);
    await replaceSongInList(saved);
    playback.timedLyrics.value = await lyricsSync.loadFor(saved);
    playback.refreshLineIndex();
    _emit('가사를 원본으로 복구했습니다 — 직전 상태는 F로 되돌릴 수 있어요');
    return true;
  }

  /// 현재 줄을 가사에서 지운다 — 단축키 D.
  ///
  /// 노래가 끝난 뒤에도 이어지는 환청 줄(STT가 페이드아웃에서 지어낸
  /// 가사)을 그 자리에서 지우는 용도. 지우기 전 원본을 .bak으로 남긴다.
  Future<void> deleteCurrentLyricsLine() async {
    if (_syncLockBlocked()) return;
    final song = selectedSong == null ? null : songById(selectedSong!.id);
    if (song == null) {
      _emit('먼저 곡을 선택해 주세요.');
      return;
    }
    final index = playback.lineIndex.value;

    final synced = playback.timedLyrics.value;
    if (synced != null && !synced.isEmpty) {
      final raw = await lyricsSync.rawFor(song);
      if (raw == null) {
        _emit('가사 원문(LRC)을 읽지 못했습니다.');
        return;
      }
      final result = removeLrcLine(raw, displayIndex: index);
      if (result == null) {
        _emit('지울 줄이 없습니다.');
        return;
      }
      await lyricsSync.backupLrc(song);
      _pushLyricsUndo(song.id, raw);
      final saved = await lyricsSync.save(song, result.lrc);
      if (saved == null) {
        // 마지막 남은 줄을 지우면 LRC가 비어 저장이 거부된다.
        _emit('마지막 줄은 지울 수 없습니다. 가사 제거는 곡 수정에서 해 주세요.');
        return;
      }
      await replaceSongInList(saved);
      playback.timedLyrics.value = await lyricsSync.loadFor(saved);
      playback.refreshLineIndex();
      _emit('${index + 1}번째 줄 삭제: "${result.removedText}" (원본은 .bak)');
      return;
    }

    // 일반 가사 — 표시 줄(빈 줄 제외)을 원본 줄 번호로 되돌려 지운다.
    final indexed = LyricsLineUtils.splitLinesIndexed(song.lyricsText);
    if (index < 0 || index >= indexed.length) {
      _emit('지울 줄이 없습니다.');
      return;
    }
    final sourceLines = song.lyricsText.split(RegExp(r'\r?\n'));
    final removed = sourceLines.removeAt(indexed[index].sourceIndex).trim();
    final updated = await updateSongFields(
      song.id,
      lyrics: sourceLines.join('\n'),
    );
    if (updated != null) {
      _emit('${index + 1}번째 줄 삭제: "$removed"');
    }
  }

  /// 싱크를 원래대로 되돌린다(오프셋 0) — 단축키 T.
  /// `.`/`/`로 밀고 당기다 어긋났을 때 처음부터 다시 맞추는 리셋.
  Future<bool> resetLyricsOffset() async {
    if (_syncLockBlocked()) return false;
    if (_selectedTrack() == null) {
      _emit('먼저 곡과 반주를 선택해 주세요.');
      return false;
    }
    await _writeLyricsOffset(0);
    _emit('싱크를 원래대로 되돌렸습니다.');
    return true;
  }

  /// 재생 중에 "여기가 첫 줄"을 눌러 싱크를 그 지점에 맞춘다.
  ///
  /// 싱크 가사(LRC)든 노래 구간 배분이든 같은 오프셋 하나로 처리한다 —
  /// 사용자에게는 "첫 줄을 지금으로" 하나의 동작이다.
  Future<bool> anchorLyricsToCurrentPosition() async {
    if (_syncLockBlocked()) return false;
    if (_selectedTrack() == null) {
      _emit('먼저 곡과 반주를 선택해 주세요.');
      return false;
    }
    final offset = playback.anchorOffsetForCurrentPosition();
    if (offset == null) {
      _emit('맞출 기준이 없습니다. 싱크 가사를 가져오거나 MR을 만들어 주세요.');
      return false;
    }
    if (offset.abs() > AppConstants.maxLyricsOffsetMs) {
      // 곡 한복판에서 눌렀거나 재생 전에 눌렀을 때다. 조용히 큰 값을
      // 밀어 넣으면 가사가 통째로 사라져 원인을 못 찾는다.
      _emit('첫 소절이 나오는 순간에 눌러 주세요.');
      return false;
    }

    await _writeLyricsOffset(offset);
    _emit('첫 줄을 지금 위치에 맞췄습니다 (${_formatOffsetLabel(offset)}).');
    return true;
  }

  static String _formatOffsetLabel(int ms) {
    if (ms == 0) return '동시';
    final seconds = (ms.abs() / 1000).toStringAsFixed(1);
    return ms < 0 ? '$seconds초 먼저' : '$seconds초 늦게';
  }

  /// 지금 선택된 곡·슬롯의 반주. 재생 스냅샷의 곡은 오래됐을 수 있어
  /// 목록의 최신 인스턴스를 쓴다.
  BackingTrack? _selectedTrack() {
    final snapshotSong = selectedSong;
    final slot = selectedTrackSlot;
    if (snapshotSong == null || slot == null) return null;
    final song = songs.firstWhere(
      (s) => s.id == snapshotSong.id,
      orElse: () => snapshotSong,
    );
    return song.trackForSlot(slot);
  }

  /// 실제로 적용된(한계로 잘린) 값을 돌려준다 — 호출자가 요청값과 비교해
  /// 한계 도달을 사용자에게 알릴 수 있게. 선택이 없으면 입력을 그대로 반환.
  Future<int> _writeLyricsOffset(int offsetMs) async {
    final snapshotSong = selectedSong;
    final slot = selectedTrackSlot;
    if (snapshotSong == null || slot == null) return offsetMs;
    final song = songs.firstWhere(
      (s) => s.id == snapshotSong.id,
      orElse: () => snapshotSong,
    );
    final track = song.trackForSlot(slot);
    if (track == null) return offsetMs;

    final next = offsetMs.clamp(
      -AppConstants.maxLyricsOffsetMs,
      AppConstants.maxLyricsOffsetMs,
    );
    // 같은 녹음을 쓰는 슬롯(1·2·3)에는 함께 적용된다 — 슬롯을 바꿔 불러도
    // 맞춰 둔 싱크가 유지된다. 노래방(4번)은 다른 녹음이라 자기 값만 갖는다.
    await replaceSongInList(song.withLyricsOffsetForSlot(slot, next));
    playback.applyLyricsOffset(next);
    return next;
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

  // ── 음정 코치 (녹음 채점·보정) ──────────────────────────

  /// 원곡(1번 슬롯)에서 분리한 **보컬 스템** 경로 — 채점의 기준 멜로디.
  /// 분리 서버가 꺼져 있으면 켜질 때까지 기다린다(가져오기와 같은 규약).
  Future<String?> vocalStemForSong(Song song) async {
    final original = song.trackForSlot(TrackVariant.original.preferredSlot);
    if (original == null) {
      _emit('원곡(1번 슬롯)이 있어야 채점 기준을 만들 수 있습니다.');
      return null;
    }
    final path = await repo.getBackingTrackPath(original.fileName);
    if (path == null) {
      _emit('원곡 파일을 찾을 수 없습니다.');
      return null;
    }
    if (!separatorOnline) {
      _emit('분리 서버 켜는 중… (최대 2분)');
      await ensureSeparatorOnline();
    }
    final separated = await separation.separate(path);
    if (!separated.success || separated.vocalsPath == null) {
      _emit(separated.message ?? '보컬 분리에 실패했습니다.');
      return null;
    }
    return separated.vocalsPath;
  }

  /// 녹음 당시의 총 전조(구운 키 + 사용자 키) — 채점 기준을 옮길 반음.
  int takeTranspose(Song song, RecordingTake take) {
    final slot = take.backingTrackSlot;
    final baked = slot == null
        ? 0
        : (song.trackForSlot(slot)?.bakedSemitones ?? 0);
    return baked + take.pitchSemitones;
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

  /// 분리 서버 기동 명령(빈 문자열이면 자동 기동 없음).
  Future<String> separatorStartCommand() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_kSeparatorCmdKey) ?? '').trim();
  }

  Future<void> setSeparatorStartCommand(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSeparatorCmdKey, path.trim());
  }

  /// 기동 명령이 등록돼 있고 실제 파일이 있는가.
  Future<bool> canAutoStartSeparator() async {
    final cmd = await separatorStartCommand();
    if (cmd.isEmpty) return false;
    return File(cmd).exists();
  }

  /// 앱이 직접 띄운 로컬 서버들(분리·STT). 앱이 수명을 관리한다 —
  /// 콘솔창 없이 백그라운드로 켜고, 앱이 닫힐 때 함께 끈다(사용자 규약).
  /// 사용자가 밖에서 직접 켠 서버는 여기 없으므로 건드리지 않는다.
  final List<Process> _managedServers = [];

  /// .bat 서버를 콘솔창 없이 켠다. normal 모드는 stdio를 파이프로 물려
  /// CREATE_NO_WINDOW로 뜬다(detached는 창 관리도 수명 관리도 안 된다).
  Future<bool> _startManagedServer(String cmd) async {
    try {
      final proc = await Process.start(
        'cmd.exe',
        ['/c', cmd],
        workingDirectory: File(cmd).parent.path,
      );
      // 파이프가 가득 차면 서버가 멈춘다 — 출력은 흘려보낸다.
      unawaited(proc.stdout.drain<void>());
      unawaited(proc.stderr.drain<void>());
      _managedServers.add(proc);
      return true;
    } catch (e) {
      debugPrint('서버 기동 실패($cmd): $e');
      return false;
    }
  }

  /// 앱이 띄운 서버를 트리째 끝낸다(cmd 아래 python까지 — /T).
  /// 앱 종료 경로(창 닫기·dispose)에서 부른다. 여러 번 불려도 안전하다.
  void stopManagedServers() {
    for (final proc in _managedServers) {
      try {
        Process.runSync('taskkill', ['/PID', '${proc.pid}', '/T', '/F']);
      } catch (e) {
        debugPrint('서버 종료 실패(pid ${proc.pid}): $e');
      }
    }
    _managedServers.clear();
  }

  bool _separatorStarting = false;

  /// 분리 서버가 꺼져 있으면 등록된 명령으로 켜고 온라인까지 기다린다.
  ///
  /// demucs 모델 로드가 있어 첫 기동은 오래 걸린다 — 넉넉히 기다린다.
  /// 이미 켜는 중이면 프로세스를 또 띄우지 않고 기다리기만 한다.
  Future<bool> ensureSeparatorOnline({
    Duration timeout = const Duration(seconds: 120),
  }) async {
    await _refreshSeparatorStatus();
    if (separatorOnline) return true;
    final cmd = await separatorStartCommand();
    if (cmd.isEmpty || !await File(cmd).exists()) return false;

    if (!_separatorStarting) {
      _separatorStarting = true;
      if (!await _startManagedServer(cmd)) {
        _separatorStarting = false;
        return false;
      }
    }

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (_disposed) break;
      await _refreshSeparatorStatus();
      if (separatorOnline) break;
    }
    _separatorStarting = false;
    return separatorOnline;
  }

  bool _sttStarting = false;

  /// STT 서버 기동 명령. 등록이 없으면 SVIL 표준 경로를 써 본다.
  Future<String> _sttStartCommand() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = (prefs.getString(_kSttCmdKey) ?? '').trim();
    if (saved.isNotEmpty) return saved;
    const fallback = r'C:\Projects\svil-ai-work\stt_system\start.bat';
    return await File(fallback).exists() ? fallback : '';
  }

  /// STT 서버가 꺼져 있으면 켜고 온라인까지 기다린다 — 분리 서버와 같은
  /// 규약. 창을 닫아 서버가 죽어 있어도 받아쓰기가 스스로 살린다
  /// (실사용 보고: "받아쓰기 작동 안 함" = 서버 꺼짐).
  Future<bool> ensureSttOnline({
    Duration timeout = const Duration(seconds: 90),
  }) async {
    if (await sttLyrics.isOnline()) return true;
    final cmd = await _sttStartCommand();
    if (cmd.isEmpty || !await File(cmd).exists()) return false;

    if (!_sttStarting) {
      _sttStarting = true;
      if (!await _startManagedServer(cmd)) {
        _sttStarting = false;
        return false;
      }
    }

    final deadline = DateTime.now().add(timeout);
    var online = false;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (_disposed) break;
      online = await sttLyrics.isOnline();
      if (online) break;
    }
    _sttStarting = false;
    return online;
  }

  Future<void> _refreshSeparatorStatus() async {
    final status = await separation.status();
    if (_disposed) return;
    separatorStatusLabel = status.label;
    separatorOnline = status.online;
    _notify();
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
        !separatorOnline &&
        !await canAutoStartSeparator()) {
      // 자동 기동이 가능하면 거절하지 않는다 — 파이프라인이 켜고 기다린다.
      return const ImportEnqueueOutcome.error(
        'separator_offline',
        '분리 서버가 꺼져 있어 MR을 만들 수 없습니다. 서버를 켜거나 '
        '설정에 시작 명령을 등록해 주세요.',
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
      if (!separatorOnline) {
        // 서버가 꺼져 있으면 여기서 켜고 기다린다 — 큐 작업이라 블로킹해도
        // 진행 표시가 사용자를 안심시킨다. 실패하면 아래 분리 실패 폴백
        // (원곡만 등록)이 그대로 받아 준다.
        onProgress(const JobProgress(label: '분리 서버 켜는 중 (최대 2분)'));
        await ensureSeparatorOnline();
      }
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
        instrumentalSemitones: plan.instrumentalSemitones,
        pitchSemitones: plan.pitchSemitones,
      ),
      pitchLabel: plan.wantsPitch
          ? '키조절 ${formatKeyLabel(plan.pitchSemitones!)}'
          : null,
      instrumentalLabel: plan.wantsPitchedInstrumental
          ? 'MR ${formatKeyLabel(plan.instrumentalSemitones)}'
          : null,
    );

    final slotPaths = <int, String>{};
    final slotLabels = <int, String>{};
    final slotBaked = <int, int>{};
    int? mrSlot;
    PlannedTrack? pitchPlanned;
    PlannedTrack? mrPitchPlanned;
    for (final track in planned.tracks) {
      switch (track.variant) {
        case TrackVariant.original:
          slotPaths[track.slot] = originalPath;
        case TrackVariant.mr:
          // 등록 시점의 파일은 분리 결과 그대로다. 키를 구워야 하는
          // MR(남자키 프리셋)은 정직하게 0으로 등록하고 2단계에서
          // 렌더가 성공하면 그때 라벨·구운 키를 바꾼다 — 렌더가 실패해도
          // "MR"이라는 라벨과 파일이 일치한다.
          slotPaths[track.slot] = instrumentalPath ?? originalPath;
          mrSlot = track.slot;
          if (track.bakedSemitones != 0) {
            mrPitchPlanned = track;
            slotLabels[track.slot] = TrackVariant.mr.label;
            slotBaked[track.slot] = 0;
            continue;
          }
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

    // MR 슬롯 자체의 키조절(남자키 프리셋) — 반드시 위 키조절 슬롯 **다음**에
    // 한다. 둘 다 원본(무변조) MR을 기준으로 구워야 하는데, 이 단계가 슬롯
    // 파일을 키조절본으로 갈아끼우기 때문이다.
    if (mrPitchPlanned != null && mrSlot != null) {
      onProgress(
        JobProgress(
          ratio: 1,
          label: 'MR ${formatKeyLabel(mrPitchPlanned.bakedSemitones)} 만드는 중',
        ),
      );
      final rendered = await _renderPitchSlot(
        song: song,
        baseSlot: mrSlot,
        targetSlot: mrSlot,
        semitones: mrPitchPlanned.bakedSemitones,
        label: mrPitchPlanned.label,
      );
      if (rendered != null) {
        song = rendered;
      } else {
        pitchNote += ' · MR 키조절 실패(원키 MR로 남김)';
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

    // 링크를 곡에 남긴다 — '가사 다시 생성'이 자막을 다시 조회할 수 있게.
    song = song.copyWith(sourceUrl: job.url);
    await replaceSongInList(song);

    // 가사까지 한 흐름에서 붙인다. 실패해도 곡 자체는 남긴다.
    // 규약(사용자 지정): LRCLIB → 유튜브 수동 자막 → AI 받아쓰기 순 폴백.
    var lyricsNote = '';
    if (job.fetchLyrics) {
      onProgress(const JobProgress(label: '가사 찾는 중 (LRCLIB)'));
      final outcome = await lyricsSync.fetchFor(
        song,
        duration: metadata.duration,
      );
      if (outcome.success && outcome.song != null) {
        song = outcome.song!;
        await replaceSongInList(song);
        lyricsNote = ' · 가사 포함';
        onProgress(const JobProgress(label: '가사 싱크 맞추는 중'));
        lyricsNote += await _autoAlignNoteFor(song);
      } else {
        // 업로더 수동 자막 — 타이밍까지 있는 정답이라 받아쓰기보다 우선.
        onProgress(const JobProgress(label: '유튜브 자막 확인 중'));
        final subs = await youtubeImport.fetchManualSubtitles(job.url);
        var attached = false;
        if (subs != null && subs.isNotEmpty) {
          final lrc = lrcFromSttSegments(
            subs,
            title: song.title,
            artist: song.artist,
            duration: metadata.duration,
          );
          final withSubs = await attachLrc(songId: song.id, content: lrc);
          if (withSubs != null) {
            song = withSubs;
            lyricsNote = ' · 유튜브 자막 가사(${subs.length}줄)';
            attached = true;
          }
        }
        if (!attached) {
          onProgress(
            const JobProgress(label: '가사가 없어 AI 받아쓰기 중 (수십 초)'),
          );
          final stt = await generateSttLyrics(
            songId: song.id,
            duration: metadata.duration,
          );
          if (stt) {
            song = songById(song.id) ?? song;
            lyricsNote = ' · 받아쓴 가사 포함';
          } else {
            lyricsNote = ' · 가사는 찾지 못함(받아쓰기도 실패)';
          }
        }
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
    var updated = await attachTrackToSong(
      songId: songId,
      slot: slot,
      sourcePath: audioPath,
      label: job.trackLabel ?? TrackVariant.karaoke.label,
    );
    if (updated == null) {
      _failJob(job, '반주를 넣지 못했습니다.');
      return;
    }

    // 키를 구워 달라는 요청(노래방 −2/−5/−7 등)이면 같은 슬롯에 렌더로
    // 갈아끼운다. 실패해도 원키 반주는 남는다 — 라벨이 파일과 일치한다.
    var keyNote = '';
    if (job.trackSemitones != 0) {
      onProgress(
        JobProgress(
          ratio: 1,
          label: '${formatKeyLabel(job.trackSemitones)} 반주 만드는 중',
        ),
      );
      final baseLabel = job.trackLabel ?? TrackVariant.karaoke.label;
      final rendered = await _renderPitchSlot(
        song: updated,
        baseSlot: slot,
        targetSlot: slot,
        semitones: job.trackSemitones,
        label: '$baseLabel ${formatKeyLabel(job.trackSemitones)}',
      );
      if (rendered != null) {
        updated = rendered;
      } else {
        keyNote = ' · 키조절 실패(원키로 남김)';
      }
    }

    final finished = importJobs.jobById(job.id);
    if (finished == null) return;
    final label = updated.trackForSlot(slot)?.label ?? '반주';
    importJobs.update(
      finished.copyWith(
        status: ImportJobStatus.done,
        statusDetail: '슬롯 $slot에 "$label"을(를) 넣었습니다.$keyNote',
        songId: updated.id,
        ratio: 1,
      ),
    );
    _emit('"${updated.title}" 슬롯 $slot에 $label 추가$keyNote');
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
  /// songs.json 저장 직렬화 사슬. 겹치면 완료 순서가 뒤바뀌어 늦게 끝난
  /// **낡은** 스냅샷이 디스크에 남을 수 있다 — `.`/`/` 연타(실시간 싱크
  /// 조절)가 이 경로를 초당 여러 번 태우면서 실제 위험이 됐다.
  Future<void> _songsSaveChain = Future.value();

  /// 곡 목록의 저장 순서를 통째로 바꾼다(드래그 재정렬).
  ///
  /// 같은 곡 집합일 때만 받는다 — 재정렬 계산 중에 다른 경로(가져오기 완료
  /// 등)가 목록을 바꿨다면 낡은 순서로 덮어쓰지 않고 버린다.
  Future<void> setSongOrder(List<Song> ordered) async {
    if (_disposed) return;
    if (ordered.length != songs.length) return;
    final currentIds = {for (final s in songs) s.id};
    if (!ordered.every((s) => currentIds.contains(s.id))) return;
    songs = List.unmodifiable(ordered);
    _notify();
    _songsSaveChain = _songsSaveChain
        .catchError((_) {})
        .then((_) => repo.saveSongs(songs));
    await _songsSaveChain;
  }

  Future<void> replaceSongInList(Song song) async {
    if (_disposed) return;
    songs = songs
        .map((s) => s.id == song.id ? song : s)
        .toList(growable: false);
    _notify();
    // 저장이 돌 때 최신 목록을 읽도록 사슬 안에서 songs를 다시 참조한다 —
    // 연달아 불리면 마지막 저장이 언제나 최신 상태를 쓴다.
    // 앞선 실패는 삼킨다(그 오류는 그 호출자가 이미 받았다) — 안 그러면
    // 한 번의 디스크 오류가 사슬을 영영 끊는다.
    _songsSaveChain = _songsSaveChain
        .catchError((_) {})
        .then((_) => repo.saveSongs(songs));
    await _songsSaveChain;
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
    int semitones = 0,
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
      trackSemitones: clampSemitones(semitones),
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

  /// 제목·가수·가사·폴더만 고친다. 반주 파일은 건드리지 않는다.
  Future<Song?> updateSongFields(
    String songId, {
    String? title,
    String? artist,
    String? lyrics,
    String? folder,
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
      applyFolder: folder != null,
      folder: folder ?? '',
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

  /// 활성 예약 큐를 바꾼다(탭). 저장소도 같이 갈아타 이후의 예약·저장이
  /// 전부 새 슬롯으로 간다.
  Future<void> switchQueueSlot(int slot) async {
    final next = slot.clamp(0, queueSlots.length - 1);
    if (next == activeQueueSlot) return;
    activeQueueSlot = next;
    await repo.saveActiveQueueSlot(next);
    _notify();
  }

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
