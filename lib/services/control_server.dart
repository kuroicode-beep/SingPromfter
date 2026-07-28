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
import '../controllers/import_job_controller.dart';
import '../models/import_plan.dart';
import '../models/mr_source_mode.dart';
import '../models/song.dart';

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
        final mode = MrSourceModeInfo.fromStorage(body['mode'] as String?);
        final fetchLyrics = body['fetchLyrics'] as bool? ?? true;
        // plan이 없으면 기존 동작(반주 1개) — 하위 호환.
        final rawPlan = body['plan'];
        final plan = rawPlan is Map<String, dynamic>
            ? ImportPlan.fromJson(rawPlan)
            : const ImportPlan.single();
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
        return ControlResponse.ok({'jobId': outcome.jobId});

      case ('PATCH', ['songs', final String id]):
        final updated = await app.updateSongFields(
          id,
          title: body['title'] as String?,
          artist: body['artist'] as String?,
          lyrics: body['lyrics'] as String?,
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

      case ('POST', ['playback', 'rate']):
        final value = (body['value'] as num?)?.toDouble();
        if (value == null || value < 0.5 || value > 1.5) {
          return ControlResponse.error(
            422,
            'bad_value',
            'value(0.5~1.5)가 필요합니다.',
          );
        }
        await app.updateSettings(app.settings.copyWith(playbackRate: value));
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
      'tools': {
        'ytDlp': {'found': app.ytDlpAvailable, 'version': app.ytDlpVersion},
        'separator': {
          'online': app.separatorOnline,
          'label': app.separatorStatusLabel,
        },
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
