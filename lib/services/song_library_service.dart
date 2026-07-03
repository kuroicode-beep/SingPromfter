// file: lib/services/song_library_service.dart
//
// 곡 파일 읽기와 추가/수정/삭제 시 목록 갱신 규칙을 담당한다.
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/queue_item.dart';
import '../models/song.dart';
import '../models/song_draft.dart';
import '../repository/song_repository.dart';

class SongLibraryService {
  final SongRepository _repo;

  const SongLibraryService(this._repo);

  Future<PickedLyricsResult> readPickedLyrics(PlatformFile picked) async {
    if ((picked.extension ?? '').toLowerCase() != 'txt') {
      return const PickedLyricsResult.failure('txt 파일만 선택할 수 있습니다.');
    }

    List<int>? bytes = picked.bytes;
    if (bytes == null && picked.path != null) {
      try {
        bytes = await File(picked.path!).readAsBytes();
      } catch (e, stack) {
        debugPrint('가사 파일 바이트 읽기 실패: $e\n$stack');
      }
    }
    if (bytes == null) {
      return const PickedLyricsResult.failure('가사 파일 내용을 읽을 수 없습니다.');
    }

    try {
      return PickedLyricsResult.success(
        fileName: picked.name,
        lyrics: _decodeLyricsFromBytes(bytes),
      );
    } catch (e, stack) {
      debugPrint('가사 파일 디코딩 실패: $e\n$stack');
      return const PickedLyricsResult.failure('가사 파일 읽기에 실패했습니다.');
    }
  }

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
      lyrics: lyrics,
      sourceTrackPaths: draft.trackPaths,
      trackLabels: draft.trackLabels,
      trackStartMs: draft.trackStartMs,
      trackEndMs: draft.trackEndMs,
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
      lyrics: draft.lyricsText,
      sourceTrackPaths: draft.trackPaths,
      trackLabels: draft.trackLabels,
      trackStartMs: draft.trackStartMs,
      trackEndMs: draft.trackEndMs,
    );
    final nextSongs = songs
        .map((item) => item.id == song.id ? updatedSong : item)
        .toList(growable: false);
    await _repo.saveSongs(nextSongs);
    return EditSongResult(songs: nextSongs, song: updatedSong);
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

  String _decodeLyricsFromBytes(List<int> bytes) {
    try {
      return utf8.decode(bytes).trim();
    } catch (e, stack) {
      debugPrint('UTF-8 가사 디코딩 실패, latin1 fallback 사용: $e\n$stack');
      return latin1.decode(bytes).trim();
    }
  }
}

class PickedLyricsResult {
  final String? fileName;
  final String? lyrics;
  final String? message;

  const PickedLyricsResult._({this.fileName, this.lyrics, this.message});

  const PickedLyricsResult.success({
    required String fileName,
    required String lyrics,
  }) : this._(fileName: fileName, lyrics: lyrics);

  const PickedLyricsResult.failure(String message) : this._(message: message);

  bool get isSuccess => lyrics != null && fileName != null;
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
