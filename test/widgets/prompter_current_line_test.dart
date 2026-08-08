import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/theme/app_theme.dart';
import 'package:singpromfter_app/widgets/prompter_current_line.dart';

// 무대 가사 한 줄의 강조 규칙 — 목록 모드와 3줄 창이 공유하는 단일 소유자.
void main() {
  TextStyle current({bool bold = false}) => prompterLineStyle(
    fontSize: 32,
    lineHeight: 1.4,
    boldText: bold,
    isCurrent: true,
    mutedColor: Colors.white70,
  );

  group('prompterLineStyle', () {
    test('현재 줄은 오렌지 + 그림자 2겹', () {
      final style = current();
      expect(style.color, AppColors.tertiary);
      expect(style.shadows, hasLength(2));
      expect(style.fontWeight, FontWeight.w700);
    });

    test('굵게 설정이면 한 단계 더 굵어진다', () {
      expect(current(bold: true).fontWeight, FontWeight.w800);
    });

    test('현재 줄이 아니면 그림자가 없다 — 강조는 현재 줄만', () {
      final style = prompterLineStyle(
        fontSize: 32,
        lineHeight: 1.4,
        boldText: false,
        isCurrent: false,
        mutedColor: Colors.white70,
      );
      expect(style.shadows, isNull);
      expect(style.color, Colors.white70);
      expect(style.fontWeight, FontWeight.w500);
    });

    test('글꼴 미지정이면 고가독 고딕으로 폴백한다', () {
      expect(current().fontFamily, AppFonts.legible);
    });

    test('글꼴을 주면 그대로 쓴다', () {
      final style = prompterLineStyle(
        fontSize: 32,
        lineHeight: 1.4,
        boldText: false,
        isCurrent: true,
        mutedColor: Colors.white70,
        fontFamily: 'Consolas',
      );
      expect(style.fontFamily, 'Consolas');
    });
  });

  group('prompterUnsungStyle', () {
    // 이게 깨지면 스윕이 걸리는 순간 글자 위치가 어긋나 줄이 튄다.
    test('글자 metrics를 하나도 바꾸지 않는다', () {
      final base = current();
      final unsung = prompterUnsungStyle(base);

      expect(unsung.fontSize, base.fontSize);
      expect(unsung.height, base.height);
      expect(unsung.fontFamily, base.fontFamily);
      expect(unsung.fontWeight, base.fontWeight);
      expect(unsung.letterSpacing, base.letterSpacing);
      expect(unsung.wordSpacing, base.wordSpacing);
      expect(unsung.textBaseline, base.textBaseline);
      expect(unsung.fontStyle, base.fontStyle);
    });

    test('색은 흐려지고 그림자는 빠진다', () {
      final base = current();
      final unsung = prompterUnsungStyle(base);

      expect(unsung.color!.a, lessThan(base.color!.a));
      expect(unsung.shadows, isEmpty);
    });
  });

  group('PrompterCurrentLine', () {
    Widget wrap({
      bool isCurrent = true,
      bool fillWidth = true,
      VoidCallback? onTap,
      Widget Function(TextStyle)? sweepBuilder,
    }) => MaterialApp(
      home: Scaffold(
        body: PrompterCurrentLine(
          text: '한 줄',
          isCurrent: isCurrent,
          fontSize: 32,
          mutedScale: listMutedScale,
          lineHeight: 1.4,
          boldText: false,
          mutedColor: Colors.white70,
          fillWidth: fillWidth,
          onTap: onTap,
          sweepBuilder: sweepBuilder,
        ),
      ),
    );

    testWidgets('현재 줄에는 화살표가 붙는다', (tester) async {
      await tester.pumpWidget(wrap());
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('현재 줄이 아니면 화살표가 없다', (tester) async {
      await tester.pumpWidget(wrap(isCurrent: false));
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    });

    testWidgets('현재 줄이 아니면 축소된다', (tester) async {
      await tester.pumpWidget(wrap(isCurrent: false));
      final style = tester.widget<Text>(find.text('한 줄')).style!;
      expect(style.fontSize, closeTo(32 * listMutedScale, 0.001));
    });

    // "싱크가 어긋날 때 위·아래 줄을 봐야 한다"는 요청으로 v2.11.0에서 한 단계
    // 키웠다. 기준 56pt에서 약 +2pt — 그보다 작으면 요청을 되돌린 것이다.
    test('축소 배율은 기준 56pt에서 최소 2pt를 벌어 준다', () {
      const base = 56.0;
      expect(base * listMutedScale, greaterThanOrEqualTo(base * 0.72 + 2));
      expect(base * windowMutedScale, greaterThanOrEqualTo(base * 0.82 + 2));
      // 현재 줄과 구분은 남아야 한다 — 같아지면 어느 줄인지 알 수 없다.
      expect(windowMutedScale, lessThan(1.0));
      expect(listMutedScale, lessThan(windowMutedScale));
    });

    // 아직 부르지 않은 부분의 밝기. 요청으로 0.62 → 0.70.
    test('스윕 미도달 부분은 밝지만 경계는 남는다', () {
      expect(unsungOpacity, greaterThanOrEqualTo(0.70));
      expect(unsungOpacity, lessThan(0.85));
    });

    testWidgets('누를 수 없어도 시맨틱은 붙는다 — 현재 줄임을 알려야 한다', (tester) async {
      await tester.pumpWidget(wrap());
      final semantics = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byType(PrompterCurrentLine),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(semantics.properties.label, '현재 줄: 한 줄');
      expect(semantics.properties.selected, isTrue);
      expect(semantics.properties.button, isFalse);
    });

    testWidgets('누를 수 있으면 button으로 알린다', (tester) async {
      await tester.pumpWidget(wrap(onTap: () {}));
      final semantics = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byType(PrompterCurrentLine),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(semantics.properties.button, isTrue);
    });

    testWidgets('sweepBuilder가 있으면 현재 줄만 그걸로 그린다', (tester) async {
      await tester.pumpWidget(
        wrap(sweepBuilder: (_) => const Text('스윕')),
      );
      expect(find.text('스윕'), findsOneWidget);
      expect(find.text('한 줄'), findsNothing);
    });

    testWidgets('현재 줄이 아니면 sweepBuilder를 쓰지 않는다', (tester) async {
      await tester.pumpWidget(
        wrap(isCurrent: false, sweepBuilder: (_) => const Text('스윕')),
      );
      expect(find.text('스윕'), findsNothing);
      expect(find.text('한 줄'), findsOneWidget);
    });
  });
}
