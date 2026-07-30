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
  late List<int> lineSteps;
  late int settingsChanges;

  setUp(() {
    startCalls = 0;
    endCalls = 0;
    seeks = [];
    resetCalls = 0;
    editCalls = 0;
    nudges = [];
    lineSteps = [];
    settingsChanges = 0;
  });

  Future<void> pump(
    WidgetTester tester, {
    bool withJumps = true,
    bool withSync = true,
    bool withStepLine = true,
    bool enabled = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrompterKeyboardScope(
            enabled: enabled,
            settings: const PrompterSettings(),
            onSettingsChanged: (_) => settingsChanges++,
            actions: PrompterActions(
              jumpToStart: withJumps ? () => startCalls++ : null,
              jumpToEnd: withJumps ? () => endCalls++ : null,
              seekRelative: withJumps ? seeks.add : null,
              resetLyricsSync: withSync ? () => resetCalls++ : null,
              nudgeLyricsOffset: withSync ? nudges.add : null,
              stepLine: withStepLine ? lineSteps.add : null,
            ),
            onEditCurrentLine: withSync ? () => editCalls++ : null,
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

  // v3.6.0: 화살표가 본대가 됐다 — 문장부호·글자 키가 환경에 따라 안 먹는
  // 실사용 보고 때문. ←/→=싱크, ↑/↓=줄, 원래 기능(이동·볼륨)은 Shift로.
  testWidgets('←는 가사를 늦추고 →는 앞당긴다', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(nudges, [lyricsNudgeStepMs, -lyricsNudgeStepMs]);
    expect(seeks, isEmpty);
  });

  testWidgets('↑/↓는 이전/다음 줄', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(lineSteps, [-1, 1]);
    expect(settingsChanges, 0);
  });

  testWidgets('Shift+→는 30초 앞으로', (tester) async {
    await pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(seeks, [const Duration(seconds: 30)]);
    expect(nudges, isEmpty);
  });

  testWidgets('Shift+↑는 볼륨 조절로 간다', (tester) async {
    await pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(settingsChanges, 1);
    expect(lineSteps, isEmpty);
  });

  testWidgets('싱크 대상이 없으면 ←/→는 예전처럼 5초 이동', (tester) async {
    await pump(tester, withSync: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(seeks, [const Duration(seconds: 5)]);
  });

  testWidgets('줄 이동 대상이 없으면 ↑/↓는 예전처럼 볼륨', (tester) async {
    await pump(tester, withStepLine: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(settingsChanges, 1);
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
            actions: PrompterActions(stepLine: lineSteps.add),
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

  test('물리 키(자판 위치)만으로도 판정된다 — 논리 키·문자가 다 어긋난 경우', () {
    // 실사용 보고: [·]가 아예 안 먹음 — 논리 키도 문자도 기대와 다르게
    // 오는 환경(IME/자판)의 최후 안전망.
    expect(
      lyricsNudgeFor(
        LogicalKeyboardKey.f19,
        physicalKey: PhysicalKeyboardKey.bracketLeft,
      ),
      lyricsNudgeStepMs,
    );
    expect(
      lyricsNudgeFor(
        LogicalKeyboardKey.f19,
        physicalKey: PhysicalKeyboardKey.bracketRight,
      ),
      -lyricsNudgeStepMs,
    );
    expect(
      stepLineFor(LogicalKeyboardKey.f19, physicalKey: PhysicalKeyboardKey.keyO),
      -1,
    );
    expect(
      stepLineFor(LogicalKeyboardKey.f19, physicalKey: PhysicalKeyboardKey.keyP),
      1,
    );
    // 관계없는 물리 키는 그대로 무시
    expect(
      lyricsNudgeFor(
        LogicalKeyboardKey.f19,
        physicalKey: PhysicalKeyboardKey.keyQ,
      ),
      isNull,
    );
  });

  test('stepLineFor — O/P 3겹 판정(논리 키·문자·한글 자판 ㅐ/ㅔ)', () {
    expect(stepLineFor(LogicalKeyboardKey.keyO), -1);
    expect(stepLineFor(LogicalKeyboardKey.keyP), 1);
    // 논리 키가 어긋나도(한글 IME/OEM 매핑) 실제 문자로 잡는다.
    expect(stepLineFor(LogicalKeyboardKey.f19, character: 'o'), -1);
    expect(stepLineFor(LogicalKeyboardKey.f19, character: 'ㅐ'), -1);
    expect(stepLineFor(LogicalKeyboardKey.f19, character: 'P'), 1);
    expect(stepLineFor(LogicalKeyboardKey.f19, character: 'ㅔ'), 1);
    expect(stepLineFor(LogicalKeyboardKey.keyQ, character: 'q'), isNull);
  });

  // 실사용 보고: 곡 수정 창을 닫은 직후 O/P·[·]이 전부 안 먹음.
  // 다이얼로그·팝업 메뉴가 닫히면서 포커스가 스코프 밖(루트/스코프 노드)으로
  // 떨어지면 글자 단축키가 조용히 죽는다 — 스스로 되찾아야 한다.
  testWidgets('포커스가 고아가 되면 스스로 되찾아 단축키가 살아난다', (tester) async {
    await pump(tester);

    // 다이얼로그가 닫히며 아무 위젯도 포커스를 안 가진 상황을 재현한다.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(); // 자가복구 postFrame 반영

    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pump();
    expect(resetCalls, 1);
  });

  // "먹었다 안먹었다"의 주범 — 검색창 등 텍스트 입력이 포커스를 쥐면
  // 단축키가 전부 멎는데(타이핑 보호), 빠져나올 길이 없었다.
  Future<void> pumpWithTextField(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrompterKeyboardScope(
            settings: const PrompterSettings(),
            onSettingsChanged: (_) {},
            actions: PrompterActions(resetLyricsSync: () => resetCalls++),
            child: const Column(
              children: [
                TextField(),
                Expanded(child: SizedBox.expand()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 검색창을 만진 상태를 재현
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pump();
    expect(resetCalls, 0); // 입력 중에는 단축키 보호가 맞다
  }

  testWidgets('입력창 밖을 클릭하면 입력 포커스가 풀려 단축키가 살아난다', (tester) async {
    await pumpWithTextField(tester);

    // 입력창 아래 빈 영역 클릭
    await tester.tapAt(tester.getCenter(find.byType(SizedBox).last));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pump();
    expect(resetCalls, 1);
  });

  testWidgets('ESC로 입력 포커스를 풀고 단축키를 살린다', (tester) async {
    await pumpWithTextField(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pump();
    expect(resetCalls, 1);
  });

  testWidgets('입력창 자체를 클릭한 경우에는 포커스를 뺏지 않는다', (tester) async {
    await pumpWithTextField(tester);

    await tester.tap(find.byType(TextField));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pump();
    expect(resetCalls, 0); // 여전히 타이핑 보호
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
