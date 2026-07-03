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
  final VoidCallback onClear;
  final ReorderCallback onReorder;
  final ValueChanged<int> onRemove;

  const QueuePanel({
    super.key,
    required this.queue,
    required this.songs,
    required this.onClear,
    required this.onReorder,
    required this.onRemove,
  });

  double get _height {
    final visibleRows = queue.length.clamp(1, 5);
    return (visibleRows * 58) + ((visibleRows - 1) * 8);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onClear,
              style: TextButton.styleFrom(
                minimumSize: const Size(72, 48),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              child: const Text('비우기', style: TextStyle(fontSize: 12)),
            ),
          ),
          SizedBox(
            height: _height,
            child: ReorderableListView(
              buildDefaultDragHandles: false,
              onReorder: onReorder,
              children: [
                for (var i = 0; i < queue.length; i++)
                  Padding(
                    key: ValueKey(
                      '${queue[i].songId}_${queue[i].queuedAt.toIso8601String()}',
                    ),
                    padding: EdgeInsets.only(
                      bottom: i == queue.length - 1 ? 0 : 8,
                    ),
                    child: _QueueTile(
                      index: i,
                      item: queue[i],
                      song: _songFor(queue[i]),
                      onRemove: () => onRemove(i),
                    ),
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
  final VoidCallback onRemove;

  const _QueueTile({
    required this.index,
    required this.item,
    required this.song,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: AppColors.elevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(
                Icons.drag_handle,
                size: 18,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${index + 1}. ${song?.title ?? '(삭제된 곡)'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.selectedTrackSlot == null
                      ? '가사'
                      : 'MR${item.selectedTrackSlot}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(
              Icons.delete_outline,
              size: 22,
              color: AppColors.textMuted,
            ),
            tooltip: '삭제',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
        ],
      ),
    );
  }
}
