// file: test/widgets/song_list_panel_test.dart
//
// 곡 목록 드래그 재정렬 — 손잡이가 있고, 끌면 보이는 순서·인덱스를 알린다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/services/song_sort_service.dart';
import 'package:singpromfter_app/theme/app_theme.dart';
import 'package:singpromfter_app/widgets/song_list_panel.dart';

Song _song(String id, String title) => Song(
  id: id,
  title: title,
  lyricsPath: '$id.txt',
  lyricsText: '',
  backingTracks: const [],
  createdAt: DateTime(2026, 7, 30),
  updatedAt: DateTime(2026, 7, 30),
);

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required List<Song> songs,
    void Function(List<String>, int, int)? onReorder,
    SongSortMode sortMode = SongSortMode.manual,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: SongListPanel(
              songs: songs,
              selectedSong: null,
              selectedTrackSlot: null,
              sortMode: sortMode,
              onReorder: onReorder,
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

  final songs = [_song('a', '가을'), _song('b', '나비'), _song('c', '다리')];

  testWidgets('onReorder가 있으면 줄마다 드래그 손잡이가 붙는다', (tester) async {
    await pump(tester, songs: songs, onReorder: (_, _, _) {});
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(3));
  });

  testWidgets('onReorder가 없으면 손잡이도 없다', (tester) async {
    await pump(tester, songs: songs);
    expect(find.byIcon(Icons.drag_handle), findsNothing);
  });

  testWidgets('손잡이를 끌면 보이는 id 순서와 인덱스를 알린다', (tester) async {
    List<String>? gotIds;
    int? gotOld;
    int? gotNew;
    await pump(
      tester,
      songs: songs,
      onReorder: (ids, oldIndex, newIndex) {
        gotIds = ids;
        gotOld = oldIndex;
        gotNew = newIndex;
      },
    );

    // 첫 곡의 손잡이를 아래로 끌어 둘째 자리로. 재정렬은 드래그 중 프레임이
    // 흘러야 시작되므로 제스처를 단계별로 나눠 pump한다.
    final firstHandle = find.byIcon(Icons.drag_handle).first;
    final secondHandle = find.byIcon(Icons.drag_handle).at(1);
    final delta =
        tester.getCenter(secondHandle) - tester.getCenter(firstHandle);
    final gesture = await tester.startGesture(tester.getCenter(firstHandle));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(delta);
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(gotIds, ['a', 'b', 'c'], reason: '정렬 적용된 보이는 순서 그대로');
    expect(gotOld, 0);
    expect(gotNew, isNotNull);
    expect(gotNew, greaterThan(0), reason: '아래로 이동했다');
  });

  testWidgets('제목순 정렬이어도 손잡이는 보인다 — 끌면 호출부가 내 순서로 전환한다', (
    tester,
  ) async {
    await pump(
      tester,
      songs: songs,
      sortMode: SongSortMode.title,
      onReorder: (_, _, _) {},
    );
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(3));
  });
}
