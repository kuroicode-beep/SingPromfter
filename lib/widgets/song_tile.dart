// file: lib/widgets/song_tile.dart
//
// 곡 목록의 단일 카드 UI. 선택, 재생, 예약, 수정, 삭제 액션을 노출한다.
import 'package:flutter/material.dart';

import '../models/song.dart';
import '../theme/app_theme.dart';
import 'small_action_button.dart';

class SongTile extends StatelessWidget {
  final Song song;
  final bool selected;
  final int? selectedTrackSlot;
  final void Function(int slot)? onSelectTrack;
  final VoidCallback onSelect;
  final VoidCallback onPlayNow;
  final VoidCallback onReserve;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;

  const SongTile({
    super.key,
    required this.song,
    required this.selected,
    this.selectedTrackSlot,
    this.onSelectTrack,
    required this.onSelect,
    required this.onPlayNow,
    required this.onReserve,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF2A240A) : AppColors.elevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Semantics(
                    label: song.isFavorite ? '즐겨찾기 해제' : '즐겨찾기 추가',
                    button: true,
                    child: IconButton(
                      onPressed: onToggleFavorite,
                      icon: Icon(
                        song.isFavorite ? Icons.star : Icons.star_border,
                        color: song.isFavorite
                            ? AppColors.accent
                            : AppColors.textMuted,
                      ),
                      tooltip: song.isFavorite ? '즐겨찾기 해제' : '즐겨찾기 추가',
                    ),
                  ),
                ],
              ),
              if (selected &&
                  song.backingTracks.isNotEmpty &&
                  onSelectTrack != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: song.backingTracks.map((track) {
                    final isSel = selectedTrackSlot == track.slot;
                    return OutlinedButton.icon(
                      onPressed: () => onSelectTrack!(track.slot),
                      icon: Icon(
                        isSel
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 14,
                      ),
                      label: Text(
                        track.label.trim().isEmpty
                            ? '반주${track.slot}'
                            : track.label,
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: isSel
                            ? AppColors.accent
                            : AppColors.elevated,
                        foregroundColor: isSel
                            ? const Color(0xFF0A0A0A)
                            : AppColors.textPrimary,
                        side: BorderSide(
                          color: isSel ? AppColors.accent : AppColors.border,
                        ),
                        minimumSize: const Size(96, 48),
                        textStyle: const TextStyle(fontSize: 13),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SmallActionButton(
                      label: '선택',
                      icon: Icons.check,
                      onTap: onSelect,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: SmallActionButton(
                      label: '재생',
                      icon: Icons.play_arrow,
                      onTap: onPlayNow,
                      primary: true,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: SmallActionButton(
                      label: '예약',
                      icon: Icons.schedule,
                      onTap: onReserve,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: SmallActionButton(
                      label: '수정',
                      icon: Icons.edit_outlined,
                      onTap: onEdit,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: SmallActionButton(
                      label: '삭제',
                      icon: Icons.delete_outline,
                      onTap: onDelete,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
