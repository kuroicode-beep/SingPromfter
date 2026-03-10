import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/song.dart';
import '../theme/app_theme.dart';

class PrompterScreen extends StatefulWidget {
  final Song song;
  final double fontSize;
  final double lineHeight;
  final String? fontFamily;
  final bool boldText;

  const PrompterScreen({
    super.key,
    required this.song,
    required this.fontSize,
    required this.lineHeight,
    this.fontFamily,
    this.boldText = false,
  });

  @override
  State<PrompterScreen> createState() => _PrompterScreenState();
}

class _PrompterScreenState extends State<PrompterScreen> {
  final _scrollController = ScrollController();
  bool _controlsVisible = true;

  late double _fontSize;
  late double _lineHeight;

  @override
  void initState() {
    super.initState();
    _fontSize = widget.fontSize;
    _lineHeight = widget.lineHeight;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _scrollController.dispose();
    super.dispose();
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

  void _toggleControls() => setState(() => _controlsVisible = !_controlsVisible);

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
              padding: EdgeInsets.fromLTRB(32, _controlsVisible ? 80 : 48, 32, 120),
              child: Center(
                child: Text(
                  widget.song.lyricsText.isEmpty ? '(가사가 없습니다)' : widget.song.lyricsText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: _fontSize,
                    height: _lineHeight,
                    fontFamily: widget.fontFamily,
                    fontWeight: widget.boldText ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ),
            ),
            if (_controlsVisible) ...[
              _buildTopBar(),
              _buildSizeControls(),
            ],
            _buildScrollButtons(),
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
                icon: const Icon(Icons.touch_app_outlined, color: Colors.white38, size: 20),
                onPressed: _toggleControls,
                tooltip: '컨트롤 숨기기',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSizeControls() {
    return Positioned(
      top: 72,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          children: [
            const Text('크기', style: TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 4),
            _RoundBtn(
              icon: Icons.text_increase,
              onTap: () => setState(() => _fontSize = (_fontSize + 4).clamp(16, 80)),
            ),
            const SizedBox(height: 6),
            _RoundBtn(
              icon: Icons.text_decrease,
              onTap: () => setState(() => _fontSize = (_fontSize - 4).clamp(16, 80)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollButtons() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _controlsVisible ? 1.0 : 0.25,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black, Colors.transparent],
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ScrollBtn(
                icon: Icons.keyboard_arrow_up,
                onTap: () => _scroll(-200),
              ),
              const SizedBox(width: 24),
              _ScrollBtn(
                icon: Icons.keyboard_arrow_down,
                onTap: () => _scroll(200),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white70, size: 18),
      ),
    );
  }
}

class _ScrollBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ScrollBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: const Color(0xFF0A0A0A), size: 32),
      ),
    );
  }
}
