// file: lib/services/lyrics_sync_service.dart
//
// 싱크 가사 가져오기·저장·조회를 한곳에서 다룬다.
import 'package:flutter/foundation.dart';

import '../models/song.dart';
import '../models/timed_lyrics.dart';
import '../repository/lrc_store.dart';
import 'lrclib_client.dart';

class LyricsFetchOutcome {
  final bool success;
  final String message;
  final Song? song;

  const LyricsFetchOutcome({
    required this.success,
    required this.message,
    this.song,
  });
}

class LyricsSyncService {
  final LrcStore _store;
  final LrclibClient _client;

  LyricsSyncService({LrcStore? store, LrclibClient? client})
    : _store = store ?? LrcStore(),
      _client = client ?? LrclibClient();

  /// 곡에 저장된 LRC를 읽어 파싱한다. 없으면 null.
  Future<TimedLyrics?> loadFor(Song song) async {
    if ((song.lrcFileName ?? '').isEmpty) return null;
    final raw = await _store.read(song.id);
    if (raw == null) return null;
    final parsed = LrcParser.parse(raw);
    return parsed.isEmpty ? null : parsed;
  }

  /// LRCLIB에서 싱크 가사를 찾아 저장한다.
  ///
  /// 정확 조회 → 실패 시 검색 폴백. 싱크 가사가 없는 결과는 쓰지 않는다.
  Future<LyricsFetchOutcome> fetchFor(Song song, {Duration? duration}) async {
    if (song.title.trim().isEmpty) {
      return const LyricsFetchOutcome(success: false, message: '곡 제목이 없어 찾을 수 없습니다.');
    }

    try {
      var candidate = await _client.get(
        title: song.title,
        artist: song.artist,
        duration: duration,
      );

      if (candidate == null || !candidate.hasSynced) {
        final query = '${song.title} ${song.artist}'.trim();
        final results = await _client.search(query: query);
        candidate = _pickBest(results, duration: duration);
      }

      // 가수가 채널명 등으로 오염됐을 수 있어 제목만으로 한 번 더 찾는다.
      if ((candidate == null || !candidate.hasSynced) &&
          song.artist.trim().isNotEmpty) {
        final results = await _client.search(query: song.title.trim());
        candidate = _pickBest(results, duration: duration);
      }

      if (candidate == null || !candidate.hasSynced) {
        return const LyricsFetchOutcome(
          success: false,
          message: '싱크 가사를 찾지 못했습니다. .lrc 파일을 직접 가져올 수 있습니다.',
        );
      }

      final saved = await save(song, candidate.syncedLyrics!);
      if (saved == null) {
        return const LyricsFetchOutcome(success: false, message: '가사 저장에 실패했습니다.');
      }
      return LyricsFetchOutcome(
        success: true,
        message: '싱크 가사를 가져왔습니다: ${candidate.trackName}',
        song: saved,
      );
    } catch (e) {
      debugPrint('가사 가져오기 실패: $e');
      return const LyricsFetchOutcome(
        success: false,
        message: '가사 서버에 연결하지 못했습니다. 네트워크를 확인해 주세요.',
      );
    }
  }

  /// LRC 원문을 저장하고 파일명이 반영된 곡을 돌려준다.
  Future<Song?> save(Song song, String lrcContent) async {
    final parsed = LrcParser.parse(lrcContent);
    if (parsed.isEmpty) return null;
    final fileName = await _store.write(song.id, lrcContent);
    if (fileName == null) return null;
    return song.copyWith(lrcFileName: fileName, updatedAt: DateTime.now());
  }

  Future<Song> remove(Song song) async {
    await _store.delete(song.id);
    return song.copyWith(clearLrcFileName: true, updatedAt: DateTime.now());
  }

  /// 길이가 가장 비슷하고 싱크가 있는 결과를 고른다. (순수 로직)
  static LyricsCandidate? _pickBest(
    List<LyricsCandidate> results, {
    Duration? duration,
  }) {
    final synced = results.where((r) => r.hasSynced).toList();
    if (synced.isEmpty) return null;
    if (duration == null || duration <= Duration.zero) return synced.first;

    synced.sort((a, b) {
      final da = (a.duration - duration).inMilliseconds.abs();
      final db = (b.duration - duration).inMilliseconds.abs();
      return da.compareTo(db);
    });
    return synced.first;
  }

  /// 테스트용 공개 래퍼.
  @visibleForTesting
  static LyricsCandidate? pickBestForTest(
    List<LyricsCandidate> results, {
    Duration? duration,
  }) => _pickBest(results, duration: duration);
}
