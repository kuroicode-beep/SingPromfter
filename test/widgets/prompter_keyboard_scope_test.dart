import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/prompter_settings.dart';
import 'package:singpromfter_app/widgets/prompter_keyboard_scope.dart';

// Home/End = 곡 처음/끝으로, ←/→ = 5초 뒤로/앞으로.
void main() {
  late int startCalls;
  late int endCalls;
  late List<Duration> seeks;

  setUp(() {
    startCalls = 0;
    endCalls = 0;
    seeks = [];
  });

  Future<void> pump(
    WidgetTester tester, {
    bool withJumps = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrompterKeyboardScope(
            settings: const PrompterSettings(),
            onSettingsChanged: (_) {},
            onJumpToStart: withJumps ? () => startCalls++ : null,
            onJumpToEnd: withJumps ? () => endCalls++ : null,
            onSeekRelative: withJumps ? seeks.add : null,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Home은 곡 처음으로', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();

    expect(startCalls, 1);
    expect(endCalls, 0);
  });

  testWidgets('End는 곡 끝으로', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();

    expect(endCalls, 1);
    expect(startCalls, 0);
  });

  testWidgets('콜백이 없으면 아무 일도 없다', (tester) async {
    await pump(tester, withJumps: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();

    expect(startCalls, 0);
    expect(endCalls, 0);
    expect(tester.takeException(), isNull);
  });

  // v2.8.0: 이 키가 가사 속도 조절이었다가 이동으로 바뀌었다.
  testWidgets('→는 5초 앞으로', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(seeks, [const Duration(seconds: 5)]);
  });

  testWidgets('←는 5초 뒤로', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    expect(seeks, [const Duration(seconds: -5)]);
  });

  testWidgets('Shift+→는 30초 앞으로', (tester) async {
    await pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(seeks, [const Duration(seconds: 30)]);
  });

  testWidgets('이동 콜백이 없으면 아무 일도 없다', (tester) async {
    await pump(tester, withJumps: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(seeks, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
