// file: lib/widgets/inline_name_editor.dart
//
// 제자리 이름 편집칸 — 목록의 폴더 이름·곡 제목을 더블클릭하면 그 자리에
// 뜬다. 이름만 고치자고 수정 창을 여닫는 게 번거롭다는 실사용 요청.
//
// 탐색기와 같은 문법이라 따로 배울 게 없다: 열리면 전체 선택,
// Enter로 확정, Esc로 취소, 다른 곳을 누르면 확정.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

class InlineNameEditor extends StatefulWidget {
  final String initial;

  /// 스크린리더가 읽을 이름(예: '폴더 이름 수정').
  final String semanticsLabel;

  /// 제자리 편집이므로 원래 글자와 같은 모양을 쓴다.
  final TextStyle? style;

  /// 확정. 다듬지 않은 원문을 넘긴다 — 공백 처리는 호출부 소관.
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  const InlineNameEditor({
    super.key,
    required this.initial,
    required this.semanticsLabel,
    required this.onSubmit,
    required this.onCancel,
    this.style,
  });

  @override
  State<InlineNameEditor> createState() => _InlineNameEditorState();
}

class _InlineNameEditorState extends State<InlineNameEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  )..selection = TextSelection(
    baseOffset: 0,
    extentOffset: widget.initial.length,
  );

  /// Enter로 확정한 뒤 포커스가 빠지며 한 번 더 부르는 것을 막는 빗장.
  bool _closed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_closed) return;
    _closed = true;
    widget.onSubmit(_controller.text);
  }

  void _cancel() {
    if (_closed) return;
    _closed = true;
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticsLabel,
      textField: true,
      child: Focus(
        // Esc는 TextField가 쓰지 않아 여기까지 올라온다.
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _cancel();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: _controller,
          autofocus: true,
          style: widget.style ?? AppTypography.body,
          decoration: const InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.elevated,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
          onTapOutside: (_) => _submit(),
        ),
      ),
    );
  }
}
