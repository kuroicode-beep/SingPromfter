// file: lib/services/queue_logic.dart
//
// 예약 큐 순서 조작의 순수 로직.
import '../models/prompter_settings.dart';
import '../models/queue_item.dart';
import '../models/song.dart';

class QueueLogic {
  QueueLogic._();

  static List<QueueItem> appendSongs({
    required List<QueueItem> queue,
    required List<Song> songs,
    required PrompterSettings settings,
  }) {
    final nextQueue = List<QueueItem>.from(queue);
    for (final song in songs) {
      final songSlot = settings.trackSlotForSong(song.id);
      final slot = song.availableTrackSlots.contains(songSlot)
          ? songSlot
          : (song.availableTrackSlots.isNotEmpty
                ? song.availableTrackSlots.first
                : null);
      nextQueue.add(
        QueueItem(
          songId: song.id,
          selectedTrackSlot: slot,
          queuedAt: DateTime.now(),
        ),
      );
    }
    return nextQueue;
  }

  static List<QueueItem> removeAt(List<QueueItem> queue, int index) {    if (index < 0 || index >= queue.length) return queue;
    return List<QueueItem>.from(queue)..removeAt(index);
  }

  /// Flutter 3.41의 onReorderItem이 주는 **보정된** newIndex를,
  /// [reorder]가 쓰는 예전 ReorderableListView raw 인덱스로 되돌린다.
  ///
  /// 이 규약의 소유자는 QueueLogic이다 — 제어 API(sp_queue_reorder)와
  /// 기존 테스트가 전부 raw 규약이라, 새 콜백 쪽을 여기서 변환해 맞춘다.
  static int rawIndexForAdjusted(int oldIndex, int adjustedNewIndex) =>
      adjustedNewIndex > oldIndex ? adjustedNewIndex + 1 : adjustedNewIndex;

  static List<QueueItem> reorder(
    List<QueueItem> queue,
    int oldIndex,
    int newIndex,
  ) {
    if (oldIndex < 0 || oldIndex >= queue.length) return queue;
    var targetIndex = newIndex;
    if (targetIndex > oldIndex) targetIndex -= 1;
    if (targetIndex < 0 || targetIndex >= queue.length) return queue;

    final nextQueue = List<QueueItem>.from(queue);
    final item = nextQueue.removeAt(oldIndex);
    nextQueue.insert(targetIndex, item);
    return nextQueue;
  }
}
