// file: test/widgets/newline_shortcut_scope_test.dart
//
// Shift+Enter 줄바꿈 — 여러 줄 입력에서만 동작해야 한다.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/widgets/newline_shortcut_scope.dart';

Widget _harness(TextEditingController controller, {int? maxLines}) {
  return MaterialApp(
    home: Scaffold(
      body: NewlineShortcutScope(
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLines: maxLines,
        ),
      ),
    ),
  );
}

Future<void> _pressShiftEnter(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

void main() {
  testWidgets('여러 줄 입력에서 Shift+Enter는 줄바꿈을 넣는다', (tester) async {
    final controller = TextEditingController(text: '안녕');
    addTearDown(controller.dispose);
    await tester.pumpWidget(_harness(controller, maxLines: 4));
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 2);

    await _pressShiftEnter(tester);

    expect(controller.text, '안녕\n');
    expect(controller.selection.baseOffset, 3);
  });

  testWidgets('선택 영역이 있으면 줄바꿈으로 대체한다', (tester) async {
    final controller = TextEditingController(text: '가나다');
    addTearDown(controller.dispose);
    await tester.pumpWidget(_harness(controller, maxLines: 4));
    await tester.pump();
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 2);

    await _pressShiftEnter(tester);

    expect(controller.text, '가\n다');
  });

  testWidgets('한 줄 입력에서는 아무 일도 하지 않는다', (tester) async {
    final controller = TextEditingController(text: '제목');
    addTearDown(controller.dispose);
    await tester.pumpWidget(_harness(controller, maxLines: 1));
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 2);

    await _pressShiftEnter(tester);

    expect(controller.text, '제목');
  });
}
