// file: test/widgets/prompter_line_edit_test.dart
//
// 프롬프터 인라인 가사 수정 — 길게 누르면 그 자리에서 고친다.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/prompter_lines.dart';
import 'package:singpromfter_app/theme/app_theme.dart';
import 'package:singpromfter_app/widgets/prompter_line_list_view.dart';

void main() {
  final lines = buildPrompterLines(
    lyricsText: '첫 줄\n둘째 줄\n셋째 줄',
    timedLyrics: null,
    trackEnd: null,
  );

  Future<void> pump(
    WidgetTester tester, {
    void Function(int, String)? onEditLine,
    LineEditRequest? editRequest,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: PrompterLineListView(
            lines: lines,
            currentIndex: 0,
            fontSize: 24,
            lineHeight: 1.5,
            autoFollow: false,
            onEditLine: onEditLine,
            editRequest: editRequest,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('길게 누르면 그 줄이 입력창으로 바뀐다', (tester) async {
    await pump(tester, onEditLine: (_, _) {});

    await tester.longPress(find.text('둘째 줄'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '둘째 줄',
    );
  });

  testWidgets('고치고 저장하면 줄 번호와 새 텍스트를 알린다', (tester) async {
    int? gotIndex;
    String? gotText;
    await pump(
      tester,
      onEditLine: (index, text) {
        gotIndex = index;
        gotText = text;
      },
    );

    await tester.longPress(find.text('둘째 줄'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '고친 둘째 줄');
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(gotIndex, 1);
    expect(gotText, '고친 둘째 줄');
    expect(find.byType(TextField), findsNothing, reason: '편집기가 닫혀야 한다');
  });

  testWidgets('취소하면 아무것도 알리지 않는다', (tester) async {
    var called = false;
    await pump(tester, onEditLine: (_, _) => called = true);

    await tester.longPress(find.text('첫 줄'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '바꾼 값');
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.text('첫 줄'), findsOneWidget, reason: '원래 텍스트로 돌아온다');
  });

  testWidgets('onEditLine이 없으면 길게 눌러도 아무 일 없다', (tester) async {
    await pump(tester);
    await tester.longPress(find.text('첫 줄'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('편집 요청(단축키 E)이 오면 그 줄이 입력창으로 바뀐다', (tester) async {
    await pump(tester, onEditLine: (_, _) {});
    // seq가 바뀌어야 요청으로 인정된다 — 같은 위젯 재빌드로 전달.
    await pump(
      tester,
      onEditLine: (_, _) {},
      editRequest: const LineEditRequest(seq: 1, index: 2),
    );

    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '셋째 줄',
    );
  });

  testWidgets('ESC를 누르면 저장하고 나온다', (tester) async {
    int? gotIndex;
    String? gotText;
    await pump(
      tester,
      onEditLine: (index, text) {
        gotIndex = index;
        gotText = text;
      },
    );

    await tester.longPress(find.text('첫 줄'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ESC로 저장');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(gotIndex, 0);
    expect(gotText, 'ESC로 저장');
    expect(find.byType(TextField), findsNothing);
  });
}
