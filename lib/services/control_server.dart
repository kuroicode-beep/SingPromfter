// file: lib/services/control_server.dart
//
// 로컬 제어 API — 127.0.0.1:8772 루프백 전용 HTTP 서버.
//
// MCP(singprompter_mcp.py)가 이 API를 통해 곡 추가·키 조절·큐·재생을
// 프롬프트만으로 조작한다. 루프백에만 바인딩하므로 외부에서 접근할 수 없다.
//
// 저작권 게이트: 최초 1회 확인(ack)은 앱 화면에서만 세팅할 수 있고,
// 이 API에는 ack를 세팅하는 엔드포인트가 없다(우회 불가).
//
// 스레딩: HttpServer 콜백은 메인 isolate 이벤트 루프에서 실행되므로
// AppController를 직접 호출해도 안전하다(락 불필요).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../constants/app_version.dart';
import '../controllers/app_controller.dart';
import '../controllers/compose_job_controller.dart';
import '../controllers/import_job_controller.dart';
import '../models/composition.dart';
import '../models/import_plan.dart';
import '../models/mr_source_mode.dart';
import '../models/recording_take.dart';
import '../models/song.dart';
import 'app_capture.dart';
import 'recording_library_service.dart';

/// 라우팅 결과 — 상태코드와 JSON 본문.
class ControlResponse {
  final int status;
  final Map<String, dynamic> body;

  const ControlResponse(this.status, this.body);

  static ControlResponse ok([Map<String, dynamic> extra = const {}]) =>
      ControlResponse(200, {'ok': true, ...extra});

  static ControlResponse error(int status, String code, String message) =>
      ControlResponse(status, {
        'ok': false,
        'error': {'code': code, 'message': message},
      });

  static ControlResponse notFound() =>
      error(404, 'not_found', '해당 경로가 없습니다.');
}

/// 순수 라우터 — HttpServer 없이 dispatch만 테스트할 수 있다.
class ControlRouter {
  final AppController app;

  const ControlRouter(this.app);

  Future<ControlResponse> dispatch(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String> query = const {},
  }) async {
    try {
      return await _dispatch(method, path, body ?? const {}, query);
    } catch (e) {
      debugPrint('제어 API 처리 실패($method $path): $e');
      return ControlResponse.error(500, 'internal', '처리 중 오류: $e');
    }
  }

  Future<ControlResponse> _dispatch(
    String method,
    String path,
    Map<String, dynamic> body,
    Map<String, String> query,
  ) async {
    final parts = path
        .split('/')
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    // 모든 경로는 /api/... 형태다.
    if (parts.isEmpty || parts.first != 'api') return ControlResponse.notFound();
    final rest = parts.sublist(1);

    switch ((method, rest)) {
      // ── 상태 ──
      case ('GET', ['state']):
        return ControlResponse.ok(_stateJson());

      // ── 곡 ──
      case ('GET', ['songs']):
        final q = (query['query'] ?? '').trim().toLowerCase();
        final items = app.songs
            .where(
              (s) =>
                  q.isEmpty ||
                  s.title.toLowerCase().contains(q) ||
                  s.artist.toLowerCase().contains(q),
            )
            .map(_songJson)
            .toList(growable: false);
        return ControlResponse.ok({'songs': items});

      case ('GET', ['songs', final String id]):
        final song = app.songById(id);
        if (song == null) return _songNotFound();
        return ControlResponse.ok({
          'song': _songJson(song, includeLyrics: true),
        });

      case ('POST', ['songs']):
        final url = (body['url'] as String?)?.trim() ?? '';
        final fetchLyrics = body['fetchLyrics'] as bool? ?? true;
        // 링크만 오면(모드·계획 둘 다 미지정) "부를 수 있는 곡"이 기본이다 —
        // 원곡/MR/MR−2키 3슬롯 + 가사 + 싱크 보정까지. 어느 하나라도 명시한
        // 호출은 명시한 대로 동작한다(기존 자동화와의 호환).
        final rawMode = body['mode'] as String?;
        final rawPlan = body['plan'];
        final bareLink = rawMode == null && rawPlan == null;
        var mode = bareLink
            ? MrSourceMode.aiSeparate
            : MrSourceModeInfo.fromStorage(rawMode);
        var plan = rawPlan is Map<String, dynamic>
            ? ImportPlan.fromJson(rawPlan)
            : (bareLink ? const ImportPlan.full() : const ImportPlan.single());
        String? note;
        if (bareLink && !app.separatorOnline) {
          // 30초 주기 표시가 낡았을 수 있다 — 거절하기 전에 한 번은 두드린다.
          await app.refreshToolAvailability();
        }
        if (bareLink &&
            !app.separatorOnline &&
            !await app.canAutoStartSeparator()) {
          // 서버가 꺼져 있고 자동 기동도 불가능하면, 거절하는 대신 원곡만
          // 남긴다 — "링크만 주면 된다"는 계약이 서버 상태에 따라 깨지지
          // 않게. 자동 기동이 가능하면 파이프라인이 알아서 켠다.
          mode = MrSourceMode.asIs;
          plan = const ImportPlan(makeOriginal: true, makeInstrumental: false);
          note = '분리 서버가 꺼져 있어 원곡만 등록합니다. '
              '서버를 켠 뒤 [+반주]로 MR을 추가해 주세요.';
        }
        final outcome = await app.enqueueImport(
          url,
          mode,
          fetchLyrics: fetchLyrics,
          plan: plan,
        );
        if (!outcome.ok) {
          final status = outcome.errorCode == 'notice_not_acked' ? 409 : 422;
          return ControlResponse.error(
            status,
            outcome.errorCode!,
            outcome.message ?? '가져오기를 시작하지 못했습니다.',
          );
        }
        return ControlResponse.ok({'jobId': outcome.jobId, 'note': ?note});

      case ('PATCH', ['songs', final String id]):
        final updated = await app.updateSongFields(
          id,
          title: body['title'] as String?,
          artist: body['artist'] as String?,
          lyrics: body['lyrics'] as String?,
          folder: body['folder'] as String?,
        );
        if (updated == null) {
          return ControlResponse.error(
            422,
            'edit_failed',
            '곡을 찾을 수 없거나 같은 제목이 이미 있습니다.',
          );
        }
        return ControlResponse.ok({'song': _songJson(updated)});

      case ('DELETE', ['songs', final String id]):
        final removed = await app.removeSong(id);
        if (!removed) return _songNotFound();
        return ControlResponse.ok();

      case ('POST', ['songs', final String id, 'lyrics', 'fetch']):
        final outcome = await app.fetchSyncedLyricsFor(songId: id);
        return ControlResponse.ok({
          'found': outcome.success,
          'message': outcome.message,
        });

      // LRC 원문을 직접 붙인다 — LRCLIB에 없는 곡(로컬 전사 등)의 입구.
      case ('POST', ['songs', final String id, 'lyrics', 'lrc']):
        final content = body['content'] as String?;
        if (content == null || content.trim().isEmpty) {
          return ControlResponse.error(
            422,
            'missing_content',
            'content(LRC 원문, [mm:ss.xx] 형식)가 필요합니다.',
          );
        }
        final attached = await app.attachLrc(songId: id, content: content);
        if (attached == null) {
          return ControlResponse.error(
            422,
            'lrc_invalid',
            '곡을 찾을 수 없거나 LRC를 해석하지 못했습니다.',
          );
        }
        return ControlResponse.ok({'song': _songJson(attached)});

      // 가사 다시 생성 — 정밀 파이프라인(자막→보컬 스템 받아쓰기→환청 정리).
      // 분리·전사가 겹치면 수 분 걸린다. MCP·배치 정리의 입구.
      case ('POST', ['songs', final String id, 'lyrics', 'regenerate']):
        if (app.songById(id) == null) return _songNotFound();
        final ok = await app.regenerateLyrics(
          songId: id,
          useVocalStem: body['useVocalStem'] as bool? ?? true,
          useDeepSeek: body['useDeepSeek'] as bool? ?? true,
          useYoutubeSubs: body['useYoutubeSubs'] as bool? ?? true,
          referenceLyrics: body['referenceLyrics'] as String?,
        );
        if (!ok) {
          return ControlResponse.error(
            422,
            'regenerate_failed',
            '가사를 다시 만들지 못했습니다. 앱 하단 메시지를 확인해 주세요.',
          );
        }
        final regenerated = app.songById(id);
        return ControlResponse.ok({
          'song': regenerated == null ? null : _songJson(regenerated),
        });

      // 원곡·MR을 비교해 가사 싱크를 맞춘다. 몇 초 걸린다.
      case ('POST', ['songs', final String id, 'lyrics', 'align']):
        if (app.songById(id) == null) {
          return ControlResponse.error(404, 'song_not_found', '곡을 찾을 수 없습니다.');
        }
        final aligned = await app.autoAlignLyrics(songId: id);
        if (!aligned) {
          return ControlResponse.error(
            422,
            'align_failed',
            '맞출 지점을 찾지 못했습니다. 원곡·MR·싱크 가사가 모두 필요합니다.',
          );
        }
        final song = app.songById(id);
        return ControlResponse.ok({
          'lyricsOffsetMs':
              song?.backingTracks.firstOrNull?.lyricsOffsetMs ?? 0,
        });

      case ('POST', ['songs', final String id, 'pitch']):
        final semitones = (body['semitones'] as num?)?.toInt();
        if (semitones == null) {
          return ControlResponse.error(
            422,
            'missing_semitones',
            'semitones(정수, 원곡 대비 반음)가 필요합니다.',
          );
        }
        final slot = (body['slot'] as num?)?.toInt();
        final applied = await app.setPitch(id, semitones, slot: slot);
        if (!applied) {
          return ControlResponse.error(
            422,
            'pitch_failed',
            '곡이 없거나 반주 슬롯을 찾을 수 없습니다.',
          );
        }
        return ControlResponse.ok();

      // ── 반주 슬롯 ──
      case ('POST', ['songs', final String id, 'tracks']):
        final url = (body['url'] as String?)?.trim() ?? '';
        final mode = MrSourceModeInfo.fromStorage(body['mode'] as String?);
        final outcome = await app.enqueueTrackImport(
          songId: id,
          url: url,
          mode: mode,
          slot: (body['slot'] as num?)?.toInt(),
          label: body['label'] as String?,
        );
        if (!outcome.ok) {
          final status = switch (outcome.errorCode) {
            'song_not_found' => 404,
            'notice_not_acked' => 409,
            'no_free_slot' => 409,
            _ => 422,
          };
          return ControlResponse.error(
            status,
            outcome.errorCode!,
            outcome.message ?? '반주를 가져오지 못했습니다.',
          );
        }
        return ControlResponse.ok({'jobId': outcome.jobId});

      case ('DELETE', ['songs', final String id, 'tracks', final String s]):
        final slot = int.tryParse(s);
        if (slot == null) {
          return ControlResponse.error(422, 'bad_slot', '슬롯 번호가 잘못됐습니다.');
        }
        final updated = await app.removeTrackFromSong(
          songId: id,
          slot: slot,
        );
        if (updated == null) {
          return ControlResponse.error(
            404,
            'track_not_found',
            '해당 슬롯에 반주가 없습니다.',
          );
        }
        return ControlResponse.ok({'song': _songJson(updated)});

      // ── 예약 큐 ──
      case ('GET', ['queue']):
        return ControlResponse.ok({
          'items': [
            for (var i = 0; i < app.queue.length; i++)
              {
                'index': i,
                'songId': app.queue[i].songId,
                'title': app.songById(app.queue[i].songId)?.title ?? '',
              },
          ],
        });

      case ('POST', ['queue']):
        final song = app.songById((body['songId'] as String?) ?? '');
        if (song == null) return _songNotFound();
        await app.reserveSong(song);
        return ControlResponse.ok({'queueLength': app.queue.length});

      case ('DELETE', ['queue', final String index]):
        final i = int.tryParse(index);
        if (i == null || i < 0 || i >= app.queue.length) {
          return ControlResponse.error(422, 'bad_index', '큐 인덱스가 잘못됐습니다.');
        }
        await app.removeQueueItem(i);
        return ControlResponse.ok();

      case ('POST', ['queue', 'clear']):
        await app.clearQueue();
        return ControlResponse.ok();

      case ('POST', ['queue', 'reorder']):
        final from = (body['from'] as num?)?.toInt();
        final to = (body['to'] as num?)?.toInt();
        if (from == null || to == null) {
          return ControlResponse.error(422, 'bad_index', 'from/to가 필요합니다.');
        }
        await app.reorderQueue(from, to);
        return ControlResponse.ok();

      // ── 재생 ──
      case ('POST', ['screenshot']):
        final path = (body['path'] as String?)?.trim() ?? '';
        if (path.isEmpty) {
          return ControlResponse.error(422, 'bad_path', 'path가 필요합니다.');
        }
        final saved = await captureAppScreenshot(path);
        if (saved == null) {
          return ControlResponse.error(
            500,
            'capture_failed',
            '앱 화면 캡처에 실패했습니다.',
          );
        }
        return ControlResponse.ok({'path': saved});

      case ('POST', ['view']):
        final name = (body['name'] as String?)?.trim() ?? '';
        final handled = app.onNavigate?.call(name) ?? false;
        if (!handled) {
          return ControlResponse.error(
            422,
            'bad_view',
            'name은 home/search/favorites/training/recordings/jobs/'
                'settings/stage/back 중 하나여야 합니다.',
          );
        }
        return ControlResponse.ok({'view': name});

      case ('POST', ['playback', 'select']):
        final song = app.songById((body['songId'] as String?) ?? '');
        if (song == null) return _songNotFound();
        final slot = (body['slot'] as num?)?.toInt();
        await app.playback.loadSong(song, preferredSlot: slot);
        return ControlResponse.ok();

      case ('POST', ['playback', 'play']):
        await app.playback.play();
        return ControlResponse.ok({'playing': app.playback.snapshot.playing});

      case ('POST', ['playback', 'pause']):
        await app.playback.pause();
        return ControlResponse.ok({'playing': app.playback.snapshot.playing});

      case ('POST', ['playback', 'toggle']):
        await app.playback.togglePlayPause();
        return ControlResponse.ok({'playing': app.playback.snapshot.playing});

      case ('POST', ['playback', 'stop']):
        await app.playback.stop();
        return ControlResponse.ok();

      case ('POST', ['playback', 'restart']):
        await app.playback.restart();
        return ControlResponse.ok();

      case ('POST', ['playback', 'seek']):
        final ms = (body['positionMs'] as num?)?.toInt();
        if (ms == null || ms < 0) {
          return ControlResponse.error(
            422,
            'bad_position',
            'positionMs(0 이상 정수)가 필요합니다.',
          );
        }
        await app.playback.seek(Duration(milliseconds: ms));
        return ControlResponse.ok();

      case ('POST', ['playback', 'volume']):
        final value = (body['value'] as num?)?.toDouble();
        if (value == null || value < 0 || value > 1) {
          return ControlResponse.error(
            422,
            'bad_value',
            'value(0.0~1.0)가 필요합니다.',
          );
        }
        await app.updateSettings(app.settings.copyWith(volume: value));
        return ControlResponse.ok();

      // 배속이 아니라 **템포**다. 음정을 보존하는 오프라인 렌더로 처리하므로
      // 처음 쓰는 값은 렌더 시간만큼 걸린다. 이름과 0.5~1.5 계약은 그대로 둔다.
      case ('POST', ['playback', 'rate']):
        final value = (body['value'] as num?)?.toDouble();
        if (value == null || value < 0.5 || value > 1.5) {
          return ControlResponse.error(
            422,
            'bad_value',
            'value(0.5~1.5)가 필요합니다.',
          );
        }
        final tempoSong = app.selectedSong;
        final tempoSlot = app.selectedTrackSlot;
        if (tempoSong == null || tempoSlot == null) {
          return ControlResponse.error(
            409,
            'no_selection',
            '먼저 곡과 반주를 선택해 주세요.',
          );
        }
        await app.setTempo(
          tempoSong.id,
          value,
          slot: tempoSlot,
          keepPosition: true,
        );
        return ControlResponse.ok();

      // ── 가져오기 작업 ──
      case ('GET', ['jobs']):
        return ControlResponse.ok({
          'jobs': app.importJobs.jobs.map(_jobJson).toList(growable: false),
        });

      case ('POST', ['jobs', final String id, 'cancel']):
        app.importJobs.cancel(id);
        return ControlResponse.ok();

      case ('POST', ['jobs', final String id, 'retry']):
        app.importJobs.retry(id);
        return ControlResponse.ok();

      case ('POST', ['jobs', 'clear-finished']):
        app.importJobs.clearFinished();
        return ControlResponse.ok();

      // ── 작곡 (v3.0.0, 로컬AI 게이트는 AppController가 검사) ──
      case ('GET', ['compose']):
        return ControlResponse.ok({
          'compositions': app.composeLibrary.items
              .map(_compositionJson)
              .toList(growable: false),
        });

      case ('POST', ['compose']):
        final request = ComposeRequest(
          title: (body['title'] as String?)?.trim() ?? '',
          mode: ComposeModeInfo.fromStorage(body['mode'] as String?),
          // API는 최종 프롬프트를 받는다 — 다듬기는 호출자(에이전트) 몫.
          stylePromptEn: (body['prompt'] as String?)?.trim() ?? '',
          lyrics: (body['lyrics'] as String?)?.trim() ?? '',
          vocalType: (body['vocalType'] as String?)?.trim() ?? '',
          genre: (body['genre'] as String?)?.trim() ?? '',
          bpm: (body['bpm'] as num?)?.toInt(),
          durationSec: (body['durationSec'] as num?)?.toInt() ?? 210,
          seed: (body['seed'] as num?)?.toInt() ?? -1,
        );
        final outcome = await app.enqueueCompose(request);
        if (!outcome.ok) {
          final status = switch (outcome.errorCode) {
            'local_ai_disabled' => 403,
            'empty_prompt' => 422,
            _ => 503,
          };
          return ControlResponse.error(
            status,
            outcome.errorCode!,
            outcome.message ?? '생성을 시작하지 못했습니다.',
          );
        }
        return ControlResponse.ok({'jobId': outcome.jobId});

      case ('GET', ['compose', 'jobs']):
        return ControlResponse.ok({
          'jobs': app.composeJobs.jobs
              .map(_composeJobJson)
              .toList(growable: false),
        });

      case ('POST', ['compose', 'jobs', final String id, 'cancel']):
        app.composeJobs.cancel(id);
        return ControlResponse.ok();

      case ('POST', ['compose', 'jobs', final String id, 'retry']):
        app.composeJobs.retry(id);
        return ControlResponse.ok();

      case ('POST', ['compose', final String id, 'register']):
        final song = await app.registerCompositionAsSong(id);
        if (song == null) {
          return ControlResponse.error(
            422,
            'register_failed',
            '곡 등록에 실패했습니다. 생성곡 id를 확인해 주세요.',
          );
        }
        if (body['karaokeSet'] == true) {
          await app.makeKaraokeSetForComposition(id);
        }
        return ControlResponse.ok({'songId': song.id});

      case ('DELETE', ['compose', final String id]):
        final item = app.composeLibrary.byId(id);
        if (item == null) {
          return ControlResponse.error(
            404,
            'composition_not_found',
            '해당 생성곡을 찾을 수 없습니다.',
          );
        }
        await app.composeLibrary.remove(item);
        return ControlResponse.ok();

      // ── 녹음 (v3.0.0, 읽기 전용 목록) ──
      case ('GET', ['recordings']):
        final library = RecordingLibraryService();
        await library.load();
        return ControlResponse.ok({
          'takes':
              library.takes.map(_recordingJson).toList(growable: false),
        });

      default:
        return ControlResponse.notFound();
    }
  }

  ControlResponse _songNotFound() =>
      ControlResponse.error(404, 'song_not_found', '해당 곡을 찾을 수 없습니다.');

  Map<String, dynamic> _stateJson() {
    final snapshot = app.playback.snapshot;
    final song = snapshot.song;
    return {
      'version': AppVersion.current,
      'song': song == null
          ? null
          : {
              'id': song.id,
              'title': song.title,
              'artist': song.artist,
              'slot': snapshot.trackSlot,
              'pitch': song.id.isEmpty
                  ? 0
                  : app.settings.pitchForSong(song.id, snapshot.trackSlot),
              // 곡 자체의 조성과, 구운 키·사용자 키까지 얹어 지금 들리는 조성.
              'tempo': app.settings.tempoForSong(song.id, snapshot.trackSlot),
              'musicalKey': song.musicalKey?.label,
              'soundingKey': app
                  .soundingKeyFor(song, snapshot.trackSlot)
                  ?.label,
            },
      'playing': snapshot.playing,
      'audioReady': snapshot.audioReady,
      'positionMs': app.playback.position.value.inMilliseconds,
      'durationMs': snapshot.duration.inMilliseconds,
      'queueLength': app.queue.length,
      'activeJobs': app.importJobs.jobs
          .where((j) => !j.status.isFinished)
          .length,
      'activeComposeJobs': app.composeJobs.jobs
          .where((j) => !j.status.isFinished)
          .length,
      'localAiEnabled': app.settings.localAiEnabled,
      'tools': {
        'ytDlp': {
          'found': app.ytDlpAvailable,
          'version': app.ytDlpVersion,
          'ejs': app.ytDlpEjsVersion,
        },
        'separator': {
          'online': app.separatorOnline,
          'label': app.separatorStatusLabel,
        },
        'compose': {
          'online': app.composeServerOnline,
          'label': app.composeStatusLabel,
        },
        'bgm': {'online': app.bgmServerOnline, 'label': app.bgmStatusLabel},
      },
    };
  }

  Map<String, dynamic> _songJson(Song song, {bool includeLyrics = false}) => {
    'id': song.id,
    'title': song.title,
    'artist': song.artist,
    'favorite': song.isFavorite,
    'hasSyncedLyrics': (song.lrcFileName ?? '').isNotEmpty,
    'slots': song.availableTrackSlots,
    'tracks': [
      for (final track in song.backingTracks)
        {
          'slot': track.slot,
          'label': track.label,
          'bakedSemitones': track.bakedSemitones,
        },
    ],
    'pitchBySlot': {
      for (final slot in song.availableTrackSlots)
        '$slot': app.settings.pitchForSong(song.id, slot),
    },
    'musicalKey': song.musicalKey?.label,
    'soundingKeyBySlot': {
      for (final slot in song.availableTrackSlots)
        '$slot': app.soundingKeyFor(song, slot)?.label,
    },
    if (includeLyrics) 'lyrics': song.lyricsText,
  };

  Map<String, dynamic> _jobJson(ImportJob job) => {
    'id': job.id,
    'url': job.url,
    'title': job.title,
    'status': job.status.name,
    'statusLabel': job.status.label,
    'ratio': job.ratio,
    'statusDetail': job.statusDetail,
    'songId': job.songId,
  };

  Map<String, dynamic> _compositionJson(Composition item) => {
    'id': item.id,
    'title': item.title,
    'mode': item.mode.storageValue,
    'durationSec': item.durationSec,
    'seed': item.seed,
    'lyrics': item.lyrics,
    'createdAt': item.createdAt.toIso8601String(),
    'genTimeSec': item.genTimeSec,
    'registeredSongId': item.registeredSongId,
    'batchId': item.batchId,
  };

  Map<String, dynamic> _composeJobJson(ComposeJob job) => {
    'id': job.id,
    'title': job.request.title,
    'mode': job.request.mode.storageValue,
    'status': job.status.name,
    'statusLabel': job.status.label,
    'statusDetail': job.statusDetail,
    'resultCompositionId': job.resultCompositionId,
  };

  Map<String, dynamic> _recordingJson(RecordingTake take) => {
    'id': take.id,
    'songId': take.songId,
    'songTitle': take.songTitle,
    'recordedAt': take.recordedAt.toIso8601String(),
    'durationMs': take.durationMs,
    'pitchSemitones': take.pitchSemitones,
    'rating': take.rating,
    'comment': take.comment,
    'isKeep': take.isKeep,
    'hasAccompaniment': take.hasAccompaniment,
    'hasMix': take.hasMix,
    'hasSeparatedVocal': take.hasSeparatedVocal,
  };
}

/// 루프백 HTTP 서버. bind 실패는 앱 동작에 영향을 주지 않는다(로그만).
class ControlServer {
  static const int defaultPort = 8772;

  final ControlRouter _router;
  final int port;
  HttpServer? _server;

  ControlServer(AppController app, {this.port = defaultPort})
    : _router = ControlRouter(app);

  bool get running => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      _server = server;
      server.listen(_handle, onError: (Object e) {
        debugPrint('제어 서버 오류: $e');
      });
      debugPrint('제어 서버 시작: http://127.0.0.1:$port');
    } catch (e) {
      // 포트 충돌 등 — 앱은 정상 동작하고 제어 API만 꺼진다.
      debugPrint('제어 서버를 열지 못했습니다(포트 $port): $e');
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    Map<String, dynamic>? body;
    try {
      final raw = await utf8.decoder.bind(request).join();
      if (raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) body = decoded;
      }
    } catch (_) {
      // 본문이 JSON이 아니면 빈 본문으로 취급한다.
    }

    final response = await _router.dispatch(
      request.method,
      request.uri.path,
      body: body,
      query: request.uri.queryParameters,
    );

    request.response
      ..statusCode = response.status
      ..headers.contentType = ContentType('application', 'json', charset: 'utf-8')
      ..write(jsonEncode(response.body));
    await request.response.close();
  }
}
