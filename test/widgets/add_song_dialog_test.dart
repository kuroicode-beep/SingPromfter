import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/dialogs/add_song_dialog.dart';
import 'package:singpromfter_app/models/mr_source_mode.dart';
import 'package:singpromfter_app/theme/app_theme.dart';

// 곡 추가의 주 경로(링크 우선)를 고정한다.
void main() {
  setUp(() {
    // 클립보드 자동 채우기가 테스트 입력을 덮어쓰지 않도록 비워 둔다.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') return <String, dynamic>{};
          return null;
        });
  });

  Future<AddSongChoice?> openDialog(
    WidgetTester tester, {
    bool toolAvailable = true,
  }) async {
    AddSongChoice? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await AddSongDialog.show(
                  context,
                  toolAvailable: toolAvailable,
                  toolMissingReason: toolAvailable ? null : 'yt-dlp 없음',
                  separatorStatusLabel: '분리 서버: 온라인 (GPU)',
                  separatorOnline: true,
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('링크 입력이 주 경로로 먼저 보인다', (tester) async {
    await openDialog(tester);

    expect(find.text('곡 추가'), findsOneWidget);
    expect(find.text('유튜브 링크'), findsOneWidget);
    expect(find.text('가져와서 추가'), findsOneWidget);
    // 파일 등록은 보조 경로로 남아 있다
    expect(find.text('파일로 직접 추가'), findsOneWidget);
  });

  testWidgets('유튜브가 아닌 주소는 막고 안내한다', (tester) async {
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'https://vimeo.com/123');
    await tester.tap(find.text('가져와서 추가'));
    await tester.pumpAndSettle();

    expect(find.textContaining('유튜브 주소가 아닙니다'), findsOneWidget);
  });

  testWidgets('빈 입력도 막는다', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('가져와서 추가'));
    await tester.pumpAndSettle();

    expect(find.textContaining('붙여넣어'), findsOneWidget);
  });

  testWidgets('링크를 넣으면 기본값(반주 그대로 + 가사 자동)으로 돌려준다', (tester) async {
    AddSongChoice? captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                captured = await AddSongDialog.show(
                  context,
                  toolAvailable: true,
                  toolMissingReason: null,
                  separatorStatusLabel: '분리 서버: 온라인 (GPU)',
                  separatorOnline: true,
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'https://www.youtube.com/watch?v=abc',
    );
    await tester.tap(find.text('가져와서 추가'));
    await tester.pumpAndSettle();

    expect(captured, isA<AddSongFromUrl>());
    final choice = captured! as AddSongFromUrl;
    expect(choice.url, 'https://www.youtube.com/watch?v=abc');
    expect(choice.mode, MrSourceMode.asIs);
    expect(choice.fetchLyrics, isTrue);
  });

  testWidgets('파일로 직접 추가는 보조 경로 결과를 준다', (tester) async {
    AddSongChoice? captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                captured = await AddSongDialog.show(
                  context,
                  toolAvailable: true,
                  toolMissingReason: null,
                  separatorStatusLabel: '분리 서버: 꺼짐',
                  separatorOnline: false,
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    // 대화상자 내용이 스크롤되므로 보이게 한 뒤 누른다.
    await tester.ensureVisible(find.text('파일로 직접 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('파일로 직접 추가'));
    await tester.pumpAndSettle();

    expect(captured, isA<AddSongFromFiles>());
  });

  testWidgets('yt-dlp가 없으면 가져오기를 막고 이유를 보여준다', (tester) async {
    await openDialog(tester, toolAvailable: false);

    expect(find.text('yt-dlp 없음'), findsOneWidget);

    // 눌러도 아무 일이 없어야 한다 — 대화상자가 그대로 열려 있다.
    await tester.tap(find.text('가져와서 추가'));
    await tester.pumpAndSettle();
    expect(find.text('곡 추가'), findsOneWidget);

    // 링크 입력도 막혀 있다.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
  });
}
