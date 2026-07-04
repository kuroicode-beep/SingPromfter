// file: lib/widgets/queue_panel.dart
//
// 예약 큐 표시, 드래그 재정렬, 항목 삭제를 담당하는 패널 위젯.
import 'package:flutter/material.dart';

import '../models/queue_item.dart';
import '../models/song.dart';
import '../theme/app_theme.dart';

class QueuePanel extends StatelessWidget {
  final List<QueueItem> queue;
  final List<Song> songs;
  final String? playingSongId;
  final bool playing;
  final VoidCallback onClear;
  final ReorderCallback onReorder;
  final ValueChanged<int> onRemove;

  const QueuePanel({
    super.key,
    required this.queue,
    required this.songs,
    this.playingSongId,
    this.playing = false,
    required this.onClear,
    required this.onReorder,
    required this.onRemove,
  });

  double get _height {
    final visibleRows = queue.length.clamp(1, 5);
    return visibleRows * 72.0;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: AppShapes.panel(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('예약 큐', style: AppTypography.listTitle),
              const Spacer(),
              TextButton(
                onPressed: onClear,
                style: TextButton.styleFrom(
                  minimumSize: const Size(72, 50),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                child: Text('비우기', style: AppTypography.body),
              ),
            ],
          ),
          const Divider(height: 1, thickness: 1),
          SizedBox(
            height: _height,
            child: ReorderableListView(
              buildDefaultDragHandles: false,
              onReorder: onReorder,
              children: [
                for (var i = 0; i < queue.length; i++)
                  _QueueTile(
                    key: ValueKey(
                      '${queue[i].songId}_${queue[i].queuedAt.toIso8601String()}',
                    ),
                    index: i,
                    item: queue[i],
                    song: _songFor(queue[i]),
                    isNowPlaying: playing && playingSongId == queue[i].songId,
                    showDivider: i < queue.length - 1,
                    onRemove: () => onRemove(i),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Song? _songFor(QueueItem item) {
    for (final song in songs) {
      if (song.id == item.songId) return song;
    }
    return null;
  }
}

class _QueueTile extends StatelessWidget {
  final int index;
  final QueueItem item;
  final Song? song;
  final bool isNowPlaying;
  final bool showDivider;
  final VoidCallback onRemove;

  const _QueueTile({
    super.key,
    required this.index,
    required this.item,
    required this.song,
    required this.isNowPlaying,
    required this.showDivider,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      key: key,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: isNowPlaying ? AppColors.selectedSurface : Colors.transparent,
            borderRadius: AppShapes.controlRadius,
            border: isNowPlaying
                ? const Border(
                    left: BorderSide(color: AppColors.primaryContainer, width: 3),
                  )
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.drag_handle,
                      size: 22,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                Text(
                  (index + 1).toString().padLeft(2, '0'),
                  style: AppTypography.bodyMuted.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              song?.title ?? '(삭제된 곡)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.labelStrong,
                            ),
                          ),
                          if (isNowPlaying)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryContainer,
                                borderRadius: AppShapes.controlRadius,
                              ),
                              child: Text(
                                'NOW',
                                style: AppTypography.body.copyWith(
                                  color: AppColors.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.selectedTrackSlot == null
                            ? '가사 전용'
                            : '반주 ${item.selectedTrackSlot}',
                        style: AppTypography.bodyMuted,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 24,
                    color: AppColors.textMuted,
                  ),
                  tooltip: '삭제',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 50, minHeight: 50),
                ),
              ],
            ),
          ),
        ),
        if (showDivider) const Divider(height: 1, thickness: 1),
      ],
    );
  }
}
