import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/widgets/prompter_wheel_scope.dart';

// 세 모드(줄 / 글자 크기 / 키)는 완전히 배타적이어야 한다.
// 특히 Ctrl을 눌렀다 떼는 사이에 잔여 델타가 줄을 밀면 안 된다.
void main() {
  late List<int> lineSteps;
  late List<int> sizeSteps;
  late List<int> pitchSteps;
  late TestPointer pointer;
  late bool pointerAdded;

  setUp(() {
    lineSteps = [];
    sizeSteps = [];
    pitchSteps = [];
    // 포인터는 테스트당 하나만 둔다. 스크롤할 때마다 addPointer를 부르면
    // MouseTracker가 중복 등록으로 어서션을 던진다.
    pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointerAdded = false;
  });

  Future<void> pump(WidgetTester tester, {bool withPitch = true}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrompterWheelScope(
              onStepLine: lineSteps.add,
              onStepFontSize: sizeSteps.add,
              onStepPitch: withPitch ? pitchSteps.add : null,
              child: const SizedBox.expand(
                child: ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      );

  Future<void> scroll(WidgetTester tester, double dy) async {
    final center = tester.getCenter(find.byType(PrompterWheelScope));
    if (!pointerAdded) {
      await tester.sendEventToBinding(pointer.addPointer(location: center));
      await tester.sendEventToBinding(pointer.hover(center));
      pointerAdded = true;
    }
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pump();
    // 모드별 레이트 리밋(60ms)을 넘겨 다음 입력이 삼켜지지 않게 한다.
    await tester.pump(const Duration(milliseconds: 80));
  }

  group('wheelModeFor (순수 판정)', () {
    test('수식키가 없으면 줄 이동', () {
      expect(wheelModeFor(ctrl: false, alt: false), WheelMode.line);
    });

    test('Ctrl이면 글자 크기', () {
      expect(wheelModeFor(ctrl: true, alt: false), WheelMode.fontSize);
    });

    test('Alt면 키', () {
      expect(wheelModeFor(ctrl: false, alt: true), WheelMode.pitch);
    });

    test('둘 다 눌리면 키가 이긴다', () {
      expect(wheelModeFor(ctrl: true, alt: true), WheelMode.pitch);
    });
  });

  testWidgets('휠 한 칸 = 한 줄', (tester) async {
    await pump(tester);
    await scroll(tester, 53); // 윈도우 노치 크기

    expect(lineSteps, [1]);
    expect(sizeSteps, isEmpty);
    expect(pitchSteps, isEmpty);
  });

  testWidgets('Ctrl+휠은 글자 크기만', (tester) async {
    await pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await scroll(tester, -53);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(sizeSteps, [1]);
    expect(lineSteps, isEmpty);
    expect(pitchSteps, isEmpty);
  });

  testWidgets('Alt+휠은 키만', (tester) async {
    await pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await scroll(tester, -53);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    expect(pitchSteps, [1]);
    expect(lineSteps, isEmpty);
    expect(sizeSteps, isEmpty);
  });

  testWidgets('Ctrl을 떼도 잔여 델타가 줄을 밀지 않는다 (요구 1 회귀)', (tester) async {
    await pump(tester);

    // 트랙패드처럼 작은 델타로 줄 누적을 만들어 둔다.
    await scroll(tester, 15);
    expect(lineSteps, isEmpty);

    // Ctrl을 누르고 크기를 바꾼다 → 줄 누적은 버려져야 한다.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await scroll(tester, -53);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(sizeSteps, [1]);
    expect(lineSteps, isEmpty);

    // Ctrl을 뗀 뒤 작은 델타 하나로는 줄이 움직이면 안 된다.
    await scroll(tester, 15);
    expect(lineSteps, isEmpty, reason: '이전 모드의 잔여가 새면 안 된다');
  });

  testWidgets('모드를 오가도 서로의 진행을 삼키지 않는다', (tester) async {
    await pump(tester);

    await scroll(tester, 53);
    expect(lineSteps, [1]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await scroll(tester, 53);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(sizeSteps, [-1]);

    await scroll(tester, 53);
    expect(lineSteps, [1, 1], reason: '모드별 레이트 리밋이 따로 돌아야 한다');
  });

  testWidgets('onStepPitch가 없으면 Alt+휠은 아무 일도 하지 않는다', (tester) async {
    await pump(tester, withPitch: false);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await scroll(tester, -53);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    expect(pitchSteps, isEmpty);
    expect(lineSteps, isEmpty);
    expect(sizeSteps, isEmpty);
  });
}
