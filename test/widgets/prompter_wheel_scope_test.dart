import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/widgets/prompter_wheel_scope.dart';

// 요구 4·8의 상호 배타성을 고정한다:
//   그냥 휠  → 줄 이동만
//   Ctrl+휠 → 글자 크기만
void main() {
  late List<int> lineSteps;
  late List<int> sizeSteps;

  setUp(() {
    lineSteps = [];
    sizeSteps = [];
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PrompterWheelScope(
          onStepLine: lineSteps.add,
          onStepFontSize: sizeSteps.add,
          child: const SizedBox.expand(child: ColoredBox(color: Colors.black)),
        ),
      ),
    ),
  );

  /// 휠 이벤트를 무대 가운데로 보낸다.
  Future<void> scroll(WidgetTester tester, double dy) async {
    final center = tester.getCenter(find.byType(PrompterWheelScope));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.addPointer(location: center));
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pump();
  }

  testWidgets('휠을 아래로 굴리면 다음 줄로 간다', (tester) async {
    await pump(tester);
    await scroll(tester, 120);

    expect(lineSteps, [1]);
    expect(sizeSteps, isEmpty);
  });

  testWidgets('휠을 위로 굴리면 이전 줄로 간다', (tester) async {
    await pump(tester);
    await scroll(tester, -120);

    expect(lineSteps, [-1]);
    expect(sizeSteps, isEmpty);
  });

  testWidgets('임계값에 못 미치면 아무 일도 없다', (tester) async {
    await pump(tester);
    await scroll(tester, 10);

    expect(lineSteps, isEmpty);
    expect(sizeSteps, isEmpty);
  });

  testWidgets('Ctrl+휠은 글자 크기만 바꾸고 줄은 건드리지 않는다', (tester) async {
    await pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await scroll(tester, -120); // 위로 = 크게
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(sizeSteps, [1]);
    expect(lineSteps, isEmpty);
  });

  testWidgets('Ctrl+휠 아래로 굴리면 작아진다', (tester) async {
    await pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await scroll(tester, 120);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(sizeSteps, [-1]);
    expect(lineSteps, isEmpty);
  });
}
