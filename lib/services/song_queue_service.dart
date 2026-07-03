// file: lib/services/song_queue_service.dart
//
// 예약 큐의 추가, 제거, 정렬, 다음 곡 선택 규칙을 관리한다.
import '../models/prompter_settings.dart';
import '../models/queue_item.dart';
import '../models/song.dart';
import '../repository/song_repository.dart';
import 'queue_logic.dart';

class SongQueueService {
  final SongRepository _repo;

  const SongQueueService(this._repo);

  Future<List<QueueItem>> addSong({
    required List<QueueItem> queue,
    required Song song,
    required PrompterSettings settings,
  }) async {
    final songSlot = settings.trackSlotForSong(song.id);
    final slot = song.availableTrackSlots.contains(songSlot)
        ? songSlot
        : (song.availableTrackSlots.isNotEmpty
              ? song.availableTrackSlots.first
              : null);

    final nextQueue = List<QueueItem>.from(queue)
      ..add(
        QueueItem(
          songId: song.id,
          selectedTrackSlot: slot,
          queuedAt: DateTime.now(),
        ),
      );
    await _repo.saveQueue(nextQueue);
    return nextQueue;
  }

  Future<List<QueueItem>> removeAt(List<QueueItem> queue, int index) async {
    final nextQueue = QueueLogic.removeAt(queue, index);
    await _repo.saveQueue(nextQueue);
    return nextQueue;
  }

  Future<List<QueueItem>> reorder(
    List<QueueItem> queue,
    int oldIndex,
    int newIndex,
  ) async {
    final nextQueue = QueueLogic.reorder(queue, oldIndex, newIndex);
    await _repo.saveQueue(nextQueue);
    return nextQueue;
  }

  Future<List<QueueItem>> clear() async {
    await _repo.saveQueue(const []);
    return const [];
  }

  Future<NextQueuedSong?> popNextPlayable({
    required List<QueueItem> queue,
    required List<Song> songs,
  }) async {
    var nextQueue = List<QueueItem>.from(queue);
    while (nextQueue.isNotEmpty) {
      final next = nextQueue.removeAt(0);
      await _repo.saveQueue(nextQueue);

      Song? song;
      for (final item in songs) {
        if (item.id == next.songId) {
          song = item;
          break;
        }
      }
      if (song == null) continue;

      return NextQueuedSong(
        queue: nextQueue,
        song: song,
        selectedTrackSlot: next.selectedTrackSlot,
      );
    }

    return null;
  }
}

class NextQueuedSong {
  final List<QueueItem> queue;
  final Song song;
  final int? selectedTrackSlot;

  const NextQueuedSong({
    required this.queue,
    required this.song,
    required this.selectedTrackSlot,
  });
}
