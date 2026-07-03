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
    final queue = await _repo.loadQueue();
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
      queue: queue,
      settings: settings,
      initialSong: initialSong,
    );
  }
}

class SongListBootstrapState {
  final List<Song> songs;
  final List<QueueItem> queue;
  final PrompterSettings settings;
  final Song? initialSong;

  const SongListBootstrapState({
    required this.songs,
    required this.queue,
    required this.settings,
    required this.initialSong,
  });
}
