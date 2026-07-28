// file: lib/widgets/pitch_hud.dart
//
// Alt+휠로 키를 굴리는 동안 화면 한가운데에 크게 띄우는 표시.
//
// 키 렌더는 곡 전체를 다시 인코딩하는 오프라인 작업이라 즉시 들리지 않는다.
// 그래서 "지금 무엇을 고르고 있는지"는 화면이 먼저 알려 줘야 한다.
import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/key_label.dart';
import '../utils/music_key.dart';

/// 조절 중인 값을 크게 보여 준다. [semitones]가 null이면 사라진다.
///
/// 키와 템포가 같은 카드를 쓴다 — 무대에서 "지금 무엇을 고르고 있는지"를
/// 알려 주는 자리가 둘로 갈리면 눈이 헤맨다.
class PitchHud extends StatefulWidget {
  /// 조절 중인 반음. null이면 표시하지 않는다.
  final int? semitones;

  /// 곡의 조성(감지·지정된 값). 알면 옮겨진 조성도 함께 보여 준다.
  final MusicKey? songKey;

  /// 큰 글씨를 직접 지정한다. 주면 [semitones] 대신 이 값을 쓴다(템포용).
  final String? headline;

  /// 작은 글씨. 주면 조성 대신 이 값을 쓴다.
  final String? caption;

  /// 사라지기 전 머무는 시간.
  final Duration linger;

  const PitchHud({
    super.key,
    required this.semitones,
    this.songKey,
    this.headline,
    this.caption,
    this.linger = const Duration(milliseconds: 1400),
  });

  @override
  State<PitchHud> createState() => _PitchHudState();
}

class _PitchHudState extends State<PitchHud> {
  Timer? _hideTimer;
  int? _shown;

  @override
  void didUpdateWidget(covariant PitchHud oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.semitones != oldWidget.semitones) _refresh();
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _hideTimer?.cancel();
    final value = widget.semitones;
    if (value == null) {
      // 적용이 끝나 값이 비면 잠시 더 보여 주고 사라진다.
      _hideTimer = Timer(widget.linger, () {
        if (mounted) setState(() => _shown = null);
      });
      return;
    }
    setState(() => _shown = value);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _shown;
    if (value == null) return const SizedBox.shrink();

    final key = widget.songKey?.transposed(value);
    final caption = widget.caption ?? key?.label;
    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.82),
            borderRadius: AppShapes.panelRadius,
            border: Border.all(color: AppColors.tertiary, width: 3),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.headline ?? formatKeyLabel(value),
                style: const TextStyle(
                  fontFamily: AppFonts.legible,
                  fontSize: 56,
                  height: 1.1,
                  color: AppColors.tertiary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (caption != null) ...[
                const SizedBox(height: 6),
                Text(
                  caption,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 28,
                    color: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
