// file: lib/services/sync_server_handler.dart
//
// PC가 폰에 곡을 넘겨주는 쪽. 제어 API 서버(control_server) 위에 얹는다 —
// 새 서버를 세우지 않는다.
//
// 🔴 보안: 동기화를 켜면 서버가 루프백 밖(LAN)으로 나간다. 그때부터
// 원격 연결에는 두 가지 제약이 붙는다.
//   ① /api/sync/* 이외의 경로는 전부 거부 — 곡 삭제·재생 조작 같은 것이
//      LAN에 열리면 안 된다. MCP는 원래 같은 PC에서만 부른다.
//   ② X-Sync-Token 헤더가 페어링 코드와 같아야 한다.
// 루프백 연결(같은 PC)은 지금까지처럼 제한 없이 동작한다.
import 'dart:convert';
import 'dart:io';

import '../constants/app_version.dart';
import '../controllers/app_controller.dart';
import '../repository/lrc_store.dart';
import '../repository/practice_log_store.dart';
import '../repository/song_repository.dart';
import 'sync_protocol.dart';

class SyncServerHandler {
  final AppController app;
  final SongRepository _repo;
  final LrcStore _lrcStore;

  final PracticeLogStore _practiceStore;

  SyncServerHandler(
    this.app, {
    SongRepository? repo,
    LrcStore? lrcStore,
    PracticeLogStore? practiceStore,
  }) : _repo = repo ?? SongRepository.instance,
       _lrcStore = lrcStore ?? LrcStore(),
       _practiceStore = practiceStore ?? PracticeLogStore();

  static const String tokenHeader = 'x-sync-token';
  static const String pathPrefix = '/api/sync/';

  /// 이 요청을 처리해야 하는가.
  static bool handles(String path) => path.startsWith(pathPrefix);

  /// 원격(루프백이 아닌) 연결이 이 경로를 쓸 수 있는가.
  /// 동기화 경로만 허용한다 — 나머지는 같은 PC에서만.
  static bool allowedFromRemote(String path) => handles(path);

  /// 파일명이 경로가 아닌 '이름'인가.
  ///
  /// 🔴 '..'가 들어 있다고 막으면 안 된다 — 곡 제목에 말줄임표가 들어간
  /// 파일("아마도 그건.. - 최용준_mr1.mp3")이 통째로 거부된다(실측 3건).
  /// 막아야 하는 건 경로 구분자와 상위 디렉터리 참조 자체다.
  static bool isSafeTrackName(String fileName) {
    final name = fileName.trim();
    if (name.isEmpty) return false;
    if (name.contains('/') || name.contains(r'\')) return false;
    if (name == '.' || name == '..') return false;
    return true;
  }

  /// 매니페스트를 만든다. 반주 파일이 실제로 있는 것만 싣는다.
  Future<SyncManifest> buildManifest() async {
    final songs = app.songs;
    final lrcById = <String, String>{};
    final trackStats = <String, TrackStat>{};

    for (final song in songs) {
      if ((song.lrcFileName ?? '').isNotEmpty) {
        final lrc = await _lrcStore.read(song.id);
        if (lrc != null) lrcById[song.id] = lrc;
      }
      for (final track in song.backingTracks) {
        final path = await _repo.getBackingTrackPath(track.fileName);
        if (path == null) continue;
        final file = File(path);
        if (!await file.exists()) continue;
        final stat = await file.stat();
        trackStats[track.fileName] = (
          size: stat.size,
          mtime: stat.modified.toUtc().toIso8601String(),
        );
      }
    }

    return SyncManifest.build(
      songs: songs,
      appVersion: AppVersion.current,
      lrcBySongId: lrcById,
      trackStats: trackStats,
    );
  }

  /// 반주 파일 하나를 찾는다. 매니페스트에 실린 파일만 내준다 —
  /// 임의 경로 요청으로 PC의 다른 파일을 읽어 가지 못하게.
  Future<File?> resolveTrackFile(String fileName) async {
    if (!isSafeTrackName(fileName)) return null;
    final safe = fileName.trim();
    // 진짜 방어선은 이것 — 등록된 반주 파일명과 정확히 같아야 한다.
    // 경로 문자열을 아무리 꾸며도 목록에 없으면 통과하지 못한다.
    final known = app.songs.any(
      (s) => s.backingTracks.any((t) => t.fileName == safe),
    );
    if (!known) return null;
    final path = await _repo.getBackingTrackPath(safe);
    if (path == null) return null;
    final file = File(path);
    return await file.exists() ? file : null;
  }

  /// 폰이 올린 변경분을 반영하고 저장한다.
  Future<SyncMergeResult> applyPush(SyncPushPayload payload) async {
    final sessions = await _practiceStore.load();
    final result = SyncMerger.merge(
      songs: app.songs,
      sessions: sessions,
      payload: payload,
    );
    // 바뀐 게 없으면 파일을 다시 쓰지 않는다 — songs.json은 핫 파일이다.
    if (result.favoritesApplied > 0) {
      app.songs = result.songs;
      await _repo.saveSongs(result.songs);
    }
    if (result.sessionsAdded > 0) {
      await _practiceStore.save(result.sessions);
    }
    return result;
  }

  /// 요청 하나를 처리한다. 처리했으면 true.
  Future<bool> handle(HttpRequest request) async {
    final path = request.uri.path;
    if (!handles(path)) return false;

    final settings = app.settings;
    if (!settings.syncServerEnabled) {
      await _json(request, 403, {
        'ok': false,
        'error': {'code': 'sync_disabled', 'message': '동기화 서버가 꺼져 있습니다.'},
      });
      return true;
    }

    final token = request.headers.value(tokenHeader)?.trim() ?? '';
    if (settings.syncPairingCode.isEmpty ||
        token != settings.syncPairingCode) {
      await _json(request, 401, {
        'ok': false,
        'error': {'code': 'bad_token', 'message': '페어링 코드가 맞지 않습니다.'},
      });
      return true;
    }

    switch (path) {
      case '${pathPrefix}manifest':
        final manifest = await buildManifest();
        await _json(request, 200, {'ok': true, ...manifest.toJson()});
        return true;

      case '${pathPrefix}file':
        final name = request.uri.queryParameters['name'] ?? '';
        final file = await resolveTrackFile(name);
        if (file == null) {
          await _json(request, 404, {
            'ok': false,
            'error': {'code': 'file_not_found', 'message': '파일이 없습니다.'},
          });
          return true;
        }
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType('application', 'octet-stream')
          ..headers.contentLength = await file.length();
        await request.response.addStream(file.openRead());
        await request.response.close();
        return true;

      // 폰이 만든 변경분(즐겨찾기·연습기록)을 받아 얹는다.
      // 곡·가사·반주는 여전히 PC가 정본이라 여기서 건드리지 않는다.
      case '${pathPrefix}push':
        if (request.method != 'POST') {
          await _json(request, 405, {
            'ok': false,
            'error': {'code': 'method_not_allowed', 'message': 'POST만 됩니다.'},
          });
          return true;
        }
        final body = await utf8.decoder.bind(request).join();
        Map<String, dynamic> json;
        try {
          final decoded = body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(body);
          json = decoded is Map<String, dynamic> ? decoded : {};
        } catch (_) {
          await _json(request, 422, {
            'ok': false,
            'error': {'code': 'bad_json', 'message': '본문을 해석하지 못했습니다.'},
          });
          return true;
        }
        final result = await applyPush(SyncPushPayload.fromJson(json));
        await _json(request, 200, {
          'ok': true,
          'favoritesApplied': result.favoritesApplied,
          'sessionsAdded': result.sessionsAdded,
        });
        return true;

      default:
        await _json(request, 404, {
          'ok': false,
          'error': {'code': 'not_found', 'message': '해당 경로가 없습니다.'},
        });
        return true;
    }
  }

  Future<void> _json(
    HttpRequest request,
    int status,
    Map<String, dynamic> body,
  ) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType('application', 'json', charset: 'utf-8')
      ..write(jsonEncode(body));
    await request.response.close();
  }
}

/// 페어링 코드 생성·검증. 사람이 폰에 손으로 옮겨 적는 값이라
/// 헷갈리는 글자(0/O, 1/I/l)를 뺀 6자리를 쓴다.
class SyncPairingCode {
  SyncPairingCode._();

  // 0·O, 1·I·L을 뺀다 — 폰에 손으로 옮겨 적다 오타가 나면 원인을 못 찾는다.
  static const String alphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  static const int length = 6;

  static String generate(int Function(int max) nextInt) {
    final buf = StringBuffer();
    for (var i = 0; i < length; i++) {
      buf.write(alphabet[nextInt(alphabet.length)]);
    }
    return buf.toString();
  }

  static bool isValid(String code) {
    final c = code.trim().toUpperCase();
    if (c.length != length) return false;
    return c.split('').every(alphabet.contains);
  }
}
