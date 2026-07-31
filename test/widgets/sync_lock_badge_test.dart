// file: test/widgets/sync_lock_badge_test.dart
//
// 싱크 잠금(L) 배지 — 잠금일 때만 자물쇠+글자가 보인다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/widgets/sync_lock_badge.dart';

void main() {
  testWidgets('잠금이면 배지, 아니면 아무것도 없다', (tester) async {
    final locked = ValueNotifier(false);
    addTearDown(locked.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SyncLockBadge(locked: locked))),
    );

    expect(find.text('싱크 잠금'), findsNothing);
    expect(find.byIcon(Icons.lock), findsNothing);

    locked.value = true;
    await tester.pump();
    expect(find.text('싱크 잠금'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsOneWidget);

    locked.value = false;
    await tester.pump();
    expect(find.text('싱크 잠금'), findsNothing);
  });
}
