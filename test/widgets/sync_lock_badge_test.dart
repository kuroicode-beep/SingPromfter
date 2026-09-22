// file: test/widgets/sync_lock_badge_test.dart
//
// 싱크 잠금(L) 배지 — 잠금일 때만 자물쇠 아이콘이 보인다.
// v5.6.0에서 글자를 뺐다. 라벨·툴팁은 남는다(녹음 배지와 같은 규칙).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/widgets/sync_lock_badge.dart';

import '../fakes/semantics_count.dart';

void main() {
  testWidgets('잠금이면 아이콘 배지, 아니면 아무것도 없다', (tester) async {
    final locked = ValueNotifier(false);
    addTearDown(locked.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SyncLockBadge(locked: locked))),
    );

    expect(find.byIcon(Icons.lock), findsNothing);

    locked.value = true;
    await tester.pump();
    expect(find.byIcon(Icons.lock), findsOneWidget);
    expect(find.text('싱크 잠금'), findsNothing);

    locked.value = false;
    await tester.pump();
    expect(find.byIcon(Icons.lock), findsNothing);
  });

  testWidgets('글자를 빼도 스크린리더 라벨과 툴팁은 남는다', (tester) async {
    final locked = ValueNotifier(true);
    addTearDown(locked.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SyncLockBadge(locked: locked))),
    );

    expect(find.bySemanticsLabel('싱크 잠금 중 — L로 해제'), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, '싱크 잠금 중 — L로 해제');
  });

  testWidgets('🔴 잠그고 풀어도 시맨틱스 노드 수가 그대로다 — 라벨만 바뀐다', (tester) async {
    // 생겼다 사라지는 접근성 노드가 엔진 크래시를 냈다(center_alert.dart 머리말).
    // 녹음 배지와 같은 모양의 결함이었다 — 꺼진 배지가 크기 0이면 노드가 통째로 빠진다.
    final handle = tester.ensureSemantics();
    final locked = ValueNotifier(false);
    addTearDown(locked.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SyncLockBadge(locked: locked))),
    );

    final off = countSemanticsNodes(tester);
    locked.value = true;
    await tester.pump();
    final on = countSemanticsNodes(tester);
    locked.value = false;
    await tester.pump();

    // 예전에는 풀린 배지가 크기 0이라 노드가 통째로 빠졌다(4개 ↔ 5개).
    expect(on, off);
    expect(countSemanticsNodes(tester), off);
    handle.dispose();
  });
}
