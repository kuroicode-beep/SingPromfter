import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/composition.dart';

void main() {
  group('Composition JSON', () {
    test('왕복 후 값이 보존된다', () {
      final original = Composition(
        id: 'c1',
        title: '별내의 밤',
        mode: ComposeMode.vocal,
        stylePromptKo: '잔잔한 발라드, 피아노',
        stylePromptEn: 'calm ballad, piano, slow tempo, female vocal',
        lyrics: '[verse]\n별빛이 내리는 밤',
        vocalType: 'female',
        genre: 'k-ballad',
        bpm: 72,
        durationSec: 210,
        seed: 42,
        fileName: 'c1.mp3',
        createdAt: DateTime(2026, 8, 8, 20, 30),
        genTimeSec: 187.5,
        batchId: 'batch-1',
      );
      final restored = Composition.fromJson(original.toJson());
      expect(restored.id, 'c1');
      expect(restored.mode, ComposeMode.vocal);
      expect(restored.stylePromptEn, contains('female vocal'));
      expect(restored.lyrics, contains('[verse]'));
      expect(restored.vocalType, 'female');
      expect(restored.bpm, 72);
      expect(restored.durationSec, 210);
      expect(restored.seed, 42);
      expect(restored.genTimeSec, 187.5);
      expect(restored.batchId, 'batch-1');
      expect(restored.isRegistered, isFalse);
    });

    test('필드가 없어도 안전하게 읽는다 (기본 BGM)', () {
      final c = Composition.fromJson(const {});
      expect(c.mode, ComposeMode.bgm);
      expect(c.durationSec, 0);
      expect(c.seed, -1);
      expect(c.isRegistered, isFalse);
    });

    test('effectivePrompt — 다듬은 영문 우선, 없으면 원문', () {
      final polished = Composition.fromJson(const {
        'stylePromptKo': '신나는 댄스',
        'stylePromptEn': 'upbeat dance, edm',
      });
      expect(polished.effectivePrompt, 'upbeat dance, edm');
      final raw = Composition.fromJson(const {'stylePromptKo': '신나는 댄스'});
      expect(raw.effectivePrompt, '신나는 댄스');
    });
  });
}
