// file: test/widgets/sync_lock_badge_test.dart
//
// 싱크 잠금(L) 배지 — 잠금일 때만 자물쇠 아이콘이 보인다.
// 글자는 없다: 가사를 가린다는 피드백으로 아이콘만 남겼다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/widgets/sync_lock_badge.dart';

void main() {
  testWidgets('잠금이면 자물쇠 아이콘, 아니면 아무것도 없다', (tester) async {
    final locked = ValueNotifier(false);
    addTearDown(locked.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SyncLockBadge(locked: locked))),
    );

    expect(find.byIcon(Icons.lock), findsNothing);

    locked.value = true;
    await tester.pump();
    expect(find.byIcon(Icons.lock), findsOneWidget);
    // 가사를 가리던 글자 배지는 사라졌다.
    expect(find.text('싱크 잠금'), findsNothing);

    locked.value = false;
    await tester.pump();
    expect(find.byIcon(Icons.lock), findsNothing);
  });
}
