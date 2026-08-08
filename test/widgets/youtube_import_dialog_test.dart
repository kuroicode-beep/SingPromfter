// file: test/widgets/youtube_import_dialog_test.dart
//
// 가져오기 구성 팝업 — 프리셋 3종, 기본 키, 수동 조절.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/dialogs/youtube_import_dialog.dart';
import 'package:singpromfter_app/theme/app_theme.dart';

void main() {
  YoutubeImportChoice? captured;
  var done = false;

  Future<void> pumpAndOpen(WidgetTester tester) async {
    captured = null;
    done = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                captured = await YoutubeImportDialog.show(
                  context,
                  videoTitle: '선물 - 윤후',
                );
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

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.text('가져오기'));
    await tester.tap(find.text('가져오기'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
  }

  testWidgets('기본값 그대로 확인하면 기본 구성(원곡/MR/MR−2키)', (tester) async {
    await pumpAndOpen(tester);
    await submit(tester);

    expect(captured!.kind, YoutubeImportKind.basic);
    final plan = captured!.plan!;
    expect(plan.makeOriginal, isTrue);
    expect(plan.makeInstrumental, isTrue);
    expect(plan.instrumentalSemitones, 0);
    expect(plan.pitchSemitones, -2);
  });

  testWidgets('남자키는 원곡/MR−5키/MR−7키', (tester) async {
    await pumpAndOpen(tester);
    await tester.tap(find.text('남자키'));
    await tester.pumpAndSettle();
    await submit(tester);

    expect(captured!.kind, YoutubeImportKind.maleKey);
    final plan = captured!.plan!;
    expect(plan.makeOriginal, isTrue);
    expect(plan.instrumentalSemitones, -5);
    expect(plan.pitchSemitones, -7);
  });

  testWidgets('키는 수동으로 조절할 수 있다 — 기본 구성의 −2를 −3으로', (tester) async {
    await pumpAndOpen(tester);
    // 기본 프리셋이 선택돼 있어 스테퍼가 보인다.
    await tester.tap(find.byIcon(Icons.remove).first);
    await tester.pumpAndSettle();
    await submit(tester);

    expect(captured!.plan!.pitchSemitones, -3);
  });

  testWidgets('4번슬롯은 키 프리셋 칩과 수동 조절이 있다', (tester) async {
    await pumpAndOpen(tester);
    await tester.tap(find.textContaining('4번 슬롯'));
    await tester.pumpAndSettle();

    // 원음/−2/−5/−7 칩.
    expect(find.text('원음'), findsOneWidget);
    expect(find.text('5키 낮춤'), findsOneWidget);

    await tester.ensureVisible(find.text('7키 낮춤'));
    await tester.tap(find.text('7키 낮춤'));
    await tester.pumpAndSettle();
    await submit(tester);

    expect(captured!.kind, YoutubeImportKind.karaoke);
    expect(captured!.plan, isNull);
    expect(captured!.karaokeSemitones, -7);
  });

  testWidgets('4번슬롯 기본은 원음(0)', (tester) async {
    await pumpAndOpen(tester);
    await tester.tap(find.textContaining('4번 슬롯'));
    await tester.pumpAndSettle();
    await submit(tester);

    expect(captured!.karaokeSemitones, 0);
  });

  testWidgets('취소하면 null', (tester) async {
    await pumpAndOpen(tester);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(done, isTrue);
    expect(captured, isNull);
  });
}
