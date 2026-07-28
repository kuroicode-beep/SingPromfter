// file: lib/widgets/home_now_playing_bar.dart
//
// 홈 화면 상단 Now Playing 바.
//
// v2.5.0: 곡 정보·반주 라벨을 한 줄로 합치고, 별도 줄이던 서버 상태를
// 이 줄 오른쪽에 붙였다. 상단 스트립이 줄어든 만큼 목록·프롬프터가 넓어진다.
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/song.dart';
import '../theme/app_theme.dart';
import 'server_status_strip.dart';

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
    final title = current == null
        ? '곡을 선택해 주세요'
        : playing
        ? '재생 중: ${current.title}'
        : '선택: ${current.title}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 3, 6, 3),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainer,
        border: Border(bottom: BorderSide(color: AppColors.outline)),
      ),
      child: Row(
        children: [
          Icon(
            playing ? Icons.equalizer : Icons.music_note_outlined,
            color: playing ? AppColors.primary : AppColors.onSurfaceVariant,
            size: 17,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              trackLabel == null ? title : '$title · $trackLabel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body,
            ),
          ),
          const SizedBox(width: 8),
          const ServerStatusChip(),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: current == null ? null : onStartPrompter,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryContainer,
              foregroundColor: AppColors.onPrimaryContainer,
              disabledBackgroundColor: AppColors.elevated,
              disabledForegroundColor: AppColors.onSurfaceVariant,
              minimumSize: const Size(84, AppConstants.minTouchTarget),
              padding: const EdgeInsets.symmetric(horizontal: 12),
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
    if (slot == null) return '반주 미선택';
    final track = song.trackForSlot(slot);
    final label = track?.label.trim();
    if (label != null && label.isNotEmpty) return '반주 $slot · $label';
    return '반주 $slot';
  }
}
