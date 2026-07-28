// file: lib/services/song_library_service.dart
//
// 곡 추가/수정/삭제 시 목록 갱신 규칙을 담당한다.
import 'package:uuid/uuid.dart';

import '../models/queue_item.dart';
import '../models/song.dart';
import '../models/song_draft.dart';
import '../repository/song_repository.dart';

class SongLibraryService {
  final SongRepository _repo;

  const SongLibraryService(this._repo);

  bool hasDuplicateTitle(List<Song> songs, String title, {String? excludeId}) {
    final normalized = title.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    for (final song in songs) {
      if (song.id == excludeId) continue;
      if (song.title.trim().toLowerCase() == normalized) {
        return true;
      }
    }
    return false;
  }

  Future<AddSongResult> addSong({
    required List<Song> songs,
    required SongDraft draft,
    required String lyrics,
  }) async {
    final song = await _repo.addSong(
      id: const Uuid().v4(),
      title: draft.title,
      artist: draft.artist,
      lyrics: lyrics,
      sourceTrackPaths: draft.trackPaths,
      trackLabels: draft.trackLabels,
      trackStartMs: draft.trackStartMs,
      trackEndMs: draft.trackEndMs,
      trackBakedSemitones: draft.trackBakedSemitones,
    );
    final nextSongs = List<Song>.from(songs)..add(song);
    await _repo.saveSongs(nextSongs);
    return AddSongResult(songs: nextSongs, song: song);
  }

  Future<EditSongResult> editSong({
    required List<Song> songs,
    required Song song,
    required SongEditDraft draft,
  }) async {
    final updatedSong = await _repo.updateSong(
      song: song,
      title: draft.title,
      artist: draft.artist,
      lyrics: draft.lyricsText,
      sourceTrackPaths: draft.trackPaths,
      trackLabels: draft.trackLabels,
      trackStartMs: draft.trackStartMs,
      trackEndMs: draft.trackEndMs,
    );
    // 조성과 구운 키는 updateSong의 관심사(제목·가사·반주 파일)가 아니라
    // 여기서 얹는다.
    var withKey = draft.applyMusicalKey
        ? updatedSong.copyWith(
            musicalKey: draft.musicalKey,
            clearMusicalKey: draft.musicalKey == null,
          )
        : updatedSong;
    if (draft.trackBakedSemitones.isNotEmpty) {
      withKey = withKey.copyWith(
        backingTracks: [
          for (final track in withKey.backingTracks)
            draft.trackBakedSemitones.containsKey(track.slot)
                ? track.copyWith(
                    bakedSemitones: draft.trackBakedSemitones[track.slot],
                  )
                : track,
        ],
      );
    }
    final nextSongs = songs
        .map((item) => item.id == song.id ? withKey : item)
        .toList(growable: false);
    await _repo.saveSongs(nextSongs);
    return EditSongResult(songs: nextSongs, song: withKey);
  }

  Future<EditSongResult> toggleFavorite({
    required List<Song> songs,
    required Song song,
  }) async {
    final updatedSong = song.copyWith(
      isFavorite: !song.isFavorite,
      updatedAt: DateTime.now(),
    );
    final nextSongs = songs
        .map((item) => item.id == song.id ? updatedSong : item)
        .toList(growable: false);
    await _repo.saveSongs(nextSongs);
    return EditSongResult(songs: nextSongs, song: updatedSong);
  }

  Future<DeleteSongResult> deleteSong({
    required List<Song> songs,
    required List<QueueItem> queue,
    required Song song,
    required Song? selectedSong,
  }) async {
    final nextSongs = List<Song>.from(songs)
      ..removeWhere((item) => item.id == song.id);
    final nextQueue = List<QueueItem>.from(queue)
      ..removeWhere((item) => item.songId == song.id);
    final deletedSelected = selectedSong?.id == song.id;
    final nextSelected = deletedSelected
        ? (nextSongs.isNotEmpty ? nextSongs.first : null)
        : selectedSong;

    await _repo.saveSongs(nextSongs);
    await _repo.saveQueue(nextQueue);

    return DeleteSongResult(
      songs: nextSongs,
      queue: nextQueue,
      selectedSong: nextSelected,
      deletedSelectedSong: deletedSelected,
    );
  }

  Future<EditSongResult> restoreSong({
    required List<Song> songs,
    required Song song,
  }) async {
    if (songs.any((item) => item.id == song.id)) {
      return EditSongResult(songs: songs, song: song);
    }
    final nextSongs = List<Song>.from(songs)..add(song);
    nextSongs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    await _repo.saveSongs(nextSongs);
    return EditSongResult(songs: nextSongs, song: song);
  }

  Future<void> permanentlyDeleteSong(Song song) => _repo.deleteSong(song);

}

class AddSongResult {
  final List<Song> songs;
  final Song song;

  const AddSongResult({required this.songs, required this.song});
}

class EditSongResult {
  final List<Song> songs;
  final Song song;

  const EditSongResult({required this.songs, required this.song});
}

class DeleteSongResult {
  final List<Song> songs;
  final List<QueueItem> queue;
  final Song? selectedSong;
  final bool deletedSelectedSong;

  const DeleteSongResult({
    required this.songs,
    required this.queue,
    required this.selectedSong,
    required this.deletedSelectedSong,
  });
}
