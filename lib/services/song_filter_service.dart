// file: lib/services/song_filter_service.dart
//
// 곡 목록 검색·필터 로직을 한곳에서 제공한다.
import '../models/song.dart';
import '../utils/korean_text.dart';

enum SongListFilterMode {
  all,
  favorites,
  withBackingTrack,
  recent,
}

class SongFilterService {
  SongFilterService._();

  static const recentWindowDays = 30;

  static List<Song> filter(
    List<Song> songs, {
    String query = '',
    SongListFilterMode mode = SongListFilterMode.all,
  }) {
    final trimmed = query.trim();
    final recentCutoff = DateTime.now().subtract(
      const Duration(days: recentWindowDays),
    );

    return songs
        .where((song) {
          switch (mode) {
            case SongListFilterMode.all:
              break;
            case SongListFilterMode.favorites:
              if (!song.isFavorite) return false;
              break;
            case SongListFilterMode.withBackingTrack:
              if (song.backingTracks.isEmpty) return false;
              break;
            case SongListFilterMode.recent:
              if (song.createdAt.isBefore(recentCutoff)) return false;
              break;
          }
          if (trimmed.isEmpty) return true;
          return KoreanText.matches(song.title, trimmed) ||
              KoreanText.matches(song.artist, trimmed);
        })
        .toList(growable: false);
  }
}
