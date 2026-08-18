// file: test/widgets/recording_badge_test.dart
//
// 녹음 중(R) 배지 — 녹음 중일 때만 ● 아이콘이 보인다.
// v5.6.0에서 글자를 뺐다(가사 가림 최소화). 대신 스크린리더 라벨과
// 호버 안내가 남아 있어야 한다 — 인지 수단이 아이콘 하나로 줄면 안 된다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/widgets/recording_badge.dart';

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

    expect(find.bySemanticsLabel('녹음 중 — R로 중지'), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, '녹음 중 — R로 중지');
  });
}
