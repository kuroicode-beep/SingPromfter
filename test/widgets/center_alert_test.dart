// file: test/widgets/center_alert_test.dart
//
// 큰 글씨 경고 오버레이 — 그대로 진행하면 결과물을 잃는 상황에만 쓴다.
// 토스트와 달리 「멈추는」 알림이라, 읽을 수 있고 닫을 수 있어야 한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/theme/app_theme.dart';
import 'package:singpromfter_app/widgets/center_alert.dart';

Widget _host(void Function(BuildContext) onReady) => MaterialApp(
  theme: AppTheme.dark(),
  home: Scaffold(
    body: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => onReady(context),
        child: const Text('띄우기'),
      ),
    ),
  ),
);

void main() {
  tearDown(CenterAlert.dismiss);

  testWidgets('제목과 설명이 보인다', (tester) async {
    await tester.pumpWidget(
      _host(
        (ctx) => CenterAlert.show(
          ctx,
          title: '녹음 입력에 소리가 없습니다',
          detail: '지금 녹음하면 무음만 저장됩니다.',
        ),
      ),
    );
    await tester.tap(find.text('띄우기'));
    await tester.pump();

    expect(find.text('녹음 입력에 소리가 없습니다'), findsOneWidget);
    expect(find.text('지금 녹음하면 무음만 저장됩니다.'), findsOneWidget);
    CenterAlert.dismiss();
  });

  testWidgets('제목은 저시력에서도 읽히게 크다', (tester) async {
    await tester.pumpWidget(
      _host((ctx) => CenterAlert.show(ctx, title: '경고', detail: '설명')),
    );
    await tester.tap(find.text('띄우기'));
    await tester.pump();

    final title = tester.widget<Text>(find.text('경고'));
    // 토스트 본문(13)과 급이 달라야 한다 — 이건 멈추라는 신호다.
    expect(title.style!.fontSize, greaterThanOrEqualTo(32));
    final detail = tester.widget<Text>(find.text('설명'));
    expect(detail.style!.fontSize, greaterThanOrEqualTo(18));
    CenterAlert.dismiss();
  });

  testWidgets('[확인]으로 닫힌다', (tester) async {
    await tester.pumpWidget(
      _host((ctx) => CenterAlert.show(ctx, title: '경고', detail: '설명')),
    );
    await tester.tap(find.text('띄우기'));
    await tester.pump();
    expect(CenterAlert.isShowing, isTrue);

    await tester.tap(find.text('확인'));
    await tester.pump();

    expect(find.text('경고'), findsNothing);
    expect(CenterAlert.isShowing, isFalse);
  });

  testWidgets('접근성 노드를 만들지 않는다 — 엔진 크래시 회귀 방지', (tester) async {
    // 2026-09-22: 떴다 사라지는 오버레이의 접근성 노드를 Windows 입력 스택이
    // 잡은 채로 노드가 해제돼 Flutter 엔진이 죽었다(get_accState 등).
    // 이 오버레이는 시맨틱스 트리에 아무것도 올리지 않아야 한다.
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host((ctx) => CenterAlert.show(ctx, title: '소리 없음', detail: '장치를 확인하세요')),
    );
    await tester.tap(find.text('띄우기'));
    await tester.pump();

    // 화면에는 보이지만
    expect(find.text('소리 없음'), findsOneWidget);
    // 시맨틱스 트리에는 없다.
    expect(find.bySemanticsLabel('소리 없음'), findsNothing);
    expect(find.bySemanticsLabel('확인'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('장치를 확인')), findsNothing);
    CenterAlert.dismiss();
    handle.dispose();
  });

  testWidgets('새로 띄우면 앞의 것이 겹치지 않는다', (tester) async {
    // 오버레이가 화면을 덮어 버튼을 가리므로(어디를 눌러도 닫히는 설계)
    // 컨텍스트를 붙잡아 두고 직접 두 번 부른다.
    late BuildContext ctx;
    await tester.pumpWidget(_host((c) => ctx = c));
    await tester.tap(find.text('띄우기'));
    await tester.pump();

    CenterAlert.show(ctx, title: '경고 1', detail: '설명');
    await tester.pump();
    CenterAlert.show(ctx, title: '경고 2', detail: '설명');
    await tester.pump();

    expect(find.text('경고 1'), findsNothing);
    expect(find.text('경고 2'), findsOneWidget);
    expect(find.text('설명'), findsOneWidget);
    CenterAlert.dismiss();
  });
}
