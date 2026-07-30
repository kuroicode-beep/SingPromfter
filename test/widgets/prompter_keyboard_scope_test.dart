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
  late int resetCalls;
  late int editCalls;
  late List<int> nudges;

  setUp(() {
    startCalls = 0;
    endCalls = 0;
    seeks = [];
    resetCalls = 0;
    editCalls = 0;
    nudges = [];
  });

  Future<void> pump(
    WidgetTester tester, {
    bool withJumps = true,
    bool withSync = true,
    bool enabled = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrompterKeyboardScope(
            enabled: enabled,
            settings: const PrompterSettings(),
            onSettingsChanged: (_) {},
            onJumpToStart: withJumps ? () => startCalls++ : null,
            onJumpToEnd: withJumps ? () => endCalls++ : null,
            onSeekRelative: withJumps ? seeks.add : null,
            onResetLyricsSync: withSync ? () => resetCalls++ : null,
            onEditCurrentLine: withSync ? () => editCalls++ : null,
            onNudgeLyricsOffset: withSync ? nudges.add : null,
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

  // 싱크를 노래하면서 맞추는 키들. 손이 마우스를 찾을 필요가 없어야 한다.
  testWidgets('T는 싱크를 원래대로 리셋한다', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pump();

    expect(resetCalls, 1);
  });

  testWidgets('E는 현재 줄 인라인 편집을 연다', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();

    expect(editCalls, 1);
  });

  testWidgets('.는 가사를 늦추고 /는 앞당긴다', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pump();

    expect(nudges, [lyricsNudgeStepMs, -lyricsNudgeStepMs]);
  });

  testWidgets('싱크 콜백이 없으면 아무 일도 없다', (tester) async {
    await pump(tester, withSync: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.pump();

    expect(resetCalls, 0);
    expect(editCalls, 0);
    expect(nudges, isEmpty);
    expect(tester.takeException(), isNull);
  });

  test('lyricsNudgeFor — .은 늦춤(+), /은 앞당김(−)', () {
    expect(lyricsNudgeFor(LogicalKeyboardKey.period), lyricsNudgeStepMs);
    expect(lyricsNudgeFor(LogicalKeyboardKey.slash), -lyricsNudgeStepMs);
    expect(lyricsNudgeFor(LogicalKeyboardKey.comma), isNull);
    expect(lyricsNudgeFor(LogicalKeyboardKey.keyT), isNull);
  });

  test('lyricsNudgeFor — Shift 잔상(>·?)도 같은 키로 받는다', () {
    // Shift+→(30초 시크) 직후 Shift가 남은 채 누르면 >·?로 온다 —
    // 실사용에서 "/가 랜덤하게 안 먹음"으로 보고된 원인.
    expect(lyricsNudgeFor(LogicalKeyboardKey.greater), lyricsNudgeStepMs);
    expect(lyricsNudgeFor(LogicalKeyboardKey.question), -lyricsNudgeStepMs);
  });

  test('lyricsNudgeFor — [·]는 예비 키, 문자 매칭은 자판 배열 무관 안전망', () {
    expect(lyricsNudgeFor(LogicalKeyboardKey.bracketLeft), lyricsNudgeStepMs);
    expect(
      lyricsNudgeFor(LogicalKeyboardKey.bracketRight),
      -lyricsNudgeStepMs,
    );
    // 논리 키가 어긋나도(한글 자판 OEM 키) 실제 입력 문자로 잡는다.
    expect(
      lyricsNudgeFor(LogicalKeyboardKey.f19, character: '.'),
      lyricsNudgeStepMs,
    );
    expect(
      lyricsNudgeFor(LogicalKeyboardKey.f19, character: '/'),
      -lyricsNudgeStepMs,
    );
    expect(lyricsNudgeFor(LogicalKeyboardKey.f19, character: 'a'), isNull);
  });

  testWidgets('O/P는 이전/다음 줄', (tester) async {
    final lineSteps = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrompterKeyboardScope(
            settings: const PrompterSettings(),
            onSettingsChanged: (_) {},
            onStepLine: lineSteps.add,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();

    expect(lineSteps, [-1, 1]);
  });

  testWidgets('[와 ]로도 싱크를 밀고 당길 수 있다', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pump();

    expect(nudges, [lyricsNudgeStepMs, -lyricsNudgeStepMs]);
  });


  // 이 범위는 화면 전체를 감싼다 — 끄지 않으면 곡 검색·설정 같은 다른 탭에서도
  // 단축키가 먹는다(검색 결과를 훑다가 R로 녹음이 시작되는 사고).
  testWidgets('꺼진 범위에서는 어떤 단축키도 먹지 않는다', (tester) async {
    await pump(tester, enabled: false);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(resetCalls, 0);
    expect(nudges, isEmpty);
    expect(startCalls, 0);
    expect(seeks, isEmpty);
  });

  testWidgets('다시 켜지면(탭 복귀) 포커스를 되찾아 단축키가 살아난다', (tester) async {
    await pump(tester, enabled: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pump();
    expect(resetCalls, 0);

    await pump(tester, enabled: true);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pump();

    expect(resetCalls, 1);
  });
}
