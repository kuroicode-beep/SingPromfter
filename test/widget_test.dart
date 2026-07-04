import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/widgets/song_tile.dart';

void main() {
  testWidgets('SongTile shows title and action buttons', (tester) async {
    final song = Song(
      id: 'song-1',
      title: '테스트 곡',
      lyricsPath: 'test.txt',
      lyricsText: '가사',
      backingTracks: const [],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      isFavorite: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongTile(
            song: song,
            selected: false,
            onSelect: () {},
            onStart: () {},
            onReserve: () {},
            onEdit: () {},
            onDelete: () {},
            onToggleFavorite: () {},
          ),
        ),
      ),
    );

    expect(find.text('테스트 곡'), findsOneWidget);
    expect(find.text('재생'), findsNothing);
    expect(find.text('시작'), findsOneWidget);
    expect(find.text('예약'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsOneWidget);
  });
}
