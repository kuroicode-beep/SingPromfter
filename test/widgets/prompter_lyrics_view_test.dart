import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/prompter_display_mode.dart';
import 'package:singpromfter_app/models/timed_lyrics.dart';
import 'package:singpromfter_app/theme/app_theme.dart';
import 'package:singpromfter_app/widgets/prompter_lyrics_view.dart';

// 무대 가사 — 줄 목록·현재 줄 표시(▶ + 오렌지)·줄 클릭.
void main() {
  const lyrics = '첫 줄\n둘째 줄\n셋째 줄\n넷째 줄';

  Widget wrap({
    PrompterDisplayMode mode = PrompterDisplayMode.full,
    int index = 1,
    ValueChanged<int>? onLineTap,
    TimedLyrics? timed,
  }) => MaterialApp(
    home: Scaffold(
      body: PrompterLyricsView(
        lyricsText: lyrics,
        timedLyrics: timed,
        displayMode: mode,
        fontSize: 32,
        lineHeight: 1.4,
        highlightLineIndex: index,
        onLineTap: onLineTap,
        autoFollow: false,
      ),
    ),
  );

  TextStyle styleOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!;

  group('줄 목록 모드', () {
    testWidgets('모든 줄을 그린다', (tester) async {
      await tester.pumpWidget(wrap());
      expect(find.text('첫 줄'), findsOneWidget);
      expect(find.text('둘째 줄'), findsOneWidget);
      expect(find.text('셋째 줄'), findsOneWidget);
      expect(find.text('넷째 줄'), findsOneWidget);
    });

    testWidgets('현재 줄에만 ▶ 마커가 붙는다', (tester) async {
      await tester.pumpWidget(wrap());
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('현재 줄은 오렌지, 나머지는 아니다', (tester) async {
      await tester.pumpWidget(wrap());
      expect(styleOf(tester, '둘째 줄').color, AppColors.tertiary);
      expect(styleOf(tester, '첫 줄').color, isNot(AppColors.tertiary));
    });

    testWidgets('현재 줄이 더 크다 — 색만으로 구분하지 않는다', (tester) async {
      await tester.pumpWidget(wrap());
      final current = styleOf(tester, '둘째 줄').fontSize!;
      final other = styleOf(tester, '첫 줄').fontSize!;
      expect(current, greaterThan(other));
    });

    testWidgets('현재 줄에만 밑줄과 배경 띠가 붙는다', (tester) async {
      await tester.pumpWidget(wrap());

      // 강조 장식을 가진 Container가 정확히 하나여야 한다.
      final decorated = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) {
            final d = c.decoration;
            return d is BoxDecoration &&
                d.border?.bottom.color == AppColors.tertiary &&
                d.border!.bottom.width >= 3;
          });
      expect(decorated, hasLength(1));
    });

    testWidgets('화살표가 글자 크기만큼 크다 — 멀리서도 보이게', (tester) async {
      await tester.pumpWidget(wrap());
      final icon = tester.widget<Icon>(
        find.byIcon(Icons.play_arrow_rounded),
      );
      // v2.6.0에서는 0.62배라 작았다.
      expect(icon.size, greaterThanOrEqualTo(32 * 0.9));
    });

    testWidgets('줄을 누르면 그 인덱스를 준다', (tester) async {
      int? tapped;
      await tester.pumpWidget(wrap(onLineTap: (i) => tapped = i));
      await tester.tap(find.text('넷째 줄'));
      await tester.pump();
      expect(tapped, 3);
    });

    testWidgets('onLineTap이 없으면 눌러도 예외가 없다', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.tap(find.text('셋째 줄'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('싱크 가사가 있으면 그 줄 목록을 그린다', (tester) async {
      await tester.pumpWidget(
        wrap(
          timed: const TimedLyrics(
            lines: [
              TimedLyricLine(time: Duration.zero, text: '싱크 A'),
              TimedLyricLine(time: Duration(seconds: 3), text: '싱크 B'),
            ],
          ),
        ),
      );
      expect(find.text('싱크 A'), findsOneWidget);
      expect(find.text('싱크 B'), findsOneWidget);
      expect(find.text('첫 줄'), findsNothing);
    });

    testWidgets('범위 밖 인덱스여도 깨지지 않는다', (tester) async {
      await tester.pumpWidget(wrap(index: 99));
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });
  });

  group('3줄 집중 모드', () {
    testWidgets('앞·현재·뒤 세 줄만 보인다', (tester) async {
      await tester.pumpWidget(wrap(mode: PrompterDisplayMode.highlight));
      expect(find.text('첫 줄'), findsOneWidget);
      expect(find.text('둘째 줄'), findsOneWidget);
      expect(find.text('셋째 줄'), findsOneWidget);
      expect(find.text('넷째 줄'), findsNothing);
    });

    testWidgets('현재 줄에 ▶ + 오렌지', (tester) async {
      await tester.pumpWidget(wrap(mode: PrompterDisplayMode.highlight));
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(styleOf(tester, '둘째 줄').color, AppColors.tertiary);
    });
  });
}
