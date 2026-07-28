import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/playback_controller.dart';
import '../models/prompter_display_mode.dart';
import '../models/prompter_settings.dart';
import '../models/song.dart';
import '../theme/app_theme.dart';
import '../theme/prompter_levels.dart';
import '../utils/music_key.dart';
import '../utils/pitch_math.dart';
import '../widgets/pitch_hud.dart';
import '../widgets/prompter_eq_meter.dart';
import '../widgets/prompter_drawer.dart';
import '../widgets/prompter_stage_metrics.dart';
import '../widgets/prompter_lyrics_view.dart';
import '../widgets/prompter_sweep_line.dart';
import '../widgets/prompter_progress_bar.dart';
import '../widgets/prompter_keyboard_scope.dart';
import '../widgets/prompter_wheel_scope.dart';

class PrompterScreen extends StatefulWidget {
  final Song song;

  /// 재생 위치·하이라이트 줄을 이 컨트롤러에서 직접 구독한다.
  /// (값으로 넘기면 라우트가 리빌드되지 않아 위치가 멈춘다)
  final PlaybackController playback;

  final double fontSize;
  final double lineHeight;
  final double? fontSizeLevel;
  final double? lineHeightLevel;
  final double? customFontSizePt;
  final double volume;
  final String? fontFamily;
  final bool boldText;
  final PrompterDisplayMode displayMode;
  final bool showEqMeter;

  /// Shift+휠 — 템포. null이면 아무 일도 하지 않는다.
  final void Function(double delta)? onStepTempo;

  /// 하단 조작판을 펼쳐 둘지. 접혀도 손잡이는 항상 보인다.
  final bool controlsDrawerOpen;
  final ValueChanged<bool>? onControlsDrawerChanged;

  /// 현재 줄을 한 글자씩 밝힐지.
  final bool showSyllableSweep;

  /// Alt+휠 키 조절. null이면 무대에서 키를 바꿀 수 없다.
  final void Function(int delta)? onStepPitch;

  /// 조절 중인 키(적용 대기 값). null이면 표시하지 않는다.
  final ValueListenable<int?>? pendingPitch;

  /// 사용자 키를 얹기 전의 슬롯 조성 — HUD가 여기에 조절값을 더한다.
  final MusicKey? songKey;

  /// 지금 들리는 조성. 상단 바에 상시 표시한다.
  final MusicKey? soundingKey;
  final ValueChanged<PrompterDisplayMode>? onDisplayModeChanged;
  final ValueChanged<double>? onFontSizeLevelChanged;
  final ValueChanged<double>? onLineHeightLevelChanged;
  final ValueChanged<double>? onVolumeChanged;

  const PrompterScreen({
    super.key,
    required this.song,
    required this.playback,
    required this.fontSize,
    required this.lineHeight,
    this.fontSizeLevel,
    this.lineHeightLevel,
    this.customFontSizePt,
    this.volume = 1,
    this.fontFamily,
    this.boldText = false,
    this.displayMode = PrompterDisplayMode.full,
    this.showEqMeter = true,
    this.showSyllableSweep = true,
    this.controlsDrawerOpen = false,
    this.onControlsDrawerChanged,
    this.onStepPitch,
    this.onStepTempo,
    this.pendingPitch,
    this.songKey,
    this.soundingKey,
    this.onDisplayModeChanged,
    this.onFontSizeLevelChanged,
    this.onLineHeightLevelChanged,
    this.onVolumeChanged,
  });

  @override
  State<PrompterScreen> createState() => _PrompterScreenState();
}

class _PrompterScreenState extends State<PrompterScreen> {
  final _scrollController = ScrollController();

  bool _controlsVisible = true;

  /// 드로어 애니메이션 진행도(0=닫힘, 1=열림).
  /// 무대 크기 계산에 쓴다 — 접히는 동안 밴드가 리사이즈되면 가사가 통째로
  /// 재레이아웃되기 때문에, 언제나 "열린 상태" 크기를 기준으로 잡는다.
  Animation<double>? _drawerAnim;
  late double _fontSizeLevel;
  late double _lineHeightLevel;
  late double? _customFontSizePt;
  late PrompterDisplayMode _displayMode;

  @override
  void initState() {
    super.initState();
    _fontSizeLevel = widget.fontSizeLevel ?? _fontSizeToLevel(widget.fontSize);
    _lineHeightLevel =
        widget.lineHeightLevel ?? _lineHeightToLevel(widget.lineHeight);
    _customFontSizePt = widget.customFontSizePt;
    _displayMode = widget.displayMode;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _sizeHintTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _scrollController.dispose();
    super.dispose();
  }

  PrompterSettings get _keyboardSettings => PrompterSettings(
    fontSizeLevel: _fontSizeLevel,
    lineHeightLevel: _lineHeightLevel,
    volume: widget.volume,
    fontFamily: widget.fontFamily ?? '기본',
    boldText: widget.boldText,
    customFontSizePt: _customFontSizePt,
    displayMode: _displayMode,
  );

  void _applyKeyboardSettings(PrompterSettings next) {
    if (next.volume != widget.volume) {
      widget.onVolumeChanged?.call(next.volume);
    }
  }

  double get _fontSize =>
      _customFontSizePt ?? PrompterLevels.fontSizeForLevel(_fontSizeLevel);

  double get _lineHeight => PrompterLevels.lineHeightForLevel(_lineHeightLevel);

  double _fontSizeToLevel(double value) {
    return PrompterLevels.levelForFontSize(value);
  }

  double _lineHeightToLevel(double value) {
    return PrompterLevels.levelForLineHeight(value);
  }

  void _scroll(double delta) {
    final target = (_scrollController.offset + delta).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _toggleDisplayMode() {
    setState(() {
      _displayMode = _displayMode == PrompterDisplayMode.full
          ? PrompterDisplayMode.highlight
          : PrompterDisplayMode.full;
    });
    widget.onDisplayModeChanged?.call(_displayMode);
  }

  void _updateFontSizeLevel(double value) {
    setState(() {
      _fontSizeLevel = value;
      _customFontSizePt = null;
    });
    widget.onFontSizeLevelChanged?.call(value);
  }

  void _updateLineHeightLevel(double value) {
    setState(() => _lineHeightLevel = value);
    widget.onLineHeightLevelChanged?.call(value);
  }

  void _toggleControls() =>
      setState(() => _controlsVisible = !_controlsVisible);

  @override
  Widget build(BuildContext context) {
    // 무대 가사는 자체 글자 크기(레벨)를 쓰므로 앱 전역 배율을 초기화해
    // 배율 중첩으로 인한 오버플로를 방지한다.
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: PrompterKeyboardScope(
        settings: _keyboardSettings,
        enablePlaybackShortcuts: false,
        onSettingsChanged: _applyKeyboardSettings,
        onClose: () => Navigator.pop(context),
        onJumpToStart: widget.playback.jumpToStart,
        onJumpToEnd: widget.playback.jumpToEnd,
        onSeekRelative: widget.playback.seekRelative,
        child: PrompterWheelScope(
          onStepLine: widget.playback.stepLine,
          onStepFontSize: _stepFontSize,
          onStepPitch: widget.onStepPitch,
          onStepTempo: widget.onStepTempo == null
              ? null
              : (delta) => widget.onStepTempo!(delta * tempoStep),
          child: Scaffold(
            backgroundColor: Colors.black,
            // 하단 바를 Stack 오버레이가 아니라 Column 형제로 둔다.
            // 겹침을 상수로 어림잡지 않고 레이아웃 구조로 불가능하게 만든다
            // (이전에는 하단 바가 EQ 미터를 덮어 막대가 보이지 않았다).
            body: Column(
              children: [
                Expanded(child: _buildStage()),
                _buildBottomBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Ctrl+휠 글자 크기. 커스텀 pt가 잡혀 있으면 레벨로 환산한 뒤 옮긴다.
  void _stepFontSize(int delta) {
    final base = _customFontSizePt != null
        ? PrompterLevels.levelForFontSize(_customFontSizePt!)
        : _fontSizeLevel;
    final next = (base + delta).clamp(
      PrompterLevels.minLevel.toDouble(),
      PrompterLevels.maxLevel.toDouble(),
    );
    if (next == _fontSizeLevel && _customFontSizePt == null) return;
    _updateFontSizeLevel(next);
    _showSizeHint();
  }

  Timer? _sizeHintTimer;
  bool _sizeHintVisible = false;

  /// 크기를 바꾸면 잠깐 숫자로 알려 준다(색이 아니라 글자로).
  void _showSizeHint() {
    _sizeHintTimer?.cancel();
    if (!_sizeHintVisible) setState(() => _sizeHintVisible = true);
    _sizeHintTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _sizeHintVisible = false);
    });
  }

  /// 무대 영역 — 가사 + EQ 밴드 + 상단 바.
  ///
  /// 가사 뷰포트를 EQ 밴드 높이만큼 잘라(Positioned.fill의 bottom) 스크롤
  /// 중에도 가사 픽셀이 밴드로 넘어오지 못하게 한다. 패딩만으로는 스크롤
  /// 중 통과를 막을 수 없다.
  Widget _buildStage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stage = Size(constraints.maxWidth, constraints.maxHeight);
        // 드로어가 접힌 만큼 무대가 더 커져 있다. 그 몫을 빼 "열린 상태"
        // 크기로 계산해야 애니메이션 내내 밴드·뷰포트가 상수로 남는다.
        final hidden =
            PrompterStageMetrics.stageDrawerHeight *
            (1 - (_drawerAnim?.value ?? (widget.controlsDrawerOpen ? 1 : 0)));
        final stable = PrompterStageMetrics.stableStage(
          stage,
          hiddenDrawerHeight: hidden,
        );
        final band = PrompterStageMetrics.bandHeight(
          stable,
          showEq: widget.showEqMeter,
        );
        final meter = PrompterStageMetrics.meterSize(
          stable,
          showEq: widget.showEqMeter,
        );
        return Stack(
          children: [
            // Positioned.fill(bottom:)이 아니라 상단 고정 + 명시 높이.
            // 무대가 커지는 동안에도 가사 뷰포트가 흔들리지 않는다.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: (stable.height - band).clamp(0.0, double.infinity),
              child: AnimatedBuilder(
                // 줄 번호뿐 아니라 가사 도착·따라가기 토글에도 다시 그린다.
                animation: Listenable.merge([
                  widget.playback.lineIndex,
                  widget.playback.timedLyrics,
                  widget.playback.autoScrollPaused,
                ]),
                builder: (context, _) => PrompterLyricsView(
                  lyricsText: widget.song.lyricsText,
                  timedLyrics: widget.playback.timedLyrics.value,
                  displayMode: _displayMode,
                  fontSize: _fontSize,
                  lineHeight: _lineHeight,
                  fontFamily: widget.fontFamily,
                  boldText: widget.boldText,
                  highlightLineIndex: widget.playback.lineIndex.value,
                  scrollController: _scrollController,
                  padding: EdgeInsets.fromLTRB(
                    32,
                    _controlsVisible ? 72 : 40,
                    32,
                    24,
                  ),
                  textColor: Colors.white,
                  mutedColor: Colors.white70,
                  onLineTap: widget.playback.seekToLine,
                  autoFollow: !widget.playback.autoScrollPaused.value,
                  trackEnd: widget.playback.lyricsTrackEnd,
                  sweepBuilder: prompterSweepBuilder(
                    playback: widget.playback,
                    enabled: widget.showSyllableSweep,
                  ),
                ),
              ),
            ),
            if (widget.showEqMeter && !meter.isEmpty)
              Positioned(
                left: PrompterStageMetrics.meterInsetLeft,
                bottom: PrompterStageMetrics.meterInsetVertical,
                child: SizedBox.fromSize(
                  size: meter,
                  child: PrompterEqMeter(playback: widget.playback),
                ),
              ),
            if (_controlsVisible) _buildTopBar(),
            if (widget.pendingPitch != null)
              Positioned.fill(
                child: ValueListenableBuilder<int?>(
                  valueListenable: widget.pendingPitch!,
                  builder: (context, pitch, _) =>
                      PitchHud(semitones: pitch, songKey: widget.songKey),
                ),
              ),
            if (_sizeHintVisible)
              Positioned(
                top: 16,
                right: 16,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: AppShapes.controlRadius,
                      border: Border.all(color: AppColors.primary),
                    ),
                    child: Text(
                      '글자 크기 ${_fontSize.round()}pt',
                      style: AppTypography.mono.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            // 컨트롤 토글은 가사·미터보다 아래에 둬 줄 탭을 가로채지 않는다.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _toggleControls,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, Colors.transparent],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 28),
                onPressed: () => Navigator.pop(context),
                tooltip: '닫기',
              ),
              Expanded(
                child: Text(
                  widget.song.title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.soundingKey != null) ...[
                Semantics(
                  label: '현재 조성 ${widget.soundingKey!.label}',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.tertiary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.soundingKey!.label,
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 18,
                        color: AppColors.tertiary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              IconButton(
                icon: const Icon(
                  Icons.touch_app_outlined,
                  color: Colors.white38,
                  size: 20,
                ),
                onPressed: _toggleControls,
                tooltip: '컨트롤 숨기기',
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 무대 하단 조작판.
  ///
  /// v2.7.0까지는 AnimatedOpacity(→0.2)라 **숨겨져도 자리를 먹고 클릭도
  /// 먹었다**. 이제 진짜로 접히고, 접힌 동안은 히트테스트·시맨틱이 죽는다.
  Widget _buildBottomBar() {
    return PrompterDrawer(
      open: widget.controlsDrawerOpen,
      onOpenChanged: (open) => widget.onControlsDrawerChanged?.call(open),
      label: '조작판',
      palette: PrompterDrawerPalette.stage,
      fixedHeight: PrompterStageMetrics.stageDrawerHeight,
      onAnimationReady: (anim) {
        _drawerAnim = anim;
        anim.addListener(() {
          if (mounted) setState(() {});
        });
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.76),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 재생 위치는 컨트롤러를 직접 구독한다 — 전체화면 진행바가
              // 멈춰 있던 문제(값 스냅샷 전달)를 여기서 해소한다.
              ValueListenableBuilder<PlaybackSnapshot>(
                valueListenable: widget.playback.state,
                builder: (context, snapshot, _) {
                  if (!snapshot.audioReady) return const SizedBox.shrink();
                  return ValueListenableBuilder<Duration>(
                    valueListenable: widget.playback.position,
                    builder: (context, position, _) => PrompterProgressBar(
                      position: position,
                      duration: snapshot.duration,
                      enabled: snapshot.audioReady,
                      onSeek: widget.playback.seek,
                      activeColor: AppColors.primary,
                      labelColor: Colors.white70,
                    ),
                  );
                },
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: widget.playback.autoScrollPaused,
                      builder: (context, paused, _) => _BarIconButton(
                        icon: paused ? Icons.play_circle : Icons.pause_circle,
                        semanticsLabel: paused
                            ? '가사 따라가기 켜기'
                            : '가사 따라가기 끄기',
                        toggled: !paused,
                        onTap: widget.playback.toggleAutoScrollPaused,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _BarIconButton(
                      icon: _displayMode == PrompterDisplayMode.highlight
                          ? Icons.format_line_spacing
                          : Icons.view_headline,
                      semanticsLabel:
                          _displayMode == PrompterDisplayMode.highlight
                          ? '전체 가사 모드'
                          : '줄 하이라이트 모드',
                      toggled: _displayMode == PrompterDisplayMode.highlight,
                      onTap: _toggleDisplayMode,
                    ),
                    const SizedBox(width: 10),
                    _InlineSlider(
                      label: '크기',
                      value: _fontSizeLevel,
                      min: 1,
                      max: 7,
                      divisions: 6,
                      semanticValue: '현재 ${_fontSize.round()} 포인트',
                      onChanged: _updateFontSizeLevel,
                    ),
                    const SizedBox(width: 10),
                    _InlineSlider(
                      label: '줄간격',
                      value: _lineHeightLevel,
                      min: 1,
                      max: 7,
                      divisions: 6,
                      onChanged: _updateLineHeightLevel,
                    ),
                    const SizedBox(width: 10),
                    _BarIconButton(
                      icon: Icons.keyboard_arrow_up,
                      semanticsLabel: '가사 위로 이동',
                      onTap: () => _scroll(-200),
                    ),
                    const SizedBox(width: 6),
                    _BarIconButton(
                      icon: Icons.keyboard_arrow_down,
                      semanticsLabel: '가사 아래로 이동',
                      onTap: () => _scroll(200),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? semanticValue;
  final ValueChanged<double> onChanged;

  const _InlineSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    this.semanticValue,
    required this.onChanged,
  });

  double get _step => divisions != null ? (max - min) / divisions! : 1;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label 조절',
      value: semanticValue ?? value.toStringAsFixed(value % 1 == 0 ? 0 : 1),
      child: SizedBox(
        width: 224,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Row(
              children: [
                _FullStepButton(
                  icon: Icons.remove,
                  semanticsLabel: '$label 줄이기',
                  onTap: () =>
                      onChanged((value - _step).clamp(min, max).toDouble()),
                ),
                Expanded(
                  child: Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 10,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 16,
                        ),
                      ),
                      child: Slider(
                        min: min,
                        max: max,
                        divisions: divisions,
                        value: value.clamp(min, max).toDouble(),
                        semanticFormatterCallback: (_) =>
                            semanticValue ??
                            '$label ${value.toStringAsFixed(1)}',
                        onChanged: onChanged,
                      ),
                    ),
                  ),
                ),
                _FullStepButton(
                  icon: Icons.add,
                  semanticsLabel: '$label 늘리기',
                  onTap: () =>
                      onChanged((value + _step).clamp(min, max).toDouble()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FullStepButton extends StatelessWidget {
  final IconData icon;
  final String semanticsLabel;
  final VoidCallback onTap;

  const _FullStepButton({
    required this.icon,
    required this.semanticsLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      button: true,
      enabled: true,
      child: SizedBox(
        width: 48,
        height: 48,
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, color: Colors.white70, size: 22),
          tooltip: semanticsLabel,
        ),
      ),
    );
  }
}

class _BarIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String semanticsLabel;
  final bool? toggled;

  const _BarIconButton({
    required this.icon,
    required this.onTap,
    required this.semanticsLabel,
    this.toggled,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      button: true,
      enabled: true,
      toggled: toggled,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(10),
          ),
          child: ExcludeSemantics(
            child: Icon(icon, color: Colors.white70, size: 22),
          ),
        ),
      ),
    );
  }
}
