import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/services/song_filter_service.dart';
import 'package:singpromfter_app/theme/app_theme.dart';
import 'package:singpromfter_app/widgets/song_search_panel.dart';

void main() {
  testWidgets('SongSearchPanel filters songs from shared list', (tester) async {
    final songs = [
      Song(
        id: '1',
        title: '테스트 곡',
        lyricsPath: 'a.txt',
        lyricsText: '가사',
        backingTracks: const [],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        isFavorite: true,
      ),
      Song(
        id: '2',
        title: '다른 곡',
        lyricsPath: 'b.txt',
        lyricsText: '가사2',
        backingTracks: const [],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ];

    var query = '';
    var mode = SongListFilterMode.all;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: SongSearchPanel(
                songs: songs,
                searchQuery: query,
                filterMode: mode,
                onSearchQueryChanged: (value) => setState(() => query = value),
                onFilterModeChanged: (value) => setState(() => mode = value),
                onStart: (_) {},
                onReserve: (_) {},
                onReserveAll: () {},
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('테스트 곡'), findsOneWidget);
    expect(find.text('다른 곡'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '테스트');
    await tester.pump();

    expect(find.text('테스트 곡'), findsOneWidget);
    expect(find.text('다른 곡'), findsNothing);
  });
}
