// file: lib/repository/lrc_store.dart
//
// 싱크 가사(.lrc)를 data/lrc/<songId>.lrc에 사이드카로 저장한다.
//
// 파일명을 곡 제목이 아니라 **id 기준**으로 두는 이유: 제목을 바꿀 때
// updateSong이 파일명을 줄줄이 바꾸는 캐스케이드에 얽히지 않기 위해서다.
// 가사 txt는 사용자가 직접 열어보는 파일이라 제목 기준을 유지하지만,
// LRC는 앱이 관리하는 파일이라 id 기준이 더 안전하다.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class LrcStore {
  Future<Directory> get _lrcDir async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/data/lrc');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String fileNameFor(String songId) => '$songId.lrc';

  Future<File> fileFor(String songId) async =>
      File('${(await _lrcDir).path}/${fileNameFor(songId)}');

  Future<Directory> directory() => _lrcDir;

  Future<bool> exists(String songId) async => (await fileFor(songId)).exists();

  Future<String?> read(String songId) async {
    try {
      final file = await fileFor(songId);
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      return raw.trim().isEmpty ? null : raw;
    } catch (e) {
      debugPrint('lrc 읽기 실패($songId): $e');
      return null;
    }
  }

  Future<String?> write(String songId, String content) async {
    try {
      final file = await fileFor(songId);
      await file.writeAsString(content);
      return fileNameFor(songId);
    } catch (e) {
      debugPrint('lrc 저장 실패($songId): $e');
      return null;
    }
  }

  Future<void> delete(String songId) async {
    try {
      final file = await fileFor(songId);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('lrc 삭제 실패($songId): $e');
    }
  }
}
