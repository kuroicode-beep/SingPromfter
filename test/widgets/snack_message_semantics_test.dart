// file: test/widgets/snack_message_semantics_test.dart
//
// 토스트는 접근성 노드를 만들지 않는다 — 엔진 크래시 회귀 방지.
//
// 2026-09-22: 스페이스·R·녹음 고정을 누를 때마다 토스트가 떴다 지워졌고,
// 그 노드를 Windows 입력 스택(MSAA/UIA)이 잡은 채로 노드가 해제돼
// Flutter 엔진이 죽었다(AXPlatformNodeWin::get_accState 등 덤프 5건).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/widgets/snack_message.dart';

void main() {
  tearDown(SnackMessage.dismiss);

  testWidgets('화면에는 보이지만 시맨틱스 트리에는 없다', (tester) async {
    final handle = tester.ensureSemantics();
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    SnackMessage.show(
      ctx,
      '녹음을 시작했습니다',
      actionLabel: '실행취소',
      onAction: () {},
    );
    await tester.pump();

    expect(find.text('녹음을 시작했습니다'), findsOneWidget);
    expect(find.bySemanticsLabel('녹음을 시작했습니다'), findsNothing);
    expect(find.bySemanticsLabel('실행취소'), findsNothing);

    SnackMessage.dismiss();
    await tester.pump();
    handle.dispose();
  });

  testWidgets('실행 버튼은 여전히 눌린다', (tester) async {
    var pressed = 0;
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    SnackMessage.show(ctx, '취소했습니다', actionLabel: '실행취소', onAction: () => pressed++);
    await tester.pump();

    await tester.tap(find.text('실행취소'));
    await tester.pump();
    expect(pressed, 1);
  });
}
