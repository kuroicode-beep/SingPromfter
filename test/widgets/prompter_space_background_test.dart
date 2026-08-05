// file: test/widgets/prompter_space_background_test.dart
//
// 우주 배경 — 단계 순환 규칙·별밭 생성·위젯 온/오프.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/widgets/prompter_space_background.dart';

void main() {
  group('nextSpaceBackgroundLevel', () {
    test('1→2→3→4→5→끄기→1 순환', () {
      expect(nextSpaceBackgroundLevel(1), 2);
      expect(nextSpaceBackgroundLevel(4), 5);
      expect(nextSpaceBackgroundLevel(5), 0);
      expect(nextSpaceBackgroundLevel(0), 1);
    });

    test('단계 이름이 전부 있다', () {
      for (var level = 0; level <= spaceBackgroundMaxLevel; level++) {
        expect(spaceBackgroundLevelLabel(level), isNotEmpty);
      }
      expect(spaceBackgroundLevelLabel(0), contains('끄기'));
      expect(spaceBackgroundLevelLabel(5), contains('스톰'));
    });
  });

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

  testWidgets('0단계(끄기)면 아무것도 그리지 않는다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PrompterSpaceBackground(level: 0)),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(PrompterSpaceBackground),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
  });

  testWidgets('1~5단계 전부 CustomPaint가 그려지고 몇 프레임을 버틴다', (tester) async {
    for (var level = 1; level <= spaceBackgroundMaxLevel; level++) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PrompterSpaceBackground(level: level)),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(PrompterSpaceBackground),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
        reason: '$level단계',
      );
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 80));
    }
    // 마지막에 꺼서 Ticker를 정리한다.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PrompterSpaceBackground(level: 0)),
      ),
    );
  });
}
