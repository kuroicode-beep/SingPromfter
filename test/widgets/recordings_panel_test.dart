// file: test/widgets/recordings_panel_test.dart
//
// 녹음 보관함의 AI 버튼 게이트. AI가 꺼지면 '음정 체크'·'AI 보정'이
// 사라지고, ffmpeg로 도는 비AI 기능('반주와 합치기' 등)은 그대로 남는다.
// 오폭(비AI 기능까지 함께 숨김)이 이 기능의 가장 큰 회귀 위험이라
// 존재 단언을 같은 테스트에 붙여 둔다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/recording_take.dart';
import 'package:singpromfter_app/theme/app_theme.dart';
import 'package:singpromfter_app/widgets/recordings_panel.dart';

RecordingTake _take() => RecordingTake(
  id: 't1',
  songId: 's1',
  songTitle: '테스트 곡',
  fileName: 't1.wav',
  recordedAt: DateTime(2026, 8, 18, 12),
  durationMs: 30000,
);

Widget _panel({
  ValueChanged<RecordingTake>? onAnalyze,
  ValueChanged<RecordingTake>? onCorrect,
}) => MaterialApp(
  theme: AppTheme.dark(),
  home: Scaffold(
    body: RecordingsPanel(
      takes: [_take()],
      query: '',
      filterMode: RecordingFilterMode.all,
      playingTakeId: null,
      onQueryChanged: (_) {},
      onFilterModeChanged: (_) {},
      onPlay: (_) {},
      onStopPlay: (_) {},
      onEditComment: (_) {},
      onRate: (_, _) {},
      onToggleKeep: (_) {},
      onDelete: (_) {},
      onMix: (_) {},
      onPlayMix: (_) {},
      onAnalyze: onAnalyze,
      onCorrect: onCorrect,
      onPlayAccompaniment: (_) {},
      onCutAccompaniment: (_) {},
      onMixSettings: (_) {},
      onExport: (_) {},
    ),
  ),
);

void main() {
  testWidgets('콜백이 있으면 AI 버튼 2개가 보인다', (tester) async {
    await tester.pumpWidget(_panel(onAnalyze: (_) {}, onCorrect: (_) {}));
    await tester.pumpAndSettle();

    expect(find.text('음정 체크'), findsOneWidget);
    expect(find.text('AI 보정'), findsOneWidget);
  });

  testWidgets('콜백이 null이면 AI 버튼이 사라진다', (tester) async {
    await tester.pumpWidget(_panel());
    await tester.pumpAndSettle();

    expect(find.text('음정 체크'), findsNothing);
    expect(find.text('AI 보정'), findsNothing);
  });

  testWidgets('AI가 꺼져도 비AI 기능은 그대로 남는다 — 오폭 방지', (tester) async {
    await tester.pumpWidget(_panel());
    await tester.pumpAndSettle();

    // 전부 ffmpeg로 도는 기능이라 AI 토글과 무관해야 한다.
    expect(find.text('반주와 합치기'), findsOneWidget);
    expect(find.text('반주 만들기'), findsOneWidget);
    expect(find.text('파일로 내보내기'), findsOneWidget);
  });
}
