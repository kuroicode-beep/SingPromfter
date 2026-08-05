// file: test/widgets/prompter_space_background_test.dart
//
// 우주 배경 — 별밭 생성 규칙과 위젯 온/오프.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/widgets/prompter_space_background.dart';

void main() {
  group('generateStars', () {
    test('개수·범위·시드 재현성', () {
      final a = generateStars(110);
      final b = generateStars(110);
      expect(a.length, 110);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].x, inInclusiveRange(0, 1));
        expect(a[i].y, inInclusiveRange(0, 1));
        expect(a[i].size, inInclusiveRange(0.5, 2.0));
        expect(a[i].tone, inInclusiveRange(0, 2));
        // 같은 시드면 같은 하늘 — 프레임마다 별이 튀지 않는 근거.
        expect(a[i].x, b[i].x);
        expect(a[i].twinklePhase, b[i].twinklePhase);
      }
    });

    test('대부분은 백색, 일부만 청·앰버 톤', () {
      final stars = generateStars(500, seed: 3);
      final white = stars.where((s) => s.tone == 0).length;
      expect(white, greaterThan(300));
    });
  });

  testWidgets('꺼져 있으면 아무것도 그리지 않는다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PrompterSpaceBackground(enabled: false)),
      ),
    );
    // 프레임워크 내부 CustomPaint와 섞이지 않게 배경 위젯 하위로만 본다.
    expect(
      find.descendant(
        of: find.byType(PrompterSpaceBackground),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
  });

  testWidgets('켜져 있으면 CustomPaint가 그려지고 몇 프레임을 버틴다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PrompterSpaceBackground(enabled: true)),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(PrompterSpaceBackground),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  });
}
