// file: test/dialogs/add_track_dialog_test.dart
//
// 반주 추가 다이얼로그 — URL 경로와 노래방 자동 검색 경로의 결과 타입 검증.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/dialogs/add_track_dialog.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/theme/app_theme.dart';

void main() {
  final song = Song(
    id: 's1',
    title: '사랑말',
    artist: '최인경',
    lyricsPath: '',
    lyricsText: '',
    backingTracks: const [],
    createdAt: DateTime(2026, 8, 5),
    updatedAt: DateTime(2026, 8, 5),
  );

  // 결과는 다이얼로그가 닫힌 뒤에 채워진다 — 홀더로 받는다.
  final results = <AddTrackChoice?>[];

  Future<void> open(WidgetTester tester) async {
    results.clear();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  results.add(
                    await AddTrackDialog.show(
                      context,
                      song: song,
                      toolAvailable: true,
                      toolMissingReason: null,
                      separatorStatusLabel: '',
                      separatorOnline: true,
                    ),
                  );
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  testWidgets('자동 검색 버튼은 AddTrackKaraokeSearch(대상 곡)를 돌려준다',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('노래방 반주 자동 검색 (4번 슬롯)'));
    await tester.pumpAndSettle();

    expect(results.single, isA<AddTrackKaraokeSearch>());
    expect((results.single as AddTrackKaraokeSearch).song.id, 's1');
  });

  testWidgets('URL 경로는 여전히 AddTrackFromUrl을 돌려준다', (tester) async {
    await open(tester);
    await tester.enterText(
      find.byType(TextField).first,
      'https://www.youtube.com/watch?v=abc123',
    );
    await tester.tap(find.text('반주 가져오기'));
    await tester.pumpAndSettle();

    expect(results.single, isA<AddTrackFromUrl>());
    final url = results.single as AddTrackFromUrl;
    expect(url.songId, 's1');
    expect(url.url, contains('abc123'));
  });
}
