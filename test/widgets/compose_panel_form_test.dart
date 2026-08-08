// file: test/widgets/compose_panel_form_test.dart
//
// 작곡 폼 정형화(v5.2.0) — 조합 프롬프트 미리보기·길이 경고·가사 태그 버튼.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/widgets/compose_panel.dart';

Widget _wrap() {
  return MaterialApp(
    home: Scaffold(
      body: ComposePanel(
        composeStatusLabel: '작곡 서버: 꺼짐',
        bgmStatusLabel: 'BGM 서버: 꺼짐',
        jobs: const [],
        compositions: const [],
        playingCompositionId: null,
        onPolishPrompt: (_) async => null,
        onTagLyrics: (_) async => null,
        onGenerate: (_) {},
        onGenerateVariations: (_, _) {},
        onCancelJob: (_) {},
        onRetryJob: (_) {},
        onClearFinishedJobs: () {},
        onPlay: (_) {},
        onStopPlay: (_) {},
        onRename: (_, _) {},
        onRegister: (_, {karaokeSet = false}) {},
        onAttachToSong: (_) {},
        onExport: (_) {},
        onDelete: (_) {},
        presetsLoader: () async => const [],
      ),
    ),
  );
}

void main() {
  // 폼이 길어 기본 800x600에서는 하단 버튼이 화면 밖이다.
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap());
  }

  testWidgets('구조화 입력이 전체 프롬프트로 조합된다', (tester) async {
    await pump(tester);

    await tester.enterText(
      find.widgetWithText(TextField, '장르'), '발라드');
    await tester.enterText(
      find.widgetWithText(TextField, '악기'), '피아노, 현악');
    await tester.tap(find.text('느리게'));
    await tester.pump();

    expect(find.text('발라드, 피아노, 현악, 느린 템포'), findsOneWidget);
  });

  testWidgets('프롬프트가 최대 길이를 넘으면 경고가 뜬다', (tester) async {
    await pump(tester);

    await tester.enterText(
      find.widgetWithText(TextField, '기타 (자유 서술)'), '가' * (promptMaxChars + 1));
    await tester.pump();

    expect(find.textContaining('프롬프트가 깁니다'), findsOneWidget);
  });

  testWidgets('보컬곡 모드에서 [verse] 버튼이 가사에 태그를 넣는다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('보컬곡 (가사 포함)'));
    await tester.pump();
    await tester.ensureVisible(find.text('[verse] 넣기'));
    await tester.tap(find.text('[verse] 넣기'));
    await tester.pump();

    expect(find.textContaining('[verse]\n'), findsOneWidget);
  });

  testWidgets('보컬색 선택이 조합 프롬프트에 들어간다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('보컬곡 (가사 포함)'));
    await tester.pump();
    await tester.tap(find.text('여성'));
    await tester.pump();

    expect(find.text('여성 보컬'), findsOneWidget);
  });
}
