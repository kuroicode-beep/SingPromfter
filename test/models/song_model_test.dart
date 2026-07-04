import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/backing_track.dart';
import 'package:singpromfter_app/models/song.dart';

void main() {
  group('Song serialization', () {
    test('toJson/fromJson preserves current fields including artist', () {
      final original = Song(
        id: 'song-1',
        title: '테스트 곡',
        artist: '테스트 가수',
        lyricsPath: 'C:/data/txt/test.txt',
        lyricsText: '가사 내용',
        backingTracks: const [
          BackingTrack(
            slot: 1,
            fileName: 'test_mr1.mp3',
            label: '원곡',
            startMs: 1000,
            endMs: 90000,
          ),
          BackingTrack(slot: 2, fileName: 'test_mr2.mp3', label: '낮은키'),
        ],
        createdAt: DateTime(2026, 7, 4),
        updatedAt: DateTime(2026, 7, 4, 1),
        isFavorite: true,
      );

      final restored = Song.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.artist, '테스트 가수');
      expect(restored.lyricsText, original.lyricsText);
      expect(restored.isFavorite, isTrue);
      expect(restored.backingTracks, hasLength(2));
      expect(restored.backingTracks.first.label, '원곡');
      expect(restored.backingTracks.first.startMs, 1000);
      expect(restored.backingTracks.first.endMs, 90000);
    });

    test('fromJson without artist defaults to empty string', () {
      final song = Song.fromJson({
        'id': 'legacy-artist',
        'title': '구버전 곡',
      });

      expect(song.artist, '');
    });

    test('legacy mrFileName migrates to slot 1 backing track', () {
      final song = Song.fromJson({
        'id': 'legacy-1',
        'title': '구버전 곡',
        'mrFileName': 'old.mp3',
      });

      expect(song.backingTracks, hasLength(1));
      expect(song.backingTracks.first.slot, 1);
      expect(song.backingTracks.first.fileName, 'old.mp3');
      expect(song.backingTracks.first.label, 'MR1');
    });

    test('encodeList/decodeList round-trips songs', () {
      final songs = [
        Song(
          id: 'song-1',
          title: '노래',
          lyricsPath: '노래.txt',
          lyricsText: '가사',
          backingTracks: const [],
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ];

      final decoded = Song.decodeList(Song.encodeList(songs));

      expect(decoded, hasLength(1));
      expect(decoded.first.title, '노래');
      expect(decoded.first.lyricsText, '가사');
    });
  });
}
