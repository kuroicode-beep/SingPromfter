// file: test/widgets/pick_song_dialog_test.dart
//
// 4번 슬롯 대상 곡 선택 — 필터, 사용 중 배지, 덮어쓰기 확인.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/dialogs/pick_song_dialog.dart';
import 'package:singpromfter_app/models/backing_track.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/theme/app_theme.dart';

Song _song(String id, String title, {bool withKaraoke = false}) => Song(
  id: id,
  title: title,
  artist: '가수',
  lyricsPath: '$id.txt',
  lyricsText: '가사',
  backingTracks: [
    BackingTrack(slot: 1, fileName: '$id.mp3', label: '원곡'),
    if (withKaraoke)
      BackingTrack(slot: 4, fileName: '${id}_k.mp3', label: '노래방'),
  ],
  createdAt: DateTime(2026, 7, 30),
  updatedAt: DateTime(2026, 7, 30),
);

void main() {
  // 다이얼로그 반환값을 붙잡는 하네스. picked()는 닫힌 뒤에만 부른다.
  Song? picked;
  var done = false;

  Future<void> pumpAndOpen(WidgetTester tester, List<Song> songs) async {
    picked = null;
    done = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                picked = await PickSongDialog.show(context, songs: songs);
                done = true;
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  Song? result() {
    expect(done, isTrue, reason: '다이얼로그가 아직 안 닫혔다');
    return picked;
  }

  testWidgets('곡을 고르면 그 곡을 돌려준다', (tester) async {
    await pumpAndOpen(tester, [_song('a', '선물'), _song('b', '봄이 와도')]);

    await tester.tap(find.text('선물'));
    await tester.pumpAndSettle();

    expect(result()?.id, 'a');
  });

  testWidgets('검색어로 목록을 거른다', (tester) async {
    await pumpAndOpen(tester, [_song('a', '선물'), _song('b', '봄이 와도')]);

    await tester.enterText(find.byType(TextField), '봄');
    await tester.pumpAndSettle();

    expect(find.text('선물'), findsNothing);
    expect(find.text('봄이 와도'), findsOneWidget);
  });

  testWidgets('4번 슬롯이 있는 곡은 "4번 사용 중" 배지가 붙는다', (tester) async {
    await pumpAndOpen(tester, [
      _song('a', '선물', withKaraoke: true),
      _song('b', '봄이 와도'),
    ]);

    expect(find.textContaining('4번 사용 중'), findsOneWidget);
  });

  testWidgets('4번 점유 곡은 덮어쓰기 확인을 거쳐야 반환된다', (tester) async {
    await pumpAndOpen(tester, [_song('a', '선물', withKaraoke: true)]);

    await tester.tap(find.text('선물'));
    await tester.pumpAndSettle();

    // 확인 다이얼로그가 떠 있고 아직 안 닫혔다.
    expect(find.text('4번 슬롯 덮어쓰기'), findsOneWidget);

    await tester.tap(find.text('덮어쓰기'));
    await tester.pumpAndSettle();

    expect(result()?.id, 'a');
  });

  testWidgets('덮어쓰기를 취소하면 다이얼로그가 유지된다', (tester) async {
    await pumpAndOpen(tester, [_song('a', '선물', withKaraoke: true)]);

    await tester.tap(find.text('선물'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소').last);
    await tester.pumpAndSettle();

    // 곡 선택 다이얼로그는 아직 열려 있다.
    expect(find.text('어느 곡에 붙일까요?'), findsOneWidget);
  });

  testWidgets('취소하면 null', (tester) async {
    await pumpAndOpen(tester, [_song('a', '선물')]);

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(result(), isNull);
  });
}
