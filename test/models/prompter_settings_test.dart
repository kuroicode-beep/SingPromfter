import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/prompter_settings.dart';

void main() {
  group('PrompterSettings', () {
    test('withSongTrackSlot stores per-song slot and last selected slot', () {
      const settings = PrompterSettings();

      final updated = settings.withSongTrackSlot('song-1', 2);

      expect(updated.trackSlotForSong('song-1'), 2);
      expect(updated.lastSelectedTrackSlot, 2);
    });

    test('encode/decode preserves accessibility and playback settings', () {
      const original = PrompterSettings(
        fontSizeLevel: 5,
        lineHeightLevel: 4,
        speedLevel: 3,
        volume: 0.7,
        playbackRate: 1.25,
        lastSelectedTrackSlot: 2,
        fontFamily: 'Malgun Gothic',
        boldText: true,
        customFontSizePt: 40,
        lastSelectedTrackSlotBySong: {'song-1': 2},
      );

      final restored = PrompterSettings.decode(
        PrompterSettings.encode(original),
      );

      expect(restored.fontSizeLevel, 5);
      expect(restored.lineHeightLevel, 4);
      expect(restored.volume, 0.7);
      expect(restored.playbackRate, 1.25);
      expect(restored.boldText, isTrue);
      expect(restored.trackSlotForSong('song-1'), 2);
      expect(restored.customFontSizePt, 40);
    });

    test('custom font size overrides level-derived size', () {
      const settings = PrompterSettings(fontSizeLevel: 1, customFontSizePt: 48);

      expect(settings.effectiveFontSizePt, 48);
    });
  });
}
