// file: lib/widgets/prompter_keyboard_scope.dart
//
// 메인·전체화면 공통 키보드 단축키 포커스 범위.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/prompter_settings.dart';
import '../services/song_list_shortcut_service.dart';

class PrompterKeyboardScope extends StatefulWidget {
  final Widget child;
  final PrompterSettings settings;
  final ValueChanged<PrompterSettings> onSettingsChanged;
  final VoidCallback? onTogglePlayPause;
  final VoidCallback? onOpenPrompter;
  final VoidCallback? onClose;
  final bool enablePlaybackShortcuts;

  const PrompterKeyboardScope({
    super.key,
    required this.child,
    required this.settings,
    required this.onSettingsChanged,
    this.onTogglePlayPause,
    this.onOpenPrompter,
    this.onClose,
    this.enablePlaybackShortcuts = true,
  });

  @override
  State<PrompterKeyboardScope> createState() => _PrompterKeyboardScopeState();
}

class _PrompterKeyboardScopeState extends State<PrompterKeyboardScope> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'prompterKeyboard');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestScopeFocus());
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _requestScopeFocus() {
    if (!mounted) return;
    if (SongListShortcutService.isTextInputFocused()) return;
    _focusNode.requestFocus();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (SongListShortcutService.isTextInputFocused()) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape && widget.onClose != null) {
      widget.onClose!();
      return KeyEventResult.handled;
    }

    if (widget.enablePlaybackShortcuts) {
      if (key == LogicalKeyboardKey.space && widget.onTogglePlayPause != null) {
        widget.onTogglePlayPause!();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.f5 && widget.onOpenPrompter != null) {
        widget.onOpenPrompter!();
        return KeyEventResult.handled;
      }
    }

    final adjusted = SongListShortcutService.adjustSettings(widget.settings, key);
    if (adjusted != null) {
      widget.onSettingsChanged(adjusted);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: _shortcutMap,
      child: Actions(
        actions: _buildActions(),
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          canRequestFocus: true,
          onKeyEvent: _onKeyEvent,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _requestScopeFocus(),
            child: widget.child,
          ),
        ),
      ),
    );
  }

  Map<ShortcutActivator, Intent> get _shortcutMap {
    return {
      const SingleActivator(LogicalKeyboardKey.arrowUp): const _VolumeUpIntent(),
      const SingleActivator(LogicalKeyboardKey.arrowDown):
          const _VolumeDownIntent(),
      const SingleActivator(LogicalKeyboardKey.arrowLeft):
          const _SpeedDownIntent(),
      const SingleActivator(LogicalKeyboardKey.arrowRight):
          const _SpeedUpIntent(),
      if (widget.enablePlaybackShortcuts) ...{
        const SingleActivator(LogicalKeyboardKey.space):
            const _TogglePlayPauseIntent(),
        const SingleActivator(LogicalKeyboardKey.f5): const _OpenPrompterIntent(),
      },
      if (widget.onClose != null)
        const SingleActivator(LogicalKeyboardKey.escape): const _CloseIntent(),
    };
  }

  Map<Type, Action<Intent>> _buildActions() {
    PrompterSettings? adjust(LogicalKeyboardKey key) {
      if (SongListShortcutService.isTextInputFocused()) return null;
      return SongListShortcutService.adjustSettings(widget.settings, key);
    }

    return {
      _VolumeUpIntent: CallbackAction<_VolumeUpIntent>(
        onInvoke: (_) {
          final next = adjust(LogicalKeyboardKey.arrowUp);
          if (next != null) widget.onSettingsChanged(next);
          return null;
        },
      ),
      _VolumeDownIntent: CallbackAction<_VolumeDownIntent>(
        onInvoke: (_) {
          final next = adjust(LogicalKeyboardKey.arrowDown);
          if (next != null) widget.onSettingsChanged(next);
          return null;
        },
      ),
      _SpeedUpIntent: CallbackAction<_SpeedUpIntent>(
        onInvoke: (_) {
          final next = adjust(LogicalKeyboardKey.arrowRight);
          if (next != null) widget.onSettingsChanged(next);
          return null;
        },
      ),
      _SpeedDownIntent: CallbackAction<_SpeedDownIntent>(
        onInvoke: (_) {
          final next = adjust(LogicalKeyboardKey.arrowLeft);
          if (next != null) widget.onSettingsChanged(next);
          return null;
        },
      ),
      if (widget.enablePlaybackShortcuts) ...{
        _TogglePlayPauseIntent: CallbackAction<_TogglePlayPauseIntent>(
          onInvoke: (_) {
            if (SongListShortcutService.isTextInputFocused()) return null;
            widget.onTogglePlayPause?.call();
            return null;
          },
        ),
        _OpenPrompterIntent: CallbackAction<_OpenPrompterIntent>(
          onInvoke: (_) {
            if (SongListShortcutService.isTextInputFocused()) return null;
            widget.onOpenPrompter?.call();
            return null;
          },
        ),
      },
      if (widget.onClose != null)
        _CloseIntent: CallbackAction<_CloseIntent>(
          onInvoke: (_) {
            widget.onClose?.call();
            return null;
          },
        ),
    };
  }
}

class _VolumeUpIntent extends Intent {
  const _VolumeUpIntent();
}

class _VolumeDownIntent extends Intent {
  const _VolumeDownIntent();
}

class _SpeedUpIntent extends Intent {
  const _SpeedUpIntent();
}

class _SpeedDownIntent extends Intent {
  const _SpeedDownIntent();
}

class _TogglePlayPauseIntent extends Intent {
  const _TogglePlayPauseIntent();
}

class _OpenPrompterIntent extends Intent {
  const _OpenPrompterIntent();
}

class _CloseIntent extends Intent {
  const _CloseIntent();
}
