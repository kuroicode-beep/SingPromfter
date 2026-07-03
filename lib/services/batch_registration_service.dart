// file: lib/services/batch_registration_service.dart
//
// 폴더 내 txt/mp3 파일을 제목 기준으로 매칭해 여러 곡을 등록한다.
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import '../models/song.dart';
import '../repository/song_repository.dart';
import 'song_library_service.dart';

class BatchRegistrationService {
  final SongRepository _repo;
  final SongLibraryService _libraryService;

  const BatchRegistrationService(this._repo, this._libraryService);

  Future<List<BatchMatch>?> pickAndMatch() async {
    final dirPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '일괄 등록할 폴더 선택',
    );
    if (dirPath == null) return null;
    return matchDirectory(Directory(dirPath));
  }

  Future<List<BatchMatch>> matchDirectory(Directory dir) async {
    final files = await dir
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    final txtFiles = files.where(
      (file) => file.path.toLowerCase().endsWith('.txt'),
    );
    final mp3Files = files.where(
      (file) => file.path.toLowerCase().endsWith('.mp3'),
    );
    final matches = <BatchMatch>[];

    for (final txt in txtFiles) {
      final stem = _stem(txt.path);
      final tracks = <int, String>{};
      for (final slot in AppConstants.backingTrackSlots) {
        final expected = '${stem}_mr$slot.mp3'.toLowerCase();
        for (final mp3 in mp3Files) {
          if (_baseName(mp3.path).toLowerCase() == expected) {
            tracks[slot] = mp3.path;
            break;
          }
        }
      }
      matches.add(
        BatchMatch(title: stem, lyricsPath: txt.path, trackPaths: tracks),
      );
    }
    matches.sort((a, b) => a.title.compareTo(b.title));
    return matches;
  }

  Future<BatchRegistrationResult> register({
    required List<Song> songs,
    required List<BatchMatch> matches,
  }) async {
    final nextSongs = List<Song>.from(songs);
    var skippedCount = 0;

    for (final match in matches) {
      if (_libraryService.hasDuplicateTitle(nextSongs, match.title)) {
        skippedCount += 1;
        continue;
      }
      final lyrics = await _readLyrics(match.lyricsPath);
      final song = await _repo.addSong(
        id: const Uuid().v4(),
        title: match.title,
        lyrics: lyrics,
        sourceTrackPaths: match.trackPaths,
        trackLabels: {
          for (final slot in match.trackPaths.keys) slot: 'MR$slot',
        },
      );
      nextSongs.add(song);
    }

    await _repo.saveSongs(nextSongs);
    return BatchRegistrationResult(
      songs: nextSongs,
      importedCount: matches.length - skippedCount,
      skippedCount: skippedCount,
    );
  }

  Future<String> _readLyrics(String path) async {
    final bytes = await File(path).readAsBytes();
    try {
      return utf8.decode(bytes).trim();
    } catch (e, stack) {
      debugPrint('일괄 등록 UTF-8 디코딩 실패, latin1 fallback 사용: $e\n$stack');
      return latin1.decode(bytes).trim();
    }
  }

  String _stem(String path) {
    final name = _baseName(path);
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }

  String _baseName(String path) => path.split(RegExp(r'[\\/]')).last;
}

class BatchMatch {
  final String title;
  final String lyricsPath;
  final Map<int, String> trackPaths;

  const BatchMatch({
    required this.title,
    required this.lyricsPath,
    required this.trackPaths,
  });
}

class BatchRegistrationResult {
  final List<Song> songs;
  final int importedCount;
  final int skippedCount;

  const BatchRegistrationResult({
    required this.songs,
    required this.importedCount,
    required this.skippedCount,
  });
}
