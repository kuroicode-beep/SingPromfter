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
  final VoidCallback onStart;
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
    required this.onStart,
    required this.onReserve,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppShapes.panelRadius,
        onTap: onSelect,
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? AppColors.selectedSurface : AppColors.surfaceContainer,
            borderRadius: AppShapes.panelRadius,
            border: Border.all(color: AppColors.outline),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.listTitle.copyWith(fontSize: 17),
                              ),
                              if (song.artist.trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.bodyMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (selected)
                          Padding(
                            padding: const EdgeInsets.only(right: 4, top: 2),
                            child: Text(
                              '선택됨',
                              style: AppTypography.bodyMuted.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
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
                                  ? AppColors.primaryContainer
                                  : AppColors.elevated,
                              foregroundColor: isSel
                                  ? AppColors.onPrimaryContainer
                                  : AppColors.textPrimary,
                              side: BorderSide(
                                color: isSel
                                    ? AppColors.primaryContainer
                                    : AppColors.border,
                              ),
                              minimumSize: const Size(96, 50),
                              textStyle: AppTypography.body.copyWith(fontSize: 16),
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
                        const SizedBox(width: 8),
                        Semantics(
                          label: '${song.title} 예약',
                          button: true,
                          child: OutlinedButton(
                            onPressed: onReserve,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.tertiary,
                              side: const BorderSide(color: AppColors.tertiary),
                              minimumSize: const Size(72, 50),
                            ),
                            child: const Text('예약'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Semantics(
                          label: '${song.title} 시작',
                          button: true,
                          child: FilledButton(
                            onPressed: onStart,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primaryContainer,
                              foregroundColor: AppColors.onPrimaryContainer,
                              minimumSize: const Size(72, 50),
                            ),
                            child: const Text('시작'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (selected)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 3,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
