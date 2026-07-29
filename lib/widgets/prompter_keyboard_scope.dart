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

  /// Home — 곡 처음(트림 시작)으로.
  final VoidCallback? onJumpToStart;

  /// End — 곡 끝(트림 끝)으로.
  final VoidCallback? onJumpToEnd;

  /// ←/→ — 5초 뒤로/앞으로. Shift와 함께면 30초.
  /// v2.8.0 전에는 이 키가 가사 속도 조절이었다.
  final ValueChanged<Duration>? onSeekRelative;

  /// R — 녹음 시작/중지 토글. null이면 R은 아무 일도 하지 않는다.
  final VoidCallback? onToggleRecording;

  final bool enablePlaybackShortcuts;

  const PrompterKeyboardScope({
    super.key,
    required this.child,
    required this.settings,
    required this.onSettingsChanged,
    this.onTogglePlayPause,
    this.onOpenPrompter,
    this.onClose,
    this.onJumpToStart,
    this.onJumpToEnd,
    this.onSeekRelative,
    this.onToggleRecording,
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

    // R = 녹음 시작/중지. 텍스트 입력 중에는 위 가드가 이미 걸러 준다.
    if (key == LogicalKeyboardKey.keyR && widget.onToggleRecording != null) {
      widget.onToggleRecording!();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.home && widget.onJumpToStart != null) {
      widget.onJumpToStart!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end && widget.onJumpToEnd != null) {
      widget.onJumpToEnd!();
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

    final seek = SongListShortcutService.seekDeltaFor(
      key,
      shift: HardwareKeyboard.instance.isShiftPressed,
    );
    if (seek != null && widget.onSeekRelative != null) {
      widget.onSeekRelative!(seek);
      return KeyEventResult.handled;
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
      if (widget.onSeekRelative != null) ...{
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const _SeekBackIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const _SeekForwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
            const _SeekBackIntent(large: true),
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
            const _SeekForwardIntent(large: true),
      },
      if (widget.enablePlaybackShortcuts) ...{
        const SingleActivator(LogicalKeyboardKey.space):
            const _TogglePlayPauseIntent(),
        const SingleActivator(LogicalKeyboardKey.f5): const _OpenPrompterIntent(),
      },
      if (widget.onClose != null)
        const SingleActivator(LogicalKeyboardKey.escape): const _CloseIntent(),
      if (widget.onJumpToStart != null)
        const SingleActivator(LogicalKeyboardKey.home):
            const _JumpToStartIntent(),
      if (widget.onJumpToEnd != null)
        const SingleActivator(LogicalKeyboardKey.end):
            const _JumpToEndIntent(),
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
      if (widget.onSeekRelative != null) ...{
        _SeekForwardIntent: CallbackAction<_SeekForwardIntent>(
          onInvoke: (intent) {
            if (SongListShortcutService.isTextInputFocused()) return null;
            widget.onSeekRelative!(
              intent.large
                  ? SongListShortcutService.seekStepLarge
                  : SongListShortcutService.seekStep,
            );
            return null;
          },
        ),
        _SeekBackIntent: CallbackAction<_SeekBackIntent>(
          onInvoke: (intent) {
            if (SongListShortcutService.isTextInputFocused()) return null;
            widget.onSeekRelative!(
              -(intent.large
                  ? SongListShortcutService.seekStepLarge
                  : SongListShortcutService.seekStep),
            );
            return null;
          },
        ),
      },
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
      if (widget.onJumpToStart != null)
        _JumpToStartIntent: CallbackAction<_JumpToStartIntent>(
          onInvoke: (_) {
            widget.onJumpToStart?.call();
            return null;
          },
        ),
      if (widget.onJumpToEnd != null)
        _JumpToEndIntent: CallbackAction<_JumpToEndIntent>(
          onInvoke: (_) {
            widget.onJumpToEnd?.call();
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

class _SeekForwardIntent extends Intent {
  final bool large;
  const _SeekForwardIntent({this.large = false});
}

class _SeekBackIntent extends Intent {
  final bool large;
  const _SeekBackIntent({this.large = false});
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

class _JumpToStartIntent extends Intent {
  const _JumpToStartIntent();
}

class _JumpToEndIntent extends Intent {
  const _JumpToEndIntent();
}
