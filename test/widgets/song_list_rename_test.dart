// file: test/widgets/song_list_rename_test.dart
//
// 좌측 목록의 제자리 이름 바꾸기 — 폴더 이름과 곡 제목을 더블클릭하면
// 그 자리에 입력칸이 뜨고, Enter로 확정한다.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/services/song_sort_service.dart';
import 'package:singpromfter_app/theme/app_theme.dart';
import 'package:singpromfter_app/widgets/song_list_panel.dart';

Song _song(String id, String title, {String folder = ''}) => Song(
  id: id,
  title: title,
  lyricsPath: '$id.txt',
  lyricsText: '',
  backingTracks: const [],
  createdAt: DateTime(2026, 8, 18),
  updatedAt: DateTime(2026, 8, 18),
  folder: folder,
);

void main() {
  final songs = [_song('a', '가을', folder: '발라드'), _song('b', '나비')];

  Future<void> pump(
    WidgetTester tester, {
    void Function(String, String)? onRenameFolder,
    void Function(Song, String)? onRenameSong,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: SongListPanel(
              songs: songs,
              selectedSong: null,
              selectedTrackSlot: null,
              sortMode: SongSortMode.manual,
              folderOrder: const ['발라드'],
              onRenameFolder: onRenameFolder,
              onRenameSong: onRenameSong,
              onSelectTrack: (_, _) {},
              onSelect: (_) {},
              onStart: (_) {},
              onReserve: (_) {},
              onEdit: (_) {},
              onDelete: (_) {},
              onToggleFavorite: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> doubleTap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('폴더 이름을 더블클릭하면 입력칸이 뜨고 Enter로 확정한다', (tester) async {
    String? gotOld;
    String? gotNew;
    await pump(tester, onRenameFolder: (o, n) {
      gotOld = o;
      gotNew = n;
    });

    expect(find.byType(TextField), findsNothing);
    await doubleTap(tester, find.text('발라드'));
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '느린 노래');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(gotOld, '발라드');
    expect(gotNew, '느린 노래');
    // 확정하면 입력칸은 접힌다.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('곡 제목을 더블클릭하면 그 곡의 새 제목을 알린다', (tester) async {
    Song? gotSong;
    String? gotTitle;
    await pump(tester, onRenameSong: (s, t) {
      gotSong = s;
      gotTitle = t;
    });

    await doubleTap(tester, find.text('나비'));
    await tester.enterText(find.byType(TextField), '  나비 (라이브)  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(gotSong?.id, 'b');
    // 앞뒤 공백은 다듬어서 넘긴다.
    expect(gotTitle, '나비 (라이브)');
  });

  testWidgets('빈 이름이나 그대로면 알리지 않는다', (tester) async {
    var calls = 0;
    await pump(tester, onRenameSong: (_, _) => calls++);

    await doubleTap(tester, find.text('나비'));
    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(calls, 0);

    await doubleTap(tester, find.text('나비'));
    await tester.enterText(find.byType(TextField), '나비');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('콜백이 없으면 더블클릭해도 입력칸이 뜨지 않는다', (tester) async {
    await pump(tester);
    await doubleTap(tester, find.text('나비'));
    expect(find.byType(TextField), findsNothing);
  });
}
