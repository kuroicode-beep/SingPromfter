import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_constants.dart';
import '../models/song.dart';
import '../theme/prompter_levels.dart';

class PrompterScreen extends StatefulWidget {
  final Song song;
  final double fontSize;
  final double lineHeight;
  final double? fontSizeLevel;
  final double? lineHeightLevel;
  final double? customFontSizePt;
  final double speedLevel;
  final String? fontFamily;
  final bool boldText;
  final bool autoScrollEnabled;
  final ValueChanged<double>? onFontSizeLevelChanged;
  final ValueChanged<double>? onLineHeightLevelChanged;
  final ValueChanged<double>? onSpeedLevelChanged;

  const PrompterScreen({
    super.key,
    required this.song,
    required this.fontSize,
    required this.lineHeight,
    this.fontSizeLevel,
    this.lineHeightLevel,
    this.customFontSizePt,
    this.speedLevel = 0,
    this.fontFamily,
    this.boldText = false,
    this.autoScrollEnabled = false,
    this.onFontSizeLevelChanged,
    this.onLineHeightLevelChanged,
    this.onSpeedLevelChanged,
  });

  @override
  State<PrompterScreen> createState() => _PrompterScreenState();
}

class _PrompterScreenState extends State<PrompterScreen> {
  final _scrollController = ScrollController();
  Timer? _autoScrollTimer;

  bool _controlsVisible = true;
  late double _fontSizeLevel;
  late double _lineHeightLevel;
  late double? _customFontSizePt;
  late double _speedLevel;
  late bool _autoScrollEnabled;

  @override
  void initState() {
    super.initState();
    _fontSizeLevel = widget.fontSizeLevel ?? _fontSizeToLevel(widget.fontSize);
    _lineHeightLevel =
        widget.lineHeightLevel ?? _lineHeightToLevel(widget.lineHeight);
    _customFontSizePt = widget.customFontSizePt;
    _speedLevel = widget.speedLevel;
    _autoScrollEnabled = widget.autoScrollEnabled;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncAutoScroll());
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _scrollController.dispose();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!mounted) return false;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return true;
    }
    return false;
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

  void _syncAutoScroll() {
    _autoScrollTimer?.cancel();
    if (!_autoScrollEnabled ||
        _speedLevel <= 0 ||
        !_scrollController.hasClients) {
      return;
    }

    _autoScrollTimer = Timer.periodic(AppConstants.autoScrollInterval, (_) {
      if (!_autoScrollEnabled || !_scrollController.hasClients) return;
      final delta = PrompterLevels.scrollDeltaForSpeed(_speedLevel);
      final next = (_scrollController.offset + delta).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.jumpTo(next);
    });
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

  void _updateSpeedLevel(double value) {
    setState(() => _speedLevel = value);
    widget.onSpeedLevelChanged?.call(value);
    _syncAutoScroll();
  }

  void _toggleControls() =>
      setState(() => _controlsVisible = !_controlsVisible);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            SingleChildScrollView(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(
                32,
                _controlsVisible ? 80 : 48,
                32,
                110,
              ),
              child: Center(
                child: Text(
                  widget.song.lyricsText.isEmpty
                      ? '(가사가 없습니다)'
                      : widget.song.lyricsText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: _fontSize,
                    height: _lineHeight,
                    fontFamily: widget.fontFamily,
                    fontWeight: widget.boldText
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
              ),
            ),
            if (_controlsVisible) _buildTopBar(),
            _buildBottomBar(),
          ],
        ),
      ),
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

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _controlsVisible ? 1.0 : 0.2,
        duration: const Duration(milliseconds: 200),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.76),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _BarIconButton(
                    icon: _autoScrollEnabled
                        ? Icons.pause_circle
                        : Icons.play_circle,
                    semanticsLabel: _autoScrollEnabled
                        ? '자동 스크롤 끄기'
                        : '자동 스크롤 켜기',
                    toggled: _autoScrollEnabled,
                    onTap: () {
                      setState(() => _autoScrollEnabled = !_autoScrollEnabled);
                      _syncAutoScroll();
                    },
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
                  _InlineSlider(
                    label: '속도',
                    value: _speedLevel,
                    min: 0,
                    max: 10,
                    divisions: 20,
                    onChanged: _updateSpeedLevel,
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
                          semanticValue ?? '$label ${value.toStringAsFixed(1)}',
                      onChanged: onChanged,
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
