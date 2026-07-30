// file: lib/widgets/prompter_keyboard_scope.dart
//
// 메인·전체화면 공통 키보드 단축키 포커스 범위.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
int? lyricsNudgeFor(
  LogicalKeyboardKey key, {
  String? character,
  PhysicalKeyboardKey? physicalKey,
}) {
  // 네 겹으로 판정한다:
  // 1) 논리 키(.·/) — 표준 경로.
  // 2) Shift 잔상(>·?) — Shift+→(30초 시크) 직후 흔하다.
  // 3) **실제 입력 문자** — Windows 한글 자판에서 OEM 문장부호 키의 논리 키
  //    매핑이 어긋나는 일이 있다(글자 키 T·E·R은 되는데 .·/만 안 먹는
  //    실사용 보고의 원인으로 추정). 문자는 배열과 무관하게 온다.
  // 4) **물리 키(자판 위치)** — 논리 키도 문자도 안 온 실사용 보고([·])의
  //    최후 안전망. IME·배열이 뭐라 하든 스캔코드 위치는 변하지 않는다.
  // [·]는 같은 기능의 예비 키다 — 어느 쪽이든 손에 맞는 걸 쓰면 된다.
  const delayKeys = ['.', '>', '[', '{'];
  const advanceKeys = ['/', '?', ']', '}'];
  if (key == LogicalKeyboardKey.period ||
      key == LogicalKeyboardKey.greater ||
      key == LogicalKeyboardKey.bracketLeft ||
      key == LogicalKeyboardKey.braceLeft) {
    return lyricsNudgeStepMs;
  }
  if (key == LogicalKeyboardKey.slash ||
      key == LogicalKeyboardKey.question ||
      key == LogicalKeyboardKey.bracketRight ||
      key == LogicalKeyboardKey.braceRight) {
    return -lyricsNudgeStepMs;
  }
  final ch = character;
  if (ch != null) {
    if (delayKeys.contains(ch)) return lyricsNudgeStepMs;
    if (advanceKeys.contains(ch)) return -lyricsNudgeStepMs;
  }
  if (physicalKey == PhysicalKeyboardKey.period ||
      physicalKey == PhysicalKeyboardKey.bracketLeft) {
    return lyricsNudgeStepMs;
  }
  if (physicalKey == PhysicalKeyboardKey.slash ||
      physicalKey == PhysicalKeyboardKey.bracketRight) {
    return -lyricsNudgeStepMs;
  }
  return null;
}

/// O=이전 줄(-1), P=다음 줄(+1). 해당 키가 아니면 null. (순수 함수 — 테스트 대상)
///
/// .·/와 같은 다겹 판정이다 — 논리 키·실제 입력 문자·물리 키(자판 위치)
/// 순서로 받는다. 이 기기에서 논리 키 매핑이 어긋나는 실사용 보고(.·/)가
/// 있었으므로 글자 키에도 같은 안전망을 깐다. 한글 자판에서 O·P 자리는 ㅐ·ㅔ다.
int? stepLineFor(
  LogicalKeyboardKey key, {
  String? character,
  PhysicalKeyboardKey? physicalKey,
}) {
  if (key == LogicalKeyboardKey.keyO) return -1;
  if (key == LogicalKeyboardKey.keyP) return 1;
  const prevChars = ['o', 'O', 'ㅐ'];
  const nextChars = ['p', 'P', 'ㅔ'];
  final ch = character;
  if (ch != null) {
    if (prevChars.contains(ch)) return -1;
    if (nextChars.contains(ch)) return 1;
  }
  if (physicalKey == PhysicalKeyboardKey.keyO) return -1;
  if (physicalKey == PhysicalKeyboardKey.keyP) return 1;
  return null;
}

/// 홈과 무대(전체화면)가 **똑같이** 쓰는 동작 묶음.
///
/// 예전에는 단축키 하나를 추가할 때마다 홈 배선과 무대 배선을 따로
/// 고쳐야 했고, 실제로 E 편집·싱크 줄이 무대에서 빠지는 사고가 났다
/// (사용자: "두 군데 수정하는 거 너무 비효율적"). 이제 화면(State)이
/// 이 묶음을 한 번 만들고 홈 스코프와 무대가 같은 객체를 소비한다 —
/// 새 동작은 여기 필드 하나 + 스코프 처리기 한 곳이면 양쪽에 다 걸린다.
class PrompterActions {
  final VoidCallback? togglePlayPause;
  final VoidCallback? toggleRecording;
  final VoidCallback? resetLyricsSync;
  final VoidCallback? anchorFirstLine;
  final ValueChanged<int>? nudgeLyricsOffset;

  /// 한 줄 간격만큼 싱크 이동(Ctrl+←/→). +1=늦춤, -1=앞당김 —
  /// [nudgeLyricsOffset]과 같은 부호 규약.
  final ValueChanged<int>? nudgeLyricsOffsetLine;

  /// 현재 줄부터 아래만 밀기(Alt+←/→, ms). LRC 타임스탬프를 직접 고친다 —
  /// 위 줄은 그대로 두는 부분 보정. 부호 규약은 [nudgeLyricsOffset]과 같다.
  final ValueChanged<int>? nudgeLyricsFromCurrentLine;

  /// 싱크 잠금 토글(L). 잠그면 싱크 조절 동작 전부가 거부된다.
  final VoidCallback? toggleSyncLock;
  final ValueChanged<int>? stepLine;
  final void Function(int index, String text)? editLyricsLine;
  final VoidCallback? jumpToStart;
  final VoidCallback? jumpToEnd;
  final ValueChanged<Duration>? seekRelative;

  const PrompterActions({
    this.togglePlayPause,
    this.toggleRecording,
    this.resetLyricsSync,
    this.anchorFirstLine,
    this.nudgeLyricsOffset,
    this.nudgeLyricsOffsetLine,
    this.nudgeLyricsFromCurrentLine,
    this.toggleSyncLock,
    this.stepLine,
    this.editLyricsLine,
    this.jumpToStart,
    this.jumpToEnd,
    this.seekRelative,
  });
}

class PrompterKeyboardScope extends StatefulWidget {
  final Widget child;
  final PrompterSettings settings;
  final ValueChanged<PrompterSettings> onSettingsChanged;

  /// 홈·무대 공용 동작 묶음. 단축키 매핑:
  /// Space=재생/일시정지 · R=녹음 · T=싱크 리셋 · O/P=이전/다음 줄 ·
  /// .[=늦추기·/]=앞당기기 · Home/End=곡 처음/끝 · ←/→=5초(Shift 30초).
  final PrompterActions? actions;

  /// F5 — 무대 열기(홈 전용, 무대에서는 null).
  final VoidCallback? onOpenPrompter;

  /// ESC — 닫기(무대 전용).
  final VoidCallback? onClose;

  /// E — 현재 가사 줄 편집 트리거. 편집 요청 상태가 화면마다 살아서
  /// 이것만 화면 소유로 남는다(저장 경로는 actions.editLyricsLine 공용).
  final VoidCallback? onEditCurrentLine;

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
    this.actions,
    this.onOpenPrompter,
    this.onClose,
    this.onEditCurrentLine,
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
    // 포커스 자가복구 — 다이얼로그·팝업 메뉴가 닫히면서 포커스가 아무 데도
    // 안 남으면(루트로 떨어지면) 글자 단축키 전부가 조용히 죽는다.
    // 실사용 보고: 곡 수정 창을 닫은 직후 O/P·[·]이 안 먹음. 화면을 한 번
    // 클릭해야 살아나는데, 그 클릭을 사람에게 시키지 말고 여기서 되찾는다.
    FocusManager.instance.addListener(_onGlobalFocusChanged);
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
    FocusManager.instance.removeListener(_onGlobalFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onGlobalFocusChanged() {
    if (!mounted || !widget.enabled) return;
    final primary = FocusManager.instance.primaryFocus;
    // 진짜 위젯(텍스트 입력·버튼 등)에 포커스가 남아 있으면 건드리지
    // 않는다 — 키는 어차피 위로 버블된다. 루트(context 없음)나 스코프
    // 노드에 걸쳐 있으면 아무도 키를 안 받는 상태다.
    final orphaned =
        primary == null || primary.context == null || primary is FocusScopeNode;
    if (!orphaned) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestScopeFocus());
  }

  /// 화면 어딘가를 클릭하면 단축키 포커스를 되찾는다. 텍스트 입력이 포커스를
  /// 쥔 채라면, 클릭 지점에 입력창이 **없을 때만** 포커스를 풀어 준다 —
  /// 검색창을 만진 뒤 빈 곳을 눌러도 단축키가 죽어 있던 문제의 해법.
  /// (입력창 자체를 누른 클릭은 타이핑 의도이므로 놔둔다)
  void _onPointerDown(PointerDownEvent event) {
    if (SongListShortcutService.isTextInputFocused()) {
      final result = HitTestResult();
      WidgetsBinding.instance.hitTestInView(
        result,
        event.position,
        View.of(context).viewId,
      );
      final onEditable = result.path.any((e) => e.target is RenderEditable);
      if (onEditable) return;
      FocusManager.instance.primaryFocus?.unfocus();
    }
    _requestScopeFocus();
  }

  void _requestScopeFocus() {
    if (!mounted) return;
    if (!widget.enabled) return;
    if (SongListShortcutService.isTextInputFocused()) return;
    // 무대(전체화면)가 위에 떠 있으면 홈 스코프는 손대지 않는다 —
    // 두 스코프가 자가복구로 서로 포커스를 뺏는 것을 막는다.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    _focusNode.requestFocus();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    // 꺼진 탭에서는 아무 키도 삼키지 않는다 — 그 탭의 위젯(목록 이동 등)이
    // 키를 정상적으로 받아야 한다.
    if (!widget.enabled) return KeyEventResult.ignored;
    if (event is KeyUpEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    if (SongListShortcutService.isTextInputFocused()) {
      // ESC = 입력 포커스 해제. 검색창 등이 포커스를 쥐면 단축키가 전부
      // 멎는데("먹었다 안먹었다"의 주범), 확실하게 빠져나오는 키를 둔다.
      // 인라인 가사 편집기는 자기 ESC(저장)를 먼저 처리하므로 안 온다.
      if (event is KeyDownEvent && key == LogicalKeyboardKey.escape) {
        FocusManager.instance.primaryFocus?.unfocus();
        _requestScopeFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // 싱크 밀고 당기기는 꾹 누르면 반복되는 게 자연스럽다 — 반복 이벤트도
    // 받는다. 나머지 단축키는 최초 눌림만(토글이 튀지 않게).
    final nudge = lyricsNudgeFor(
      key,
      character: event.character,
      physicalKey: event.physicalKey,
    );
    if (nudge != null && widget.actions?.nudgeLyricsOffset != null) {
      widget.actions!.nudgeLyricsOffset!(nudge);
      return KeyEventResult.handled;
    }

    // O/P = 이전/다음 줄 — 맨휠 줄 이동의 후임. 반복 이벤트도 받아
    // 꾹 누르면 죽 넘어간다.
    final stepLine = widget.actions?.stepLine;
    if (stepLine != null) {
      final step = stepLineFor(
        key,
        character: event.character,
        physicalKey: event.physicalKey,
      );
      if (step != null) {
        stepLine(step);
        return KeyEventResult.handled;
      }
    }

    // 화살표 — ←/→ = 싱크 늦춤/앞당김, ↑/↓ = 이전/다음 줄. (v3.6.0)
    // 문장부호·글자 키가 환경(IME·자판)에 따라 안 먹는 실사용 보고로,
    // 어디서나 확실히 오는 화살표를 본대로 삼는다. 원래 기능은 Shift로:
    // Shift+←/→ = 30초 이동, Shift+↑/↓ = 볼륨. 꾹 누르면 연속(반복 수용).
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final alt = HardwareKeyboard.instance.isAltPressed;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final back = key == LogicalKeyboardKey.arrowLeft;
      // Alt+←/→ = 현재 줄부터 아래만 0.2초 밀기 (부분 보정 — 위는 그대로).
      if (alt) {
        final partialCb = widget.actions?.nudgeLyricsFromCurrentLine;
        if (partialCb != null) {
          partialCb(back ? lyricsNudgeStepMs : -lyricsNudgeStepMs);
          return KeyEventResult.handled;
        }
      }
      // Ctrl+←/→ = 한 줄 간격만큼 싱크 이동 (0.2초 걸음보다 굵은 조절).
      if (ctrl) {
        final lineCb = widget.actions?.nudgeLyricsOffsetLine;
        if (lineCb != null) {
          lineCb(back ? 1 : -1);
          return KeyEventResult.handled;
        }
      } else if (shift) {
        final seekCb = widget.actions?.seekRelative;
        if (seekCb != null) {
          seekCb(
            back
                ? -SongListShortcutService.seekStepLarge
                : SongListShortcutService.seekStepLarge,
          );
          return KeyEventResult.handled;
        }
      } else {
        final nudgeCb = widget.actions?.nudgeLyricsOffset;
        if (nudgeCb != null) {
          nudgeCb(back ? lyricsNudgeStepMs : -lyricsNudgeStepMs);
          return KeyEventResult.handled;
        }
        // 싱크 대상이 없는 화면에서는 예전처럼 5초 이동으로.
        final seekCb = widget.actions?.seekRelative;
        if (seekCb != null) {
          seekCb(
            back
                ? -SongListShortcutService.seekStep
                : SongListShortcutService.seekStep,
          );
          return KeyEventResult.handled;
        }
      }
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final up = key == LogicalKeyboardKey.arrowUp;
      if (!shift && stepLine != null) {
        stepLine(up ? -1 : 1);
        return KeyEventResult.handled;
      }
      final adjusted = SongListShortcutService.adjustSettings(
        widget.settings,
        up ? LogicalKeyboardKey.arrowUp : LogicalKeyboardKey.arrowDown,
      );
      if (adjusted != null) {
        widget.onSettingsChanged(adjusted);
        return KeyEventResult.handled;
      }
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.escape && widget.onClose != null) {
      widget.onClose!();
      return KeyEventResult.handled;
    }

    // R = 녹음 시작/중지. 텍스트 입력 중에는 위 가드가 이미 걸러 준다.
    if (key == LogicalKeyboardKey.keyR &&
        widget.actions?.toggleRecording != null) {
      widget.actions!.toggleRecording!();
      return KeyEventResult.handled;
    }

    // T = 싱크 리셋(오프셋 0으로). 밀고 당기다 어긋나면 처음부터.
    if (key == LogicalKeyboardKey.keyT &&
        widget.actions?.resetLyricsSync != null) {
      widget.actions!.resetLyricsSync!();
      return KeyEventResult.handled;
    }

    // L = 싱크 잠금 토글. 다 맞춘 싱크를 오타로 망가뜨리지 않는 자물쇠.
    if ((key == LogicalKeyboardKey.keyL ||
            event.physicalKey == PhysicalKeyboardKey.keyL) &&
        widget.actions?.toggleSyncLock != null) {
      widget.actions!.toggleSyncLock!();
      return KeyEventResult.handled;
    }

    // E = 현재 줄 인라인 편집. 받아쓰기 오탈자를 노래 중에 바로 고친다.
    if (key == LogicalKeyboardKey.keyE && widget.onEditCurrentLine != null) {
      widget.onEditCurrentLine!();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.home &&
        widget.actions?.jumpToStart != null) {
      widget.actions!.jumpToStart!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end &&
        widget.actions?.jumpToEnd != null) {
      widget.actions!.jumpToEnd!();
      return KeyEventResult.handled;
    }

    if (widget.enablePlaybackShortcuts) {
      if (key == LogicalKeyboardKey.space &&
          widget.actions?.togglePlayPause != null) {
        widget.actions!.togglePlayPause!();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.f5 && widget.onOpenPrompter != null) {
        widget.onOpenPrompter!();
        return KeyEventResult.handled;
      }
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
            onPointerDown: _onPointerDown,
            child: widget.child,
          ),
        ),
      ),
    );
  }

  Map<ShortcutActivator, Intent> get _shortcutMap {
    return {
      // ↑/↓ = 이전/다음 줄, Shift+↑/↓ = 볼륨. 줄 이동 대상이 없으면
      // 예전처럼 볼륨으로.
      if (widget.actions?.stepLine != null) ...{
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            const _StepLineIntent(-1),
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            const _StepLineIntent(1),
      } else ...{
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            const _VolumeUpIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            const _VolumeDownIntent(),
      },
      const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true):
          const _VolumeUpIntent(),
      const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true):
          const _VolumeDownIntent(),
      // ←/→ = 싱크 늦춤/앞당김, Shift+←/→ = 30초 이동. 싱크 대상이
      // 없으면 예전처럼 5초 이동으로.
      if (widget.actions?.nudgeLyricsOffset != null) ...{
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const _NudgeLyricsIntent(delay: true),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const _NudgeLyricsIntent(delay: false),
      } else if (widget.actions?.seekRelative != null) ...{
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const _SeekBackIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const _SeekForwardIntent(),
      },
      if (widget.actions?.seekRelative != null) ...{
        const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
            const _SeekBackIntent(large: true),
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
            const _SeekForwardIntent(large: true),
      },
      if (widget.actions?.nudgeLyricsOffsetLine != null) ...{
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            const _NudgeLineIntent(delay: true),
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            const _NudgeLineIntent(delay: false),
      },
      if (widget.actions?.nudgeLyricsFromCurrentLine != null) ...{
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
            const _NudgeFromLineIntent(delay: true),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
            const _NudgeFromLineIntent(delay: false),
      },
      if (widget.enablePlaybackShortcuts) ...{
        const SingleActivator(LogicalKeyboardKey.space):
            const _TogglePlayPauseIntent(),
        const SingleActivator(LogicalKeyboardKey.f5): const _OpenPrompterIntent(),
      },
      if (widget.onClose != null)
        const SingleActivator(LogicalKeyboardKey.escape): const _CloseIntent(),
      if (widget.actions?.jumpToStart != null)
        const SingleActivator(LogicalKeyboardKey.home):
            const _JumpToStartIntent(),
      if (widget.actions?.jumpToEnd != null)
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
      if (widget.actions?.stepLine != null)
        _StepLineIntent: CallbackAction<_StepLineIntent>(
          onInvoke: (intent) {
            if (SongListShortcutService.isTextInputFocused()) return null;
            widget.actions!.stepLine!(intent.step);
            return null;
          },
        ),
      if (widget.actions?.nudgeLyricsOffset != null)
        _NudgeLyricsIntent: CallbackAction<_NudgeLyricsIntent>(
          onInvoke: (intent) {
            if (SongListShortcutService.isTextInputFocused()) return null;
            widget.actions!.nudgeLyricsOffset!(
              intent.delay ? lyricsNudgeStepMs : -lyricsNudgeStepMs,
            );
            return null;
          },
        ),
      if (widget.actions?.nudgeLyricsOffsetLine != null)
        _NudgeLineIntent: CallbackAction<_NudgeLineIntent>(
          onInvoke: (intent) {
            if (SongListShortcutService.isTextInputFocused()) return null;
            widget.actions!.nudgeLyricsOffsetLine!(intent.delay ? 1 : -1);
            return null;
          },
        ),
      if (widget.actions?.nudgeLyricsFromCurrentLine != null)
        _NudgeFromLineIntent: CallbackAction<_NudgeFromLineIntent>(
          onInvoke: (intent) {
            if (SongListShortcutService.isTextInputFocused()) return null;
            widget.actions!.nudgeLyricsFromCurrentLine!(
              intent.delay ? lyricsNudgeStepMs : -lyricsNudgeStepMs,
            );
            return null;
          },
        ),
      if (widget.actions?.seekRelative != null) ...{
        _SeekForwardIntent: CallbackAction<_SeekForwardIntent>(
          onInvoke: (intent) {
            if (SongListShortcutService.isTextInputFocused()) return null;
            widget.actions!.seekRelative!(
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
            widget.actions!.seekRelative!(
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
            widget.actions?.togglePlayPause?.call();
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
      if (widget.actions?.jumpToStart != null)
        _JumpToStartIntent: CallbackAction<_JumpToStartIntent>(
          onInvoke: (_) {
            widget.actions?.jumpToStart?.call();
            return null;
          },
        ),
      if (widget.actions?.jumpToEnd != null)
        _JumpToEndIntent: CallbackAction<_JumpToEndIntent>(
          onInvoke: (_) {
            widget.actions?.jumpToEnd?.call();
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

/// ↑/↓ 줄 이동. step: -1=이전, 1=다음.
class _StepLineIntent extends Intent {
  final int step;
  const _StepLineIntent(this.step);
}

/// ←/→ 싱크 조절. delay=true면 늦춤(+), false면 앞당김(−).
class _NudgeLyricsIntent extends Intent {
  final bool delay;
  const _NudgeLyricsIntent({required this.delay});
}

/// Ctrl+←/→ 한 줄 간격 싱크 조절. delay 규약은 [_NudgeLyricsIntent]와 같다.
class _NudgeLineIntent extends Intent {
  final bool delay;
  const _NudgeLineIntent({required this.delay});
}

/// Alt+←/→ 현재 줄부터 아래만 밀기. delay 규약은 [_NudgeLyricsIntent]와 같다.
class _NudgeFromLineIntent extends Intent {
  final bool delay;
  const _NudgeFromLineIntent({required this.delay});
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
