// file: lib/services/song_filter_service.dart
//
// 곡 목록 검색·필터 로직을 한곳에서 제공한다.
import '../models/song.dart';

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
          return _matchesText(song.title, trimmed) ||
              _matchesText(song.artist, trimmed);
        })
        .toList(growable: false);
  }

  static bool _matchesText(String value, String query) {
    final normalizedTitle = value.toLowerCase();
    final normalizedQuery = query.toLowerCase();
    return normalizedTitle.contains(normalizedQuery) ||
        _koreanInitials(value).contains(normalizedQuery);
  }

  static String _koreanInitials(String value) {
    const initials = [
      'ㄱ',
      'ㄲ',
      'ㄴ',
      'ㄷ',
      'ㄸ',
      'ㄹ',
      'ㅁ',
      'ㅂ',
      'ㅃ',
      'ㅅ',
      'ㅆ',
      'ㅇ',
      'ㅈ',
      'ㅉ',
      'ㅊ',
      'ㅋ',
      'ㅌ',
      'ㅍ',
      'ㅎ',
    ];
    final buffer = StringBuffer();
    for (final codeUnit in value.runes) {
      if (codeUnit >= 0xAC00 && codeUnit <= 0xD7A3) {
        buffer.write(initials[(codeUnit - 0xAC00) ~/ 588]);
      } else {
        buffer.write(String.fromCharCode(codeUnit).toLowerCase());
      }
    }
    return buffer.toString();
  }
}
