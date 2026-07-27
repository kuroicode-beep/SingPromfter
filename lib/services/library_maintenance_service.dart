// file: lib/services/library_maintenance_service.dart
//
// 라이브러리 점검·정리. 소프트 삭제 설계상 파일이 남고 단계마다 디렉터리가
// 늘어나 고아 파일이 쌓이므로 정리 도구가 필요하다.
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/song.dart';
import '../repository/lrc_store.dart';
import '../repository/song_repository.dart';
import 'song_sort_service.dart';

class LibraryMaintenanceService {
  final SongRepository _repo;
  final LrcStore _lrcStore;

  LibraryMaintenanceService(this._repo, {LrcStore? lrcStore})
    : _lrcStore = lrcStore ?? LrcStore();

  /// 디스크를 훑어 곡 목록과 대조한다.
  Future<LibraryAudit> audit(List<Song> songs) async {
    final trackFiles = await _listFileNames(await _repo.getBackingTrackDir());
    final lrcFiles = await _listFileNames(await _lrcStore.directory());
    return LibraryAudit.compare(
      songs: songs,
      trackFilesOnDisk: trackFiles,
      lrcFilesOnDisk: lrcFiles,
    );
  }

  /// 고아 파일을 지우고 지운 개수를 돌려준다.
  Future<int> deleteOrphans(LibraryAudit audit) async {
    var deleted = 0;
    final trackDir = await _repo.getBackingTrackDir();
    for (final name in audit.orphanTrackFiles) {
      if (await _deleteIn(trackDir, name)) deleted += 1;
    }
    final lrcDir = await _lrcStore.directory();
    for (final name in audit.orphanLrcFiles) {
      if (await _deleteIn(lrcDir, name)) deleted += 1;
    }
    return deleted;
  }

  /// 피치 변형본 캐시를 비운다. 파생물이라 언제든 다시 만들 수 있다.
  Future<int> clearPitchCache() async {
    try {
      final dir = Directory('${(await _repo.getDataDir()).path}/cache/pitch');
      if (!await dir.exists()) return 0;
      var count = 0;
      await for (final entity in dir.list()) {
        if (entity is File) {
          await entity.delete();
          count += 1;
        }
      }
      return count;
    } catch (e) {
      debugPrint('피치 캐시 정리 실패: $e');
      return 0;
    }
  }

  /// 가져오기 임시 폴더에 남은 찌꺼기를 지운다.
  Future<int> clearTempFiles() async {
    try {
      final dir = await _repo.getTmpDir();
      var count = 0;
      await for (final entity in dir.list()) {
        try {
          await entity.delete(recursive: true);
          count += 1;
        } catch (_) {
          // 사용 중인 항목은 건너뛴다.
        }
      }
      return count;
    } catch (e) {
      debugPrint('임시 폴더 정리 실패: $e');
      return 0;
    }
  }

  Future<List<String>> _listFileNames(Directory dir) async {
    try {
      if (!await dir.exists()) return const [];
      final names = <String>[];
      await for (final entity in dir.list()) {
        if (entity is File) {
          names.add(entity.uri.pathSegments.last);
        }
      }
      return names;
    } catch (e) {
      debugPrint('디렉터리 목록 실패(${dir.path}): $e');
      return const [];
    }
  }

  Future<bool> _deleteIn(Directory dir, String fileName) async {
    try {
      final file = File('${dir.path}/$fileName');
      if (!await file.exists()) return false;
      await file.delete();
      return true;
    } catch (e) {
      debugPrint('파일 삭제 실패($fileName): $e');
      return false;
    }
  }
}
