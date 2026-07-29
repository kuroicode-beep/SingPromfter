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
      // 정확 조회 결과라도 길이가 크게 다르면 다른 곡일 가능성이 높다.
      if (candidate != null && !_withinTolerance(candidate, duration)) {
        candidate = null;
      }

      if (candidate == null || !candidate.hasSynced) {
        final query = '${song.title} ${song.artist}'.trim();
        final results = await _client.search(query: query);
        candidate = pickLyricsCandidate(
          results,
          duration: duration,
          artist: song.artist,
        );
      }

      // 가수가 채널명 등으로 오염됐을 수 있어 제목만으로 한 번 더 찾는다.
      // 이 결과는 동명 곡투성이라 아래 picker의 근거 요구가 특히 중요하다.
      if ((candidate == null || !candidate.hasSynced) &&
          song.artist.trim().isNotEmpty) {
        final results = await _client.search(query: song.title.trim());
        candidate = pickLyricsCandidate(
          results,
          duration: duration,
          artist: song.artist,
        );
      }

      if (candidate == null || !candidate.hasSynced) {
        return const LyricsFetchOutcome(
          success: false,
          message: '싱크 가사를 찾지 못했습니다. '
              '곡 수정에서 가사를 붙여넣거나 .lrc 파일을 가져올 수 있습니다.',
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

  /// 길이 차이가 이 이상이면 다른 곡으로 간주한다.
  static const Duration durationTolerance = Duration(seconds: 7);

  static bool _withinTolerance(LyricsCandidate c, Duration? duration) {
    if (duration == null || duration <= Duration.zero) return true;
    return (c.duration - duration).inMilliseconds.abs() <=
        durationTolerance.inMilliseconds;
  }

  /// 검색 결과에서 후보를 고른다. (순수 로직 — 테스트 대상)
  ///
  /// 검색 결과는 동명 곡이 섞인다. 「선물」처럼 흔한 제목은 가수가 전혀 다른
  /// 곡이 첫 결과로 오기도 한다. 그래서 **근거 없이는 채택하지 않는다**:
  /// 길이가 ±7초 안에서 맞거나, 가수가 겹쳐야 한다. 길이도 모르고 가수도
  /// 안 맞으면 못 찾은 것으로 처리한다 — 엉뚱한 가사보다 못 찾음이 낫다.
  /// (예전엔 길이를 모르면 첫 결과를 그냥 받았고, 그게 사고의 원인이었다.)
  static LyricsCandidate? pickLyricsCandidate(
    List<LyricsCandidate> results, {
    Duration? duration,
    String artist = '',
  }) {
    final synced = results.where((r) => r.hasSynced).toList();
    if (synced.isEmpty) return null;

    final hasDuration = duration != null && duration > Duration.zero;
    if (hasDuration) {
      synced.sort((a, b) {
        final da = (a.duration - duration).inMilliseconds.abs();
        final db = (b.duration - duration).inMilliseconds.abs();
        return da.compareTo(db);
      });
      // 가수까지 겹치는 후보가 있으면 그 안에서 길이가 가장 가까운 것.
      final withArtist = synced
          .where((c) => artistLooksSame(artist, c.artistName))
          .toList();
      final best = (withArtist.isNotEmpty ? withArtist : synced).first;
      return _withinTolerance(best, duration) ? best : null;
    }

    // 길이를 모르면 가수라도 맞아야 한다.
    for (final c in synced) {
      if (artistLooksSame(artist, c.artistName)) return c;
    }
    return null;
  }

  /// 두 가수 이름이 같은 사람으로 보이는지.
  /// 공백·구두점·괄호를 걷어낸 뒤 한쪽이 다른 쪽을 포함하면 같다고 본다
  /// ("윤후" ↔ "윤후 (Yoon Hoo)"). 빈 이름은 근거가 될 수 없다.
  @visibleForTesting
  static bool artistLooksSame(String a, String b) {
    final na = _normalizeArtist(a);
    final nb = _normalizeArtist(b);
    if (na.isEmpty || nb.isEmpty) return false;
    return na.contains(nb) || nb.contains(na);
  }

  static String _normalizeArtist(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'''[\s\-_.,·'"()\[\]]'''), '');
}
