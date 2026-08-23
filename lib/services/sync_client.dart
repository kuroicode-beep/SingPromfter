// file: lib/services/sync_client.dart
//
// 폰이 PC에서 곡을 받아오는 쪽. PC의 로컬 데이터가 정본이라 방향은
// PC → 폰 단방향이다 — 폰에서 PC로 쓰는 경로는 만들지 않는다.
//
// http.Client를 생성자로 받는다(이 코드베이스 규약) — 테스트에서 가짜를
// 넣어 서버 없이 델타·오류 처리를 검증할 수 있다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/song.dart';
import '../repository/lrc_store.dart';
import '../repository/practice_log_store.dart';
import '../repository/song_repository.dart';
import 'sync_protocol.dart';

class SyncOutcome {
  final bool ok;
  final String message;
  final int songCount;
  final int downloaded;
  final int skipped;

  const SyncOutcome({
    required this.ok,
    required this.message,
    this.songCount = 0,
    this.downloaded = 0,
    this.skipped = 0,
  });

  const SyncOutcome.failure(this.message)
    : ok = false,
      songCount = 0,
      downloaded = 0,
      skipped = 0;
}

class SyncClient {
  final http.Client _http;
  final SongRepository _repo;
  final LrcStore _lrcStore;

  final PracticeLogStore _practiceStore;

  SyncClient({
    http.Client? client,
    SongRepository? repo,
    LrcStore? lrcStore,
    PracticeLogStore? practiceStore,
  }) : _http = client ?? http.Client(),
       _repo = repo ?? SongRepository.instance,
       _lrcStore = lrcStore ?? LrcStore(),
       _practiceStore = practiceStore ?? PracticeLogStore();

  /// 폰에서 만든 변경분을 PC로 올린다.
  ///
  /// 🔴 받기(pull)보다 **먼저** 불러야 한다. 순서가 뒤바뀌면 폰이 누른 별과
  /// 방금 한 연습기록이 PC 상태로 덮인 뒤에 올라가 아무 효과가 없다.
  ///
  /// 실패해도 받기는 계속한다 — 올리기가 안 된다고 곡을 못 받을 이유는 없다.
  /// 대신 [pendingFavorites]를 비우지 않아 다음 동기화에서 다시 시도한다.
  Future<bool> push({
    required Uri base,
    required String code,
    required Map<String, bool> pendingFavorites,
  }) async {
    try {
      final sessions = await _practiceStore.load();
      final payload = SyncPushPayload(
        favorites: pendingFavorites,
        practiceSessions: sessions,
      );
      if (payload.isEmpty) return true;
      final res = await _http
          .post(
            base.replace(path: '/api/sync/push'),
            headers: {
              'x-sync-token': code,
              'content-type': 'application/json; charset=utf-8',
            },
            body: utf8.encode(jsonEncode(payload.toJson())),
          )
          .timeout(const Duration(seconds: 30));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('동기화 올리기 실패: $e');
      return false;
    }
  }

  /// 입력받은 주소를 정규화한다. 사용자는 "192.168.0.5"만 적기도 하고
  /// "http://192.168.0.5:8772/"까지 적기도 한다 — 둘 다 받는다.
  static Uri? normalizeBase(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (!text.startsWith('http://') && !text.startsWith('https://')) {
      text = 'http://$text';
    }
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : 8772,
    );
  }

  /// PC에서 곡을 받아 로컬 라이브러리를 PC 상태로 맞춘다.
  ///
  /// [onProgress]는 (받은 파일 수, 전체 파일 수, 지금 받는 파일명)을 알린다.
  /// 파일명까지 주는 이유: 반주가 크면 몇 분씩 걸려서, 숫자만 멈춰 있으면
  /// 사용자가 멈춘 줄 안다.
  Future<SyncOutcome> pull({
    required String address,
    required String pairingCode,
    Map<String, bool> pendingFavorites = const {},
    void Function(int done, int total, String? current)? onProgress,
    void Function()? onPushed,
  }) async {
    final base = normalizeBase(address);
    if (base == null) {
      return const SyncOutcome.failure('PC 주소를 확인해 주세요 (예: 192.168.0.5:8772)');
    }
    final code = pairingCode.trim().toUpperCase();
    if (code.isEmpty) {
      return const SyncOutcome.failure('페어링 코드를 입력해 주세요.');
    }

    // 받기 전에 폰의 변경분을 먼저 올린다 — 순서가 뒤바뀌면 덮인다.
    if (await push(
      base: base,
      code: code,
      pendingFavorites: pendingFavorites,
    )) {
      onPushed?.call();
    }

    final SyncManifest manifest;
    try {
      final res = await _http
          .get(
            base.replace(path: '/api/sync/manifest'),
            headers: {'x-sync-token': code},
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 401) {
        return const SyncOutcome.failure('페어링 코드가 맞지 않습니다.');
      }
      if (res.statusCode == 403) {
        return const SyncOutcome.failure('PC에서 동기화 서버를 켜 주세요.');
      }
      if (res.statusCode != 200) {
        return SyncOutcome.failure('PC가 응답하지 않습니다 (HTTP ${res.statusCode})');
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        return const SyncOutcome.failure('PC 응답을 해석하지 못했습니다.');
      }
      manifest = SyncManifest.fromJson(decoded);
    } catch (e) {
      debugPrint('동기화 매니페스트 실패: $e');
      return const SyncOutcome.failure(
        'PC에 연결하지 못했습니다. 같은 와이파이인지, 주소가 맞는지 확인해 주세요.',
      );
    }

    if (!manifest.supported) {
      return SyncOutcome.failure(
        'PC 앱이 더 새로운 버전입니다(${manifest.appVersion}) — 폰 앱을 업데이트해 주세요.',
      );
    }

    // 폰에 이미 있는 반주 파일의 크기를 모아 델타를 계산한다.
    final localStats = <String, TrackStat>{};
    try {
      final dir = await _repo.getBackingTrackDir();
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        localStats[entity.uri.pathSegments.last] = (
          size: stat.size,
          mtime: stat.modified.toUtc().toIso8601String(),
        );
      }
    } catch (e) {
      debugPrint('로컬 반주 목록 조회 실패: $e');
    }

    final downloads = SyncPlanner.plan(
      manifest: manifest,
      localStats: localStats,
    );
    onProgress?.call(0, downloads.length, null);

    var done = 0;
    for (final item in downloads) {
      onProgress?.call(done, downloads.length, item.fileName);
      try {
        final res = await _http
            .get(
              base.replace(
                path: '/api/sync/file',
                queryParameters: {'name': item.fileName},
              ),
              headers: {'x-sync-token': code},
            )
            .timeout(const Duration(minutes: 5));
        if (res.statusCode != 200) {
          debugPrint('반주 받기 실패(${item.fileName}): HTTP ${res.statusCode}');
          continue;
        }
        final dir = await _repo.getBackingTrackDir();
        final file = File('${dir.path}/${item.fileName}');
        await file.writeAsBytes(res.bodyBytes);
        done++;
        onProgress?.call(done, downloads.length, item.fileName);
      } catch (e) {
        debugPrint('반주 받기 실패(${item.fileName}): $e');
      }
    }

    // 곡 메타·가사는 PC를 그대로 따른다(단방향 동기화).
    final songs = <Song>[];
    for (final raw in manifest.songs) {
      try {
        final song = Song.fromJson(raw);
        songs.add(song);
        final lyricsText = (raw['lyricsText'] as String?) ?? '';
        if (lyricsText.isNotEmpty) {
          await _writeLyrics(song, lyricsText);
        }
        final lrc = raw['lrc'] as String?;
        if (lrc != null && lrc.trim().isNotEmpty) {
          await _lrcStore.write(song.id, lrc);
        }
      } catch (e) {
        debugPrint('곡 해석 실패: $e');
      }
    }

    try {
      await _repo.saveSongs(songs);
    } catch (e) {
      debugPrint('곡 저장 실패: $e');
      return const SyncOutcome.failure('받은 곡을 저장하지 못했습니다.');
    }

    final skipped = downloads.length - done;
    return SyncOutcome(
      ok: true,
      songCount: songs.length,
      downloaded: done,
      skipped: skipped,
      message: downloads.isEmpty
          ? '이미 최신입니다 — 곡 ${songs.length}개'
          : '곡 ${songs.length}개 · 반주 $done개 받음'
                '${skipped > 0 ? " (실패 $skipped개)" : ""}',
    );
  }

  Future<void> _writeLyrics(Song song, String text) async {
    try {
      final dir = await _repo.getLyricsDir();
      final name = song.lyricsPath.split(RegExp(r'[/\\]')).last;
      if (name.isEmpty) return;
      await File('${dir.path}/$name').writeAsString(text);
    } catch (e) {
      debugPrint('가사 저장 실패(${song.id}): $e');
    }
  }
}
