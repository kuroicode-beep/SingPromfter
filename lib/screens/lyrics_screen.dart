import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/song.dart';
import '../repository/song_repository.dart';
import '../theme/app_theme.dart';
import 'prompter_screen.dart';

class LyricsScreen extends StatefulWidget {
  final Song song;
  const LyricsScreen({super.key, required this.song});

  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen> {
  final _player = AudioPlayer();
  final _repo = SongRepository.instance;

  double _fontSize = 3;
  double _lineHeight = 3;
  double _volume = 1.0;

  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initAudio();
    WakelockPlus.enable();
  }

  Future<void> _initAudio() async {
    if (!widget.song.hasMr) return;
    final path = await _repo.getMrPath(widget.song.mrFileName!);
    if (path == null) return;
    try {
      await _player.setSourceDeviceFile(path);
    } catch (_) {}

    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state == PlayerState.playing);
    });
    _player.onPositionChanged.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
    });
    _player.onDurationChanged.listen((dur) {
      if (!mounted) return;
      setState(() => _duration = dur);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  double get _fontSizePt {
    if (_fontSize <= 1) return 18.0;
    if (_fontSize <= 2) return 24.0;
    if (_fontSize <= 3) return 32.0;
    if (_fontSize <= 4) return 42.0;
    return 56.0;
  }

  double get _lineHeightVal {
    if (_lineHeight <= 1) return 1.4;
    if (_lineHeight <= 2) return 1.6;
    if (_lineHeight <= 3) return 1.9;
    if (_lineHeight <= 4) return 2.2;
    return 2.6;
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          widget.song.title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.fullscreen),
            tooltip: '전체화면 프롬프터',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PrompterScreen(
                  song: widget.song,
                  fontSize: _fontSizePt,
                  lineHeight: _lineHeightVal,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Text(
                widget.song.lyrics.isEmpty ? '(가사 없음)' : widget.song.lyrics,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: _fontSizePt,
                  height: _lineHeightVal,
                ),
              ),
            ),
          ),
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildOptions(),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          if (widget.song.hasMr) ...[
            _buildProgress(),
            const SizedBox(height: 10),
            _buildPlayButtons(),
            const SizedBox(height: 10),
            _buildVolume(),
          ] else
            const Center(
              child: Text(
                'MR이 없습니다. 목록에서 MR을 추가해 주세요.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PrompterScreen(
                  song: widget.song,
                  fontSize: _fontSizePt,
                  lineHeight: _lineHeightVal,
                ),
              ),
            ),
            icon: const Icon(Icons.fullscreen),
            label: const Text('전체화면 프롬프터'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptions() {
    return Row(
      children: [
        Expanded(child: _buildSlider('글자 크기', _fontSize, (v) => setState(() => _fontSize = v))),
        const SizedBox(width: 16),
        Expanded(child: _buildSlider('줄 간격', _lineHeight, (v) => setState(() => _lineHeight = v))),
      ],
    );
  }

  Widget _buildSlider(String label, double value, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        Slider(min: 1, max: 5, divisions: 4, value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _buildProgress() {
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            min: 0,
            max: _duration.inMilliseconds.toDouble().clamp(1, double.infinity),
            value: _position.inMilliseconds.toDouble().clamp(
                  0,
                  _duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                ),
            onChanged: (v) => _player.seek(Duration(milliseconds: v.toInt())),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(_position),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              Text(_formatDuration(_duration),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlayButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _PlayBtn(
          icon: Icons.stop,
          label: '정지',
          onTap: () async {
            await _player.pause();
            await _player.seek(Duration.zero);
          },
          color: AppColors.elevated,
        ),
        const SizedBox(width: 12),
        _PlayBtn(
          icon: _playing ? Icons.pause : Icons.play_arrow,
          label: _playing ? '일시정지' : '재생',
          onTap: () => _playing ? _player.pause() : _player.resume(),
          color: AppColors.accent,
          textColor: const Color(0xFF0A0A0A),
          large: true,
        ),
        const SizedBox(width: 12),
        _PlayBtn(
          icon: Icons.replay,
          label: '처음부터',
          onTap: () async {
            await _player.seek(Duration.zero);
            await _player.resume();
          },
          color: AppColors.elevated,
        ),
      ],
    );
  }

  Widget _buildVolume() {
    return Row(
      children: [
        const Icon(Icons.volume_down, color: AppColors.textMuted, size: 18),
        Expanded(
          child: Slider(
            min: 0,
            max: 1,
            value: _volume,
            onChanged: (v) {
              _player.setVolume(v);
              setState(() => _volume = v);
            },
          ),
        ),
        const Icon(Icons.volume_up, color: AppColors.textMuted, size: 18),
      ],
    );
  }
}

class _PlayBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final Color textColor;
  final bool large;

  const _PlayBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
    this.textColor = AppColors.textPrimary,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = large ? 56.0 : 44.0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: textColor, size: large ? 26 : 20),
            Text(label, style: TextStyle(color: textColor, fontSize: 9, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
