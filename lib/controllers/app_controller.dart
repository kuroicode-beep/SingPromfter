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

import '../models/mr_source_mode.dart';
import '../models/prompter_display_mode.dart';
import '../models/prompter_settings.dart';
import '../models/queue_item.dart';
import '../models/song.dart';
import '../models/song_draft.dart';
import '../models/track_levels.dart';
import '../repository/song_repository.dart';
import '../services/level_analysis_service.dart';
import '../services/lyrics_sync_service.dart';
import '../services/pitch_variant_service.dart';
import '../services/process/external_tool_locator.dart';
import '../services/process/process_runner.dart';
import '../services/process/tool_progress_parsers.dart';
import '../services/prompter_audio_service.dart';
import '../services/song_library_service.dart';
import '../services/song_list_bootstrap_service.dart';
import '../services/song_queue_service.dart';
import '../services/vocal_separation_client.dart';
import '../services/youtube_import_service.dart';
import '../utils/key_label.dart';
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
      pitchVariantResolver: _resolvePitchVariant,
      levelsLoader: loadTrackLevels,
      onPracticeSessionEnded: (snapshot, played) =>
          onPracticeSessionEnded?.call(snapshot, played),
    )..init();
    importJobs = ImportJobController(runner: _runImportJob);
  }

  @override
  void dispose() {
    _disposed = true;
    _statusRefreshTimer?.cancel();
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
    await audio.setPlaybackRate(settings.playbackRate);
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
  Future<String?> _resolvePitchVariant(
    Song song,
    int slot,
    int semitones,
  ) async {
    final track = song.trackForSlot(slot);
    if (track == null) return null;
    final sourcePath = await repo.getBackingTrackPath(track.fileName);
    if (sourcePath == null) return null;

    final cached = await pitchVariants.cachedPath(
      sourceFileName: track.fileName,
      semitones: semitones,
    );
    if (cached != null) return cached;

    _emit('${formatKeyLabel(semitones)} 반주를 준비하는 중...');
    final result = await pitchVariants.render(
      sourcePath: sourcePath,
      sourceFileName: track.fileName,
      semitones: semitones,
      total: playback.snapshot.duration,
    );
    if (!result.success) {
      _emit(result.message ?? '키 변경에 실패했습니다.');
      return null;
    }
    return result.path;
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
  Future<bool> setPitch(String songId, int semitones, {int? slot}) async {
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
      await playback.prepareAudioForSelection();
    }
    _emit('키: ${formatKeyLabel(next)}');
    return true;
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

    final next = (track.lyricsOffsetMs + deltaMs).clamp(-3000, 3000);
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
    final job = importJobs.enqueue(
      url: url,
      mode: mode,
      id: const Uuid().v4(),
      fetchLyrics: fetchLyrics,
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
      // 유튜브 측 변경으로 오래된 yt-dlp가 깨지는 일이 잦다 — 힌트를 함께 준다.
      final message = result.message ?? '가져오기에 실패했습니다.';
      _failJob(
        job,
        '$message 오래된 yt-dlp가 원인일 수 있어요 — 설정에서 업데이트(-U)를 실행해 보세요.',
      );
      await youtubeImport.cleanupJob(job.id);
      return;
    }

    var audioPath = result.audioPath!;
    if (job.mode == MrSourceMode.aiSeparate) {
      onProgress(const JobProgress(label: 'AI 보컬 분리 중 (수십 초 걸립니다)'));
      final separated = await separation.separate(audioPath);
      if (!separated.success || separated.instrumentalPath == null) {
        _failJob(job, separated.message ?? 'AI 보컬 분리에 실패했습니다.');
        await youtubeImport.cleanupJob(job.id);
        return;
      }
      audioPath = separated.instrumentalPath!;
    }

    onProgress(const JobProgress(ratio: 1, label: '곡으로 등록 중'));
    var song = await _registerImportedSong(
      metadata: metadata,
      audioPath: audioPath,
    );
    await youtubeImport.cleanupJob(job.id);

    if (song == null) {
      _failJob(job, '곡 등록에 실패했습니다.');
      return;
    }

    // 첫 무대 진입 때 EQ가 바로 뜨도록 등록 직후 백그라운드로 선분석한다.
    unawaited(loadTrackLevels(song, 1));

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
      } else {
        lyricsNote = ' · 가사는 찾지 못함';
      }
    }

    final finished = importJobs.jobById(job.id);
    if (finished == null) return;
    importJobs.update(
      finished.copyWith(
        status: ImportJobStatus.done,
        statusDetail: '재생목록에 추가했습니다$lyricsNote.',
        songId: song.id,
        ratio: 1,
      ),
    );
    _emit('"${song.title}" 추가 완료$lyricsNote');
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

  /// 받은 오디오를 반주 1번 슬롯으로 하는 곡을 만든다.
  /// 가사는 이어지는 단계에서 채운다. 실패하면 null.
  Future<Song?> _registerImportedSong({
    required YoutubeMetadata metadata,
    required String audioPath,
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
        trackPaths: {1: audioPath},
        trackLabels: {1: 'MR1'},
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
