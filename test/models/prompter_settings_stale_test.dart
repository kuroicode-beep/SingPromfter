import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/prompter_settings.dart';

// PrompterNavigation의 스테일 클로저 회귀 가드.
//
// 콜백이 라우트를 연 시점의 settings를 캡처하면, 글자 크기를 바꾼 뒤
// 줄 간격을 바꿀 때 옛 스냅샷 위에 copyWith가 얹혀 크기가 조용히 되돌아간다.
// Ctrl+휠은 이 경로를 연달아 타므로 특히 치명적이다.
void main() {
  test('스냅샷을 캡처하면 앞선 변경이 사라진다 — 이 방식은 쓰면 안 된다', () {
    const captured = PrompterSettings(fontSizeLevel: 3, lineHeightLevel: 2);
    var current = captured;

    // 잘못된 방식: 두 콜백이 모두 captured를 기준으로 만든다.
    current = captured.copyWith(fontSizeLevel: 6);
    current = captured.copyWith(lineHeightLevel: 4);

    expect(current.lineHeightLevel, 4);
    expect(current.fontSizeLevel, 3, reason: '크기 변경이 사라진다(= 버그 재현)');
  });

  test('provider로 최신 값을 읽으면 두 변경이 모두 남는다', () {
    var current = const PrompterSettings(fontSizeLevel: 3, lineHeightLevel: 2);
    PrompterSettings read() => current;

    void update(PrompterSettings Function(PrompterSettings s) change) {
      current = change(read());
    }

    update((s) => s.copyWith(fontSizeLevel: 6));
    update((s) => s.copyWith(lineHeightLevel: 4));

    expect(current.fontSizeLevel, 6);
    expect(current.lineHeightLevel, 4);
  });

  test('연속 크기 변경(Ctrl+휠)도 누적된다', () {
    var current = const PrompterSettings(fontSizeLevel: 3);
    PrompterSettings read() => current;

    for (var i = 0; i < 4; i++) {
      current = read().copyWith(fontSizeLevel: read().fontSizeLevel + 1);
    }
    expect(current.fontSizeLevel, 7);
  });
}
