// file: lib/widgets/home_now_playing_bar.dart
//
// 홈 화면 상단 Now Playing / 선택 곡 상태 바.
import 'package:flutter/material.dart';

import '../models/song.dart';
import '../theme/app_theme.dart';

class HomeNowPlayingBar extends StatelessWidget {
  final Song? song;
  final int? selectedTrackSlot;
  final bool playing;
  final VoidCallback? onStartPrompter;

  const HomeNowPlayingBar({
    super.key,
    required this.song,
    required this.selectedTrackSlot,
    required this.playing,
    required this.onStartPrompter,
  });

  @override
  Widget build(BuildContext context) {
    final current = song;
    final trackLabel = _trackLabel(current, selectedTrackSlot);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        border: Border(bottom: BorderSide(color: AppColors.outline)),
      ),
      child: Row(
        children: [
          Icon(
            playing ? Icons.equalizer : Icons.music_note_outlined,
            color: playing ? AppColors.primary : AppColors.onSurfaceVariant,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current == null
                      ? '곡을 선택해 주세요'
                      : playing
                          ? 'Now Playing: ${current.title}'
                          : '선택된 곡: ${current.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body,
                ),
                if (trackLabel != null)
                  Text(trackLabel, style: AppTypography.bodyMuted),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: current == null ? null : onStartPrompter,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryContainer,
              foregroundColor: AppColors.onPrimaryContainer,
              disabledBackgroundColor: AppColors.elevated,
              disabledForegroundColor: AppColors.onSurfaceVariant,
              minimumSize: const Size(112, 50),
            ),
            child: Text(current == null ? '곡 선택 필요' : '곡 시작'),
          ),
        ],
      ),
    );
  }

  String? _trackLabel(Song? song, int? slot) {
    if (song == null) return null;
    if (song.backingTracks.isEmpty) return '가사 전용';
    if (slot == null) return '반주 슬롯 미선택';
    final track = song.trackForSlot(slot);
    final label = track?.label.trim();
    if (label != null && label.isNotEmpty) return '반주 $slot · $label';
    return '반주 $slot';
  }
}
