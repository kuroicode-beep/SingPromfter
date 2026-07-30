// file: lib/widgets/prompter_keyboard_scope.dart
//
// 메인·전체화면 공통 키보드 단축키 포커스 범위.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/prompter_settings.dart';
import '../services/song_list_shortcut_service.dart';

/// 가사 싱크 한 걸음. 화면의 −/+ 버튼과 같은 값을 쓴다 — 걸음이 두 개면
/// 키보드로 맞춘 값과 버튼으로 맞춘 값이 서로 안 맞는다.
const int lyricsNudgeStepMs = 200;

/// `.`은 뒤로(늦춤), `/`는 앞으로(앞당김). 해당 키가 아니면 null.
/// (순수 함수 — 테스트 대상)
///
/// v2.16까지는 반대였는데 사용자 감각과 어긋났다 — "."이 늦추고 "/"가
/// 앞당기는 쪽이 손에 맞는다는 피드백으로 뒤집었다.
int? lyricsNudgeFor(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.period) return lyricsNudgeStepMs;
  if (key == LogicalKeyboardKey.slash) return -lyricsNudgeStepMs;
  return null;
}

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

  /// T — 싱크를 원래대로(오프셋 0) 되돌린다. `.`/`/`로 밀고 당기다
  /// 어긋났을 때 처음부터 다시 맞추는 리셋 키다.
  final VoidCallback? onResetLyricsSync;

  /// E — 현재 가사 줄을 그 자리에서 편집한다. 입력 중에는 텍스트 입력
  /// 가드가 모든 단축키를 자동으로 끈다. ESC로 저장하고 나온다.
  final VoidCallback? onEditCurrentLine;

  /// . / — 가사 싱크를 당기고 미는 실시간 조절(ms 델타). 음수면 가사가 먼저.
  ///
  /// 노래하면서 바로 손댈 수 있어야 하는 값이다. 곡별로 즉시 저장되므로
  /// 한 번 맞춰 두면 다음부터는 그대로 뜬다.
  final ValueChanged<int>? onNudgeLyricsOffset;

  final bool enablePlaybackShortcuts;

  /// 이 범위의 단축키 전체를 켜고 끈다.
  ///
  /// 이 위젯은 화면 전체를 감싸므로, 끄지 않으면 곡 검색·설정 같은
  /// **다른 탭에서도** 단축키가 먹는다 — 검색 결과를 훑다가 R을 눌러
  /// 녹음이 시작되는 식. 단축키는 메인(홈·즐겨찾기)과 전체화면 무대에서만
  /// 살아 있어야 한다. 호출부가 현재 탭으로 판단해 넘긴다.
  final bool enabled;

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
    this.onResetLyricsSync,
    this.onEditCurrentLine,
    this.onNudgeLyricsOffset,
    this.enablePlaybackShortcuts = true,
    this.enabled = true,
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
  void didUpdateWidget(covariant PrompterKeyboardScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 다른 탭에 갔다가 돌아오면(비활성 → 활성) 포커스를 되찾아
    // 단축키가 바로 살아나게 한다.
    if (widget.enabled && !oldWidget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestScopeFocus());
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _requestScopeFocus() {
    if (!mounted) return;
    if (!widget.enabled) return;
    if (SongListShortcutService.isTextInputFocused()) return;
    _focusNode.requestFocus();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    // 꺼진 탭에서는 아무 키도 삼키지 않는다 — 그 탭의 위젯(목록 이동 등)이
    // 키를 정상적으로 받아야 한다.
    if (!widget.enabled) return KeyEventResult.ignored;
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

    // T = 싱크 리셋(오프셋 0으로). 밀고 당기다 어긋나면 처음부터.
    if (key == LogicalKeyboardKey.keyT && widget.onResetLyricsSync != null) {
      widget.onResetLyricsSync!();
      return KeyEventResult.handled;
    }

    // E = 현재 줄 인라인 편집. 받아쓰기 오탈자를 노래 중에 바로 고친다.
    if (key == LogicalKeyboardKey.keyE && widget.onEditCurrentLine != null) {
      widget.onEditCurrentLine!();
      return KeyEventResult.handled;
    }

    // . / = 가사 싱크 당기기·밀기. 나란히 붙은 두 키를 왼쪽=먼저, 오른쪽=늦게로
    // 둔다(화면의 −/+ 버튼과 같은 걸음). 조절은 곡별로 즉시 저장된다.
    final nudge = lyricsNudgeFor(key);
    if (nudge != null && widget.onNudgeLyricsOffset != null) {
      widget.onNudgeLyricsOffset!(nudge);
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
    // 꺼진 탭에서는 단축키 층(Shortcuts·Actions·Focus)을 통째로 뺀다.
    // _onKeyEvent만 막으면 Shortcuts 맵(화살표·Home/End)이 여전히 먹는다 —
    // 실제로 그 경로로 새서 잡은 버그다.
    if (!widget.enabled) return widget.child;
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
