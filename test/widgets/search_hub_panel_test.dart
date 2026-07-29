// file: test/widgets/search_hub_panel_test.dart
//
// 곡 검색 탭 최상위 — [내 곡 | 유튜브] 전환.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/theme/app_theme.dart';
import 'package:singpromfter_app/widgets/search_hub_panel.dart';

void main() {
  testWidgets('선택된 쪽 패널만 보이고, 전환을 알린다', (tester) async {
    SearchSource? changed;
    var source = SearchSource.mySongs;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: SearchHubPanel(
              source: source,
              onSourceChanged: (s) {
                changed = s;
                setState(() => source = s);
              },
              mySongsPanel: const Text('내곡패널'),
              youtubePanel: const Text('유튜브패널'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('내곡패널'), findsOneWidget);
    expect(find.text('유튜브패널'), findsNothing);

    await tester.tap(find.text('유튜브'));
    await tester.pumpAndSettle();

    expect(changed, SearchSource.youtube);
    expect(find.text('유튜브패널'), findsOneWidget);
    expect(find.text('내곡패널'), findsNothing);
  });
}
