import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/prompter_display_mode.dart';
import 'package:singpromfter_app/widgets/prompter_lyrics_view.dart';

void main() {
  testWidgets('PrompterLyricsView highlight mode shows current line larger', (
    tester,
  ) async {
    const lyrics = '첫 줄\n둘째 줄\n셋째 줄';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PrompterLyricsView(
            lyricsText: lyrics,
            displayMode: PrompterDisplayMode.highlight,
            fontSize: 32,
            lineHeight: 1.4,
            highlightLineIndex: 1,
          ),
        ),
      ),
    );

    expect(find.text('둘째 줄'), findsOneWidget);
    expect(find.text('첫 줄'), findsOneWidget);
    expect(find.text('셋째 줄'), findsOneWidget);
  });
}
