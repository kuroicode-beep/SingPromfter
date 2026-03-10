import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/song.dart';

class PrompterScreen extends StatefulWidget {
  final Song song;
  final double fontSize;
  final double lineHeight;
  final double? fontSizeLevel;
  final double? lineHeightLevel;
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
  late double _speedLevel;
  late bool _autoScrollEnabled;

  @override
  void initState() {
    super.initState();
    _fontSizeLevel = widget.fontSizeLevel ?? _fontSizeToLevel(widget.fontSize);
    _lineHeightLevel =
        widget.lineHeightLevel ?? _lineHeightToLevel(widget.lineHeight);
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

  double get _fontSize => _fontSizeForLevel(_fontSizeLevel);

  double get _lineHeight => _lineHeightForLevel(_lineHeightLevel);

  double _fontSizeForLevel(double level) {
    if (level <= 1) return 18;
    if (level <= 2) return 24;
    if (level <= 3) return 32;
    if (level <= 4) return 42;
    return 56;
  }

  double _lineHeightForLevel(double level) {
    if (level <= 1) return 1.4;
    if (level <= 2) return 1.6;
    if (level <= 3) return 1.9;
    if (level <= 4) return 2.2;
    return 2.6;
  }

  double _fontSizeToLevel(double value) {
    if (value <= 18) return 1;
    if (value <= 24) return 2;
    if (value <= 32) return 3;
    if (value <= 42) return 4;
    return 5;
  }

  double _lineHeightToLevel(double value) {
    if (value <= 1.4) return 1;
    if (value <= 1.6) return 2;
    if (value <= 1.9) return 3;
    if (value <= 2.2) return 4;
    return 5;
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

    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (!_autoScrollEnabled || !_scrollController.hasClients) return;
      final delta = _speedLevel * 1.4;
      final next = (_scrollController.offset + delta).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.jumpTo(next);
    });
  }

  void _updateFontSizeLevel(double value) {
    setState(() => _fontSizeLevel = value);
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
                    max: 5,
                    divisions: 4,
                    onChanged: _updateFontSizeLevel,
                  ),
                  const SizedBox(width: 10),
                  _InlineSlider(
                    label: '줄간격',
                    value: _lineHeightLevel,
                    min: 1,
                    max: 5,
                    divisions: 4,
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
                    onTap: () => _scroll(-200),
                  ),
                  const SizedBox(width: 6),
                  _BarIconButton(
                    icon: Icons.keyboard_arrow_down,
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
  final ValueChanged<double> onChanged;

  const _InlineSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                min: min,
                max: max,
                divisions: divisions,
                value: value,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _BarIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white70, size: 18),
      ),
    );
  }
}
