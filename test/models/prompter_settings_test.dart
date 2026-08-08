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
          volume: 0.7,
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
      expect(restored.boldText, isTrue);
      expect(restored.trackSlotForSong('song-1'), 2);
      expect(restored.customFontSizePt, 40);
    });

    test('custom font size overrides level-derived size', () {
      const settings = PrompterSettings(fontSizeLevel: 1, customFontSizePt: 48);

      expect(settings.effectiveFontSizePt, 48);
    });

    test('showEqMeter는 기본 켜짐이고 직렬화 왕복된다', () {
      const original = PrompterSettings(showEqMeter: false);
      final restored = PrompterSettings.decode(
        PrompterSettings.encode(original),
      );
      expect(restored.showEqMeter, isFalse);
      // 기존 저장 데이터(필드 없음)는 기본값 true.
      expect(PrompterSettings.fromJson(const {}).showEqMeter, isTrue);
    });

    test('v5.0.0 녹음·AI 필드가 왕복 보존된다', () {
      const original = PrompterSettings(
        recordingDevice: '마이크(RØDE NT-USB Mini)',
        recordingGain: 1.5,
        localAiEnabled: true,
        cloudAiEnabled: true,
        ollamaModel: 'gemma4:12b',
      );
      final restored = PrompterSettings.decode(
        PrompterSettings.encode(original),
      );
      expect(restored.recordingDevice, '마이크(RØDE NT-USB Mini)');
      expect(restored.recordingGain, 1.5);
      expect(restored.localAiEnabled, isTrue);
      expect(restored.cloudAiEnabled, isTrue);
      expect(restored.ollamaModel, 'gemma4:12b');
    });

    test('v5.0.0 필드의 기본값 — AI는 꺼짐, 게인 1.0', () {
      final defaults = PrompterSettings.fromJson(const {});
      expect(defaults.recordingDevice, isNull);
      expect(defaults.recordingGain, 1.0);
      expect(defaults.localAiEnabled, isFalse);
      expect(defaults.cloudAiEnabled, isFalse);
      expect(defaults.ollamaModel, 'gemma4:12b');
    });

    test('녹음 게인은 0~2로 제한하고 빈 모델명은 기본값으로', () {
      expect(
        PrompterSettings.fromJson(const {'recordingGain': 9}).recordingGain,
        2.0,
      );
      expect(
        PrompterSettings.fromJson(const {'ollamaModel': '  '}).ollamaModel,
        'gemma4:12b',
      );
    });

    test('clearRecordingDevice로 자동 선택으로 되돌린다', () {
      const original = PrompterSettings(recordingDevice: 'mic');
      final cleared = original.copyWith(clearRecordingDevice: true);
      expect(cleared.recordingDevice, isNull);
    });

    test('구 recordingDeviceName 키는 recordingDevice로 흡수된다', () {
      final migrated = PrompterSettings.fromJson(
        const {'recordingDeviceName': 'old-mic'},
      );
      expect(migrated.recordingDevice, 'old-mic');
    });
  });
}
