import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/prompter_settings.dart';
import 'package:singpromfter_app/services/song_list_shortcut_service.dart';

void main() {
  const settings = PrompterSettings(volume: 0.5, speedLevel: 2);

  test('arrow up increases volume', () {
    final next = SongListShortcutService.adjustSettings(
      settings,
      LogicalKeyboardKey.arrowUp,
    );
    expect(next?.volume, closeTo(0.6, 0.001));
    expect(next?.speedLevel, settings.speedLevel);
  });

  test('arrow down decreases volume', () {
    final next = SongListShortcutService.adjustSettings(
      settings,
      LogicalKeyboardKey.arrowDown,
    );
    expect(next?.volume, closeTo(0.4, 0.001));
  });

  test('arrow right increases prompter speed', () {
    final next = SongListShortcutService.adjustSettings(
      settings,
      LogicalKeyboardKey.arrowRight,
    );
    expect(next?.speedLevel, closeTo(2.5, 0.001));
    expect(next?.volume, settings.volume);
  });

  test('arrow left decreases prompter speed', () {
    final next = SongListShortcutService.adjustSettings(
      settings,
      LogicalKeyboardKey.arrowLeft,
    );
    expect(next?.speedLevel, closeTo(1.5, 0.001));
  });

  test('volume and speed clamp at bounds', () {
    expect(
      SongListShortcutService.adjustSettings(
        const PrompterSettings(volume: 1),
        LogicalKeyboardKey.arrowUp,
      )?.volume,
      1,
    );
    expect(
      SongListShortcutService.adjustSettings(
        const PrompterSettings(volume: 0),
        LogicalKeyboardKey.arrowDown,
      )?.volume,
      0,
    );
    expect(
      SongListShortcutService.adjustSettings(
        const PrompterSettings(speedLevel: 10),
        LogicalKeyboardKey.arrowRight,
      )?.speedLevel,
      10,
    );
    expect(
      SongListShortcutService.adjustSettings(
        const PrompterSettings(speedLevel: 0),
        LogicalKeyboardKey.arrowLeft,
      )?.speedLevel,
      0,
    );
  });
}
