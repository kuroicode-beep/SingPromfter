// file: test/widgets/recording_badge_test.dart
//
// 녹음 중(R) 배지 — 녹음 중일 때만 ● 아이콘이 보인다.
// v5.6.0에서 글자를 뺐다(가사 가림 최소화). 대신 스크린리더 라벨과
// 호버 안내가 남아 있어야 한다 — 인지 수단이 아이콘 하나로 줄면 안 된다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/widgets/recording_badge.dart';

import '../fakes/semantics_count.dart';

void main() {
  testWidgets('녹음 중이면 아이콘 배지, 아니면 아무것도 없다', (tester) async {
    final recording = ValueNotifier(false);
    addTearDown(recording.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: RecordingBadge(recording: recording))),
    );

    expect(find.byIcon(Icons.fiber_manual_record), findsNothing);

    recording.value = true;
    await tester.pump();
    expect(find.byIcon(Icons.fiber_manual_record), findsOneWidget);
    // 글자는 사라졌다 — 이게 이번 변경의 목적이다.
    expect(find.text('녹음 중'), findsNothing);

    recording.value = false;
    await tester.pump();
    expect(find.byIcon(Icons.fiber_manual_record), findsNothing);
  });

  testWidgets('글자를 빼도 스크린리더 라벨과 툴팁은 남는다', (tester) async {
    final recording = ValueNotifier(true);
    addTearDown(recording.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: RecordingBadge(recording: recording))),
    );

    // 고정 모드에서는 스페이스가 조각을 끝낸다 — R만 적혀 있으면 틀린 안내다.
    expect(find.bySemanticsLabel('녹음 중 — R 또는 스페이스로 중지'), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, '녹음 중 — R 또는 스페이스로 중지');
  });

  testWidgets('🔴 켜지고 꺼져도 시맨틱스 노드 수가 그대로다 — 라벨만 바뀐다', (tester) async {
    // 생겼다 사라지는 접근성 노드가 엔진 크래시를 냈다(center_alert.dart 머리말).
    final handle = tester.ensureSemantics();
    final recording = ValueNotifier(false);
    addTearDown(recording.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: RecordingBadge(recording: recording))),
    );

    final off = countSemanticsNodes(tester);
    recording.value = true;
    await tester.pump();
    final on = countSemanticsNodes(tester);
    recording.value = false;
    await tester.pump();

    // 예전에는 꺼진 배지가 크기 0이라 노드가 통째로 빠졌다(4개 ↔ 5개).
    expect(on, off);
    expect(countSemanticsNodes(tester), off);
    handle.dispose();
  });
}
