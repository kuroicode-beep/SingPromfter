import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/dialogs/add_song_dialog.dart';
import 'package:singpromfter_app/models/mr_source_mode.dart';
import 'package:singpromfter_app/theme/app_theme.dart';

// 곡 추가는 유튜브 링크 경로 하나뿐이다 — 파일 직접 등록 경로는 v2.2.0에서 제거됐다.
void main() {
  setUp(() {
    // 클립보드 자동 채우기가 테스트 입력을 덮어쓰지 않도록 비워 둔다.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') return <String, dynamic>{};
          return null;
        });
  });

  Future<AddSongFromUrl?> openDialog(
    WidgetTester tester, {
    bool toolAvailable = true,
    bool separatorOnline = true,
  }) async {
    AddSongFromUrl? result;
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
                  separatorStatusLabel: separatorOnline
                      ? '분리 서버: 온라인 (GPU)'
                      : '분리 서버: 꺼짐',
                  separatorOnline: separatorOnline,
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

  testWidgets('링크 입력이 유일한 경로로 보인다', (tester) async {
    await openDialog(tester);

    expect(find.text('곡 추가'), findsOneWidget);
    expect(find.text('유튜브 링크'), findsOneWidget);
    expect(find.text('가져와서 추가'), findsOneWidget);
    // 파일 직접 등록 경로는 완전히 제거됐다
    expect(find.text('파일로 직접 추가'), findsNothing);
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

  testWidgets('링크를 넣으면 기본 3슬롯 구성(원곡+MR+키조절)으로 돌려준다', (tester) async {
    AddSongFromUrl? captured;
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

    expect(captured, isNotNull);
    expect(captured!.url, 'https://www.youtube.com/watch?v=abc');
    // 3슬롯 구성이 기본이 되려면 보컬 분리가 기본이어야 한다.
    expect(captured!.mode, MrSourceMode.aiSeparate);
    expect(captured!.fetchLyrics, isTrue);
    expect(captured!.plan.makeOriginal, isTrue);
    expect(captured!.plan.makeInstrumental, isTrue);
    expect(captured!.plan.pitchSemitones, -2);
  });

  testWidgets('반주 처리를 그대로로 바꾸면 MR 슬롯은 만들지 않는다', (tester) async {
    AddSongFromUrl? captured;
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

    await tester.enterText(find.byType(TextField), 'https://youtu.be/abc');
    await tester.ensureVisible(find.text(MrSourceMode.asIs.label));
    await tester.tap(find.text(MrSourceMode.asIs.label));
    await tester.pumpAndSettle();
    await tester.tap(find.text('가져와서 추가'));
    await tester.pumpAndSettle();

    expect(captured!.mode, MrSourceMode.asIs);
    expect(captured!.plan.makeInstrumental, isFalse);
  });

  testWidgets('키조절본을 끄면 계획에서 빠진다', (tester) async {
    AddSongFromUrl? captured;
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

    await tester.enterText(find.byType(TextField), 'https://youtu.be/abc');
    await tester.ensureVisible(find.text('키조절본 (MR 기준)'));
    await tester.tap(find.text('키조절본 (MR 기준)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('가져와서 추가'));
    await tester.pumpAndSettle();

    expect(captured!.plan.pitchSemitones, isNull);
    expect(captured!.plan.wantsPitch, isFalse);
  });

  testWidgets('보컬 분리를 고르면 서버가 꺼져 있을 때 안내한다', (tester) async {
    await openDialog(tester, separatorOnline: false);

    await tester.ensureVisible(find.text(MrSourceMode.aiSeparate.label));
    await tester.tap(find.text(MrSourceMode.aiSeparate.label));
    await tester.pumpAndSettle();

    expect(find.textContaining('보컬 분리 서버를 먼저 켜'), findsOneWidget);
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
