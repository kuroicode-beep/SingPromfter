// file: test/widgets/sync_pull_dialog_test.dart
//
// 폰의 [PC에서 곡 받기] 다이얼로그. 반주가 크면 몇 분씩 걸려서 진행률이
// 안 움직이면 사용자가 멈춘 줄 안다 — 숫자와 파일명이 실제로 갱신되는지가
// 이 화면의 핵심이다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/theme/app_theme.dart';
import 'package:singpromfter_app/widgets/sync_section.dart';

typedef ProgressSink = void Function(int done, int total, String? current);

Widget _host({
  required Future<String> Function(String, String, ProgressSink) onPull,
  String initialAddress = '192.168.0.5:8772',
}) => MaterialApp(
  theme: AppTheme.dark(),
  home: Scaffold(
    body: SyncPullDialog(initialAddress: initialAddress, onPull: onPull),
  ),
);

void main() {
  testWidgets('처음에는 진행률이 없고 [지금 동기화]가 눌린다', (tester) async {
    await tester.pumpWidget(
      _host(onPull: (_, _, _) async => '이미 최신입니다 — 곡 3개'),
    );

    expect(find.text('지금 동기화'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('받는 동안 개수와 파일명이 갱신된다', (tester) async {
    final gate = Completer<String>();
    late ProgressSink sink;

    await tester.pumpWidget(
      _host(
        onPull: (_, _, onProgress) {
          sink = onProgress;
          return gate.future;
        },
      ),
    );

    await tester.tap(find.text('지금 동기화'));
    await tester.pump();

    // 목록을 받는 동안에는 전체 개수를 모른다 — 불확정 막대.
    expect(find.text('곡 목록을 받는 중…'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, isNull);

    sink(2, 10, '밤편지_mr1.mp3');
    await tester.pump();

    expect(find.text('반주 받는 중 2 / 10'), findsOneWidget);
    expect(find.text('밤편지_mr1.mp3'), findsOneWidget);
    final bar2 = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar2.value, closeTo(0.2, 0.001));

    gate.complete('곡 3개 · 반주 10개 받음');
    await tester.pumpAndSettle();

    // 끝나면 진행률은 사라지고 결과만 남는다.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('곡 3개 · 반주 10개 받음'), findsOneWidget);
    expect(find.text('밤편지_mr1.mp3'), findsNothing);
  });

  testWidgets('받는 동안에는 버튼을 다시 누를 수 없다 — 중복 실행 방지', (tester) async {
    final gate = Completer<String>();
    var calls = 0;

    await tester.pumpWidget(
      _host(
        onPull: (_, _, _) {
          calls++;
          return gate.future;
        },
      ),
    );

    await tester.tap(find.text('지금 동기화'));
    await tester.pump();
    await tester.tap(find.text('지금 동기화'), warnIfMissed: false);
    await tester.pump();

    expect(calls, 1);

    gate.complete('완료');
    await tester.pumpAndSettle();
  });

  testWidgets('저장해 둔 PC 주소가 미리 채워진다', (tester) async {
    await tester.pumpWidget(
      _host(
        onPull: (_, _, _) async => '',
        initialAddress: '10.0.0.7:8772',
      ),
    );

    expect(find.text('10.0.0.7:8772'), findsOneWidget);
  });
}
