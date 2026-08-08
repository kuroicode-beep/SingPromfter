import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/services/song_compose_client.dart';

void main() {
  group('buildSongBody — 8774 게이트웨이 계약', () {
    test('보컬 타입·장르·가사·언어가 실린다', () {
      final body = buildSongBody(
        prompt: 'calm ballad, piano',
        lyrics: '[verse]\n별빛이 내리는 밤',
        durationSec: 210,
        vocalType: 'female',
        genre: 'k-ballad',
        bpm: 72,
        seed: 42,
      );
      expect(body['prompt'], 'calm ballad, piano');
      expect(body['lyrics'], contains('[verse]'));
      expect(body['duration'], 210.0);
      expect(body['vocal'], 'female');
      expect(body['genre'], 'k-ballad');
      expect(body['bpm'], 72);
      expect(body['seed'], 42);
      expect(body['format'], 'mp3');
      expect(body['lang'], 'ko');
    });

    test('길이는 180~600초 하드 제한으로 잘라 보낸다', () {
      expect(buildSongBody(prompt: 'p', durationSec: 60)['duration'], 180.0);
      expect(buildSongBody(prompt: 'p', durationSec: 900)['duration'], 600.0);
    });

    test('bpm이 없거나 0 이하면 body에서 뺀다', () {
      expect(
        buildSongBody(prompt: 'p', durationSec: 210).containsKey('bpm'),
        isFalse,
      );
      expect(
        buildSongBody(prompt: 'p', durationSec: 210, bpm: 0).containsKey('bpm'),
        isFalse,
      );
    });
  });

  group('SongJobStatus', () {
    test('done/error 판정', () {
      expect(const SongJobStatus(status: 'done').isDone, isTrue);
      expect(const SongJobStatus(status: 'error').isError, isTrue);
      expect(const SongJobStatus(status: 'running').isDone, isFalse);
      expect(const SongJobStatus(status: 'queued').isError, isFalse);
    });
  });
}
