import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/services/bgm_compose_client.dart';

void main() {
  group('buildGenerateBody — 8766 MusicGen 계약', () {
    test('musicgen 백엔드에 mp3 변환을 켠다', () {
      final body = buildGenerateBody(prompt: 'lofi beat', durationSec: 60);
      expect(body['backend'], 'musicgen');
      expect(body['convert_mp3'], isTrue);
      expect(body['duration'], 60.0);
      expect(body['model_size'], 'medium');
      expect(body['seed'], -1);
    });

    test('길이는 10~300초로 잘라 보낸다', () {
      expect(buildGenerateBody(prompt: 'p', durationSec: 3)['duration'], 10.0);
      expect(
        buildGenerateBody(prompt: 'p', durationSec: 900)['duration'],
        300.0,
      );
    });

    test('프리셋·모델 크기·seed를 전달한다', () {
      final body = buildGenerateBody(
        prompt: '',
        preset: 'ambient',
        durationSec: 120,
        modelSize: 'large',
        seed: 7,
      );
      expect(body['preset'], 'ambient');
      expect(body['model_size'], 'large');
      expect(body['seed'], 7);
    });
  });
}
