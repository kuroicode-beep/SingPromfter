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

RecordingTake _take({
  String id = 't1',
  String? accompaniment,
  String? mixed,
  bool dualChannel = false,
  int? songPositionMs,
  int? leadInMs,
}) => RecordingTake(
  id: id,
  songId: 's1',
  songTitle: '테스트 곡',
  fileName: 't1.wav',
  recordedAt: DateTime(2026, 8, 18, 12),
  durationMs: 30000,
  accompanimentFileName: accompaniment,
  mixedFileName: mixed,
  dualChannel: dualChannel,
  songPositionMs: songPositionMs,
  leadInMs: leadInMs,
);

Widget _panel({
  ValueChanged<RecordingTake>? onAnalyze,
  ValueChanged<RecordingTake>? onCorrect,
  RecordingTake? take,
  List<RecordingTake>? takes,
}) => MaterialApp(
  theme: AppTheme.dark(),
  home: Scaffold(
    body: RecordingsPanel(
      takes: takes ?? [take ?? _take()],
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
      onStitch: (_) {},
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
    expect(find.text('내보내기(보컬·반주·합친 곡)'), findsOneWidget);
  });

  testWidgets('합친 곡이 없으면 보컬이 미리 듣기다', (tester) async {
    await tester.pumpWidget(_panel());
    await tester.pumpAndSettle();

    expect(find.text('듣기(보컬)'), findsOneWidget);
    expect(find.text('듣기(합친 곡)'), findsNothing);
    // 합친 게 없으면 보컬 단독 버튼을 따로 둘 이유가 없다.
    expect(find.text('보컬만 듣기'), findsNothing);
  });

  testWidgets('2채널 녹음은 합친 곡이 미리 듣기, 채널별 재생도 함께 있다', (tester) async {
    await tester.pumpWidget(
      _panel(take: _take(accompaniment: 't1_acc.wav', mixed: 't1_mix.m4a')),
    );
    await tester.pumpAndSettle();

    expect(find.text('듣기(합친 곡)'), findsOneWidget);
    expect(find.text('보컬만 듣기'), findsOneWidget);
    expect(find.text('반주만 듣기'), findsOneWidget);
    // 반주가 이미 있으면 '반주 만들기'를 권하지 않는다.
    expect(find.text('반주 만들기'), findsNothing);
  });

  testWidgets('2채널 테이크는 메타 줄에 글자로 표시된다', (tester) async {
    await tester.pumpWidget(
      _panel(
        take: _take(
          accompaniment: 't1_acc.wav',
          mixed: 't1_mix.m4a',
          dualChannel: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('2채널(보컬+반주)'), findsOneWidget);
  });

  testWidgets('1채널 테이크에는 2채널 표시가 없다', (tester) async {
    await tester.pumpWidget(_panel());
    await tester.pumpAndSettle();

    expect(find.textContaining('2채널'), findsNothing);
  });

  group('조각(펀치인) 표시와 잇기 버튼', () {
    testWidgets('곡 위치가 있으면 메타 줄에 조각으로 표시된다', (tester) async {
      await tester.pumpWidget(_panel(take: _take(songPositionMs: 126161)));
      await tester.pumpAndSettle();

      expect(find.textContaining('2:06 조각'), findsOneWidget);
    });

    testWidgets('고정 조각은 저장 토스트와 같은 숫자(누른 자리)로 표시된다', (tester) async {
      // 파일 좌표 1:22.785 + 리드인 300ms = 누른 자리 1:23.
      await tester.pumpWidget(
        _panel(take: _take(songPositionMs: 82785, leadInMs: 300)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('1:23 조각'), findsOneWidget);
      expect(find.textContaining('1:22 조각'), findsNothing);
    });

    testWidgets('조각이 하나뿐이면 잇기 버튼이 없다', (tester) async {
      await tester.pumpWidget(_panel(take: _take(songPositionMs: 120000)));
      await tester.pumpAndSettle();

      expect(find.text('조각 잇기'), findsNothing);
    });

    testWidgets('같은 곡 조각이 둘 이상이면 잇기 버튼이 보인다', (tester) async {
      await tester.pumpWidget(
        _panel(
          takes: [
            _take(id: 't1', songPositionMs: 120000),
            _take(id: 't2', songPositionMs: 123050),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('조각 잇기'), findsNWidgets(2));
    });

    testWidgets('곡 위치가 없는 옛 녹음은 잇기 대상이 아니다', (tester) async {
      await tester.pumpWidget(
        _panel(takes: [_take(id: 't1'), _take(id: 't2')]),
      );
      await tester.pumpAndSettle();

      expect(find.text('조각 잇기'), findsNothing);
      expect(find.textContaining('조각'), findsNothing);
    });
  });
}
