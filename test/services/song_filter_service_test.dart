import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/services/song_filter_service.dart';

void main() {
  final songs = [
    Song(
      id: '1',
      title: '봄날',
      lyricsPath: 'a.txt',
      lyricsText: '가사',
      backingTracks: const [],
      createdAt: DateTime(2026, 6, 1),
      updatedAt: DateTime(2026, 6, 1),
      isFavorite: true,
    ),
    Song(
      id: '2',
      title: 'Dynamite',
      lyricsPath: 'b.txt',
      lyricsText: 'lyrics',
      backingTracks: const [],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  ];

  test('SongFilterService filters favorites and title query', () {
    final favorites = SongFilterService.filter(
      songs,
      mode: SongListFilterMode.favorites,
    );
    expect(favorites, hasLength(1));
    expect(favorites.first.title, '봄날');

    final searched = SongFilterService.filter(
      songs,
      query: 'dyn',
      mode: SongListFilterMode.all,
    );
    expect(searched, hasLength(1));
    expect(searched.first.title, 'Dynamite');
  });

  test('SongFilterService matches Korean initials', () {
    final result = SongFilterService.filter(
      songs,
      query: 'ㅂㄴ',
      mode: SongListFilterMode.all,
    );
    expect(result, hasLength(1));
    expect(result.first.title, '봄날');
  });

  test('SongFilterService matches artist name', () {
    final songs = [
      Song(
        id: '1',
        title: '봄날',
        artist: '아이유',
        lyricsPath: 'a.txt',
        lyricsText: '가사',
        backingTracks: const [],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ];

    final result = SongFilterService.filter(
      songs,
      query: '아이유',
      mode: SongListFilterMode.all,
    );
    expect(result, hasLength(1));
  });
}
