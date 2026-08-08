// file: test/widgets/recording_badge_test.dart
//
// 녹음 중(R) 배지 — 녹음 중일 때만 ●+글자가 보인다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/widgets/recording_badge.dart';

void main() {
  testWidgets('녹음 중이면 배지, 아니면 아무것도 없다', (tester) async {
    final recording = ValueNotifier(false);
    addTearDown(recording.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: RecordingBadge(recording: recording))),
    );

    expect(find.text('녹음 중'), findsNothing);

    recording.value = true;
    await tester.pump();
    expect(find.text('녹음 중'), findsOneWidget);
    expect(find.byIcon(Icons.fiber_manual_record), findsOneWidget);

    recording.value = false;
    await tester.pump();
    expect(find.text('녹음 중'), findsNothing);
  });
}
