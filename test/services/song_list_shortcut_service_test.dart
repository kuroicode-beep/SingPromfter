import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/prompter_settings.dart';
import 'package:singpromfter_app/services/song_list_shortcut_service.dart';

// 메인 화면 단축키.
//
// v2.8.0에서 ←/→ 가 가사 속도 조절에서 5초 뒤로/앞으로 이동으로 바뀌었다.
// 속도는 이제 음악 템포 하나뿐이고, 템포는 조작판의 -/+ 와 Shift+휠이 맡는다.
// adjustSettings는 순수 함수라 디바운스가 필요한 템포 렌더를 부를 수 없어,
// 케이스를 비틀지 말고 빼는 쪽을 택했다.
void main() {
  const settings = PrompterSettings(volume: 0.5);

  group('볼륨 (↑/↓)', () {
    test('↑는 볼륨을 올린다', () {
      final next = SongListShortcutService.adjustSettings(
        settings,
        LogicalKeyboardKey.arrowUp,
      );
      expect(next?.volume, closeTo(0.6, 0.001));
    });

    test('↓는 볼륨을 내린다', () {
      final next = SongListShortcutService.adjustSettings(
        settings,
        LogicalKeyboardKey.arrowDown,
      );
      expect(next?.volume, closeTo(0.4, 0.001));
    });

    test('0과 1에서 멈춘다', () {
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
    });
  });

  group('이동 (←/→)', () {
    test('→는 5초 앞으로', () {
      expect(
        SongListShortcutService.seekDeltaFor(LogicalKeyboardKey.arrowRight),
        SongListShortcutService.seekStep,
      );
    });

    test('←는 5초 뒤로', () {
      expect(
        SongListShortcutService.seekDeltaFor(LogicalKeyboardKey.arrowLeft),
        -SongListShortcutService.seekStep,
      );
    });

    test('Shift와 함께면 30초', () {
      expect(
        SongListShortcutService.seekDeltaFor(
          LogicalKeyboardKey.arrowRight,
          shift: true,
        ),
        SongListShortcutService.seekStepLarge,
      );
      expect(
        SongListShortcutService.seekDeltaFor(
          LogicalKeyboardKey.arrowLeft,
          shift: true,
        ),
        -SongListShortcutService.seekStepLarge,
      );
    });

    test('이동 키는 설정을 건드리지 않는다', () {
      expect(
        SongListShortcutService.adjustSettings(
          settings,
          LogicalKeyboardKey.arrowRight,
        ),
        isNull,
      );
      expect(
        SongListShortcutService.adjustSettings(
          settings,
          LogicalKeyboardKey.arrowLeft,
        ),
        isNull,
      );
    });

    test('다른 키는 이동이 아니다', () {
      expect(
        SongListShortcutService.seekDeltaFor(LogicalKeyboardKey.arrowUp),
        isNull,
      );
      expect(
        SongListShortcutService.seekDeltaFor(LogicalKeyboardKey.space),
        isNull,
      );
    });
  });

  test('관계없는 키는 설정을 바꾸지 않는다', () {
    expect(
      SongListShortcutService.adjustSettings(settings, LogicalKeyboardKey.keyA),
      isNull,
    );
  });
}
