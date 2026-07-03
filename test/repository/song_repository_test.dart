import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/repository/song_repository.dart';

void main() {
  group('SongRepository filename builders', () {
    final repo = SongRepository.instance;

    test('buildLyricsFileName replaces forbidden characters', () {
      expect(repo.buildLyricsFileName('a<b>c:d'), 'a b c d.txt');
    });

    test('buildLyricsFileName normalizes whitespace', () {
      expect(repo.buildLyricsFileName('노래   제목'), '노래 제목.txt');
    });

    test('buildLyricsFileName uses fallback for blank title', () {
      expect(repo.buildLyricsFileName('   '), 'song.txt');
    });

    test('buildBackingTrackFileName includes slot number', () {
      expect(repo.buildBackingTrackFileName('노래', 1), '노래_mr1.mp3');
    });
  });
}
