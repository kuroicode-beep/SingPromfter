// file: lib/coordinators/song_action_coordinator.dart
//
// 곡 추가/수정/삭제의 다이얼로그 흐름과 결과 조립을 담당한다.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../dialogs/song_create_dialog.dart';
import '../dialogs/song_delete_dialog.dart';
import '../dialogs/song_edit_dialog.dart';
import '../models/queue_item.dart';
import '../models/song.dart';
import '../repository/song_repository.dart';
import '../services/song_library_service.dart';

class SongActionCoordinator {
  final SongRepository _repo;
  final SongLibraryService _libraryService;

  const SongActionCoordinator(this._repo, this._libraryService);

  Future<SongActionOutcome?> addSong({
    required BuildContext context,
    required List<Song> songs,
  }) async {
    final lyricsFile = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
      dialogTitle: '가사 파일(txt) 선택',
    );
    if (lyricsFile == null || lyricsFile.files.isEmpty) return null;

    final pickedLyrics = await _libraryService.readPickedLyrics(
      lyricsFile.files.first,
    );
    if (!pickedLyrics.isSuccess) {
      return SongActionOutcome.messageOnly(
        pickedLyrics.message ?? '가사 파일 읽기에 실패했습니다.',
      );
    }

    if (!context.mounted) return null;
    final draft = await SongCreateDialog.show(context, pickedLyrics.fileName!);
    if (draft == null) return null;
    if (_libraryService.hasDuplicateTitle(songs, draft.title)) {
      return const SongActionOutcome.messageOnly(
        '같은 제목의 곡이 이미 있습니다. 제목을 바꿔 주세요.',
      );
    }

    try {
      final result = await _libraryService.addSong(
        songs: songs,
        draft: draft,
        lyrics: pickedLyrics.lyrics!,
      );
      return SongActionOutcome(
        songs: result.songs,
        loadSong: result.song,
        message: '곡이 추가되었습니다.',
      );
    } catch (e, stack) {
      debugPrint('곡 추가 실패: $e\n$stack');
      return SongActionOutcome.messageOnly('곡 추가 중 오류가 발생했습니다: $e');
    }
  }

  Future<SongActionOutcome?> editSong({
    required BuildContext context,
    required List<Song> songs,
    required Song song,
    required Song? selectedSong,
  }) async {
    final draft = await SongEditDialog.show(context, song);
    if (draft == null) return null;
    if (_libraryService.hasDuplicateTitle(
      songs,
      draft.title,
      excludeId: song.id,
    )) {
      return const SongActionOutcome.messageOnly(
        '같은 제목의 곡이 이미 있습니다. 제목을 바꿔 주세요.',
      );
    }

    try {
      final result = await _libraryService.editSong(
        songs: songs,
        song: song,
        draft: draft,
      );
      final isSelected = selectedSong?.id == song.id;
      return SongActionOutcome(
        songs: result.songs,
        selectedSong: isSelected ? result.song : selectedSong,
        loadSong: isSelected ? result.song : null,
        message: '곡 정보가 수정되었습니다.',
      );
    } catch (e, stack) {
      debugPrint('곡 수정 실패: $e\n$stack');
      return SongActionOutcome.messageOnly('곡 수정 중 오류가 발생했습니다: $e');
    }
  }

  Future<SongActionOutcome?> deleteSong({
    required BuildContext context,
    required List<Song> songs,
    required List<QueueItem> queue,
    required Song song,
    required Song? selectedSong,
  }) async {
    final confirmed = await SongDeleteDialog.confirm(context, song);
    if (!confirmed) return null;

    final result = await _libraryService.deleteSong(
      songs: songs,
      queue: queue,
      song: song,
      selectedSong: selectedSong,
    );
    if (result.selectedSong == null) {
      await _repo.saveLastSongId(null);
    }

    return SongActionOutcome(
      songs: result.songs,
      queue: result.queue,
      selectedSong: result.selectedSong,
      loadSong: result.selectedSong,
      deletedSong: song,
      clearSelectedTrackSlot: true,
      stopPlayback: result.deletedSelectedSong,
      message: '"${song.title}" 삭제됨',
    );
  }
}

class SongActionOutcome {
  final List<Song>? songs;
  final List<QueueItem>? queue;
  final Song? selectedSong;
  final Song? loadSong;
  final Song? deletedSong;
  final bool clearSelectedTrackSlot;
  final bool stopPlayback;
  final String? message;

  const SongActionOutcome({
    this.songs,
    this.queue,
    this.selectedSong,
    this.loadSong,
    this.deletedSong,
    this.clearSelectedTrackSlot = false,
    this.stopPlayback = false,
    this.message,
  });

  const SongActionOutcome.messageOnly(String message) : this(message: message);
}
