// file: lib/services/song_list_bootstrap_service.dart
//
// 앱 시작 시 곡, 큐, 설정과 초기 선택 곡을 불러온다.
import '../models/prompter_settings.dart';
import '../models/queue_item.dart';
import '../models/song.dart';
import '../repository/song_repository.dart';

class SongListBootstrapService {
  final SongRepository _repo;

  const SongListBootstrapService(this._repo);

  Future<SongListBootstrapState> load() async {
    final songs = await _repo.loadSongs();
    final activeQueueSlot = await _repo.loadActiveQueueSlot();
    final queueSlots = [
      for (var i = 0; i < SongRepository.queueSlotCount; i++)
        await _repo.loadQueueSlot(i),
    ];
    final settings = await _repo.loadSettings();
    final lastSongId = await _repo.loadLastSongId();

    Song? initialSong;
    if (lastSongId != null) {
      initialSong = songs
          .where((song) => song.id == lastSongId)
          .cast<Song?>()
          .firstWhere((song) => song != null, orElse: () => null);
    }
    initialSong ??= songs.isNotEmpty ? songs.first : null;

    return SongListBootstrapState(
      songs: songs,
      queueSlots: queueSlots,
      activeQueueSlot: activeQueueSlot,
      settings: settings,
      initialSong: initialSong,
    );
  }
}

class SongListBootstrapState {
  final List<Song> songs;
  final List<List<QueueItem>> queueSlots;
  final int activeQueueSlot;
  final PrompterSettings settings;
  final Song? initialSong;

  const SongListBootstrapState({
    required this.songs,
    required this.queueSlots,
    required this.activeQueueSlot,
    required this.settings,
    required this.initialSong,
  });

  List<QueueItem> get queue => queueSlots[activeQueueSlot];
}
