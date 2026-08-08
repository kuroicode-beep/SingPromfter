// file: lib/widgets/newline_shortcut_scope.dart
//
// Shift+Enter 줄바꿈 전역 매핑. Flutter 데스크톱의 기본 텍스트 편집 매핑에는
// Shift+Enter가 없어(메신저 습관과 달리) 여러 줄 입력에서 아무 일도 일어나지
// 않는다 — 앱 루트에서 이 스코프로 채운다.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _InsertNewlineIntent extends Intent {
  const _InsertNewlineIntent();
}

/// 포커스된 여러 줄 입력에 줄바꿈을 끼워 넣는다. 한 줄 입력이면 아무것도
/// 하지 않는다(제목 칸에 \n이 들어가는 사고 방지). (테스트 대상)
void insertNewlineAtFocus() {
  final context = FocusManager.instance.primaryFocus?.context;
  final editable = context?.findAncestorStateOfType<EditableTextState>();
  if (editable == null || editable.widget.maxLines == 1) return;
  final value = editable.textEditingValue;
  final selection = value.selection;
  if (!selection.isValid) return;
  final start = selection.start;
  editable.userUpdateTextEditingValue(
    TextEditingValue(
      text: value.text.replaceRange(start, selection.end, '\n'),
      selection: TextSelection.collapsed(offset: start + 1),
    ),
    SelectionChangedCause.keyboard,
  );
}

/// 입력창이 처리하지 않는 키만 여기로 떨어지므로 일반 타이핑·기존
/// 단축키와 충돌하지 않는다.
class NewlineShortcutScope extends StatelessWidget {
  final Widget child;

  const NewlineShortcutScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter, shift: true):
            _InsertNewlineIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter, shift: true):
            _InsertNewlineIntent(),
      },
      child: Actions(
        actions: {
          _InsertNewlineIntent: CallbackAction<_InsertNewlineIntent>(
            onInvoke: (_) {
              insertNewlineAtFocus();
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}
