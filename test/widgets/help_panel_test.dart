// file: test/widgets/help_panel_test.dart
//
// 도움말 탭 — 단축키 표 렌더와 음성 재생 버튼(가짜 오디오 주입).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/constants/app_shortcuts.dart';
import 'package:singpromfter_app/services/guide_audio_service.dart';
import 'package:singpromfter_app/theme/app_theme.dart';
import 'package:singpromfter_app/widgets/help_panel.dart';

class _FakeAudio implements GuideAudio {
  final played = <String>[];
  var stopped = 0;
  var disposed = false;

  @override
  Future<void> playVoice(String clipId) async => played.add(clipId);

  @override
  Future<void> playVoiceSequence(
    Iterable<String> clipIds, {
    bool Function()? cancelled,
  }) async {
    for (final id in clipIds) {
      if (cancelled?.call() ?? false) return;
      played.add(id);
    }
  }

  @override
  Future<void> playPianoRun(String fileName) async {}

  @override
  Future<void> stopVoice() async {}

  @override
  Future<void> stopPiano() async {}

  @override
  Future<void> stopAll() async => stopped++;

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  late _FakeAudio audio;

  Future<void> pump(WidgetTester tester) async {
    audio = _FakeAudio();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: HelpPanel(audioFactory: () => audio)),
      ),
    );
    await tester.pump();
  }

  testWidgets('단축키 표가 전부 렌더된다(재생 화면 + 트레이닝)', (tester) async {
    await pump(tester);
    expect(find.text('도움말 — 단축키'), findsOneWidget);
    expect(find.text('전체 듣기'), findsOneWidget);
    // 첫 항목과 트레이닝 섹션 항목이 보이는지(지연 렌더 목록이라 스크롤).
    expect(find.text(AppShortcuts.entries.first.keys), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('트레이닝 따라하기 중'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('트레이닝 따라하기 중'), findsOneWidget);
  });

  testWidgets('행 재생 버튼은 해당 클립 하나를 재생한다', (tester) async {
    await pump(tester);
    await tester.tap(find.byIcon(Icons.volume_up_outlined).first);
    await tester.pump();
    expect(audio.played, [AppShortcuts.entries.first.clipId]);
  });

  testWidgets('전체 듣기는 인트로→항목→마침 순서로 재생한다', (tester) async {
    await pump(tester);
    await tester.tap(find.text('전체 듣기'));
    await tester.pumpAndSettle();
    expect(audio.played.first, 'help_intro');
    expect(audio.played.last, 'help_done');
    expect(audio.played, contains('help_training_intro'));
    expect(
      audio.played.length,
      3 + AppShortcuts.entries.length + AppShortcuts.trainingEntries.length,
    );
  });

  testWidgets('패널이 사라지면 오디오를 정리한다', (tester) async {
    await pump(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(audio.disposed, isTrue);
  });
}
