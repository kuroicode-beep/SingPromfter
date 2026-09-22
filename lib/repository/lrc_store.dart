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

import '../services/atomic_json_file.dart';

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

  /// 싱크 가사를 쓴다. 성공하면 파일 이름, 못 쓰면 null.
  ///
  /// 쓰다 죽어도 반쪽짜리 .lrc가 남지 않게 원자적으로 쓴다(`.tmp`→rename).
  /// 🔴 여기서 `.bak`은 만들지 않는다 — 이 폴더의 `.lrc.bak`은 「재타이밍 전 원본」
  /// ([backup])이라는 다른 뜻이라, 저장 때마다 갈면 G 복구가 엉뚱한 판본을 되살린다.
  Future<String?> write(String songId, String content) async {
    try {
      final file = await fileFor(songId);
      if (!await writeTextAtomically(file, content)) return null;
      return fileNameFor(songId);
    } catch (e) {
      debugPrint('lrc 저장 실패($songId): $e');
      return null;
    }
  }

  /// 재타이밍 전에 원본을 남긴다. 이미 백업이 있으면 덮지 않는다 —
  /// 첫 원본이 진짜 원본이다(재타이밍을 거듭해도 되돌아갈 곳은 하나).
  Future<void> backup(String songId) async {
    try {
      final file = await fileFor(songId);
      if (!await file.exists()) return;
      final bak = File('${file.path}.bak');
      if (await bak.exists()) return;
      await file.copy(bak.path);
    } catch (e) {
      debugPrint('lrc 백업 실패($songId): $e');
    }
  }

  /// 보관된 원본(.bak)을 읽는다. 없으면 null.
  Future<String?> readBackup(String songId) async {
    try {
      final bak = File('${(await fileFor(songId)).path}.bak');
      if (!await bak.exists()) return null;
      final raw = await bak.readAsString();
      return raw.trim().isEmpty ? null : raw;
    } catch (e) {
      debugPrint('lrc 백업 읽기 실패($songId): $e');
      return null;
    }
  }

  /// 보관된 원본(.bak)을 지운다 — 새 가사가 부착돼 옛 원본이 남의 판본이
  /// 됐을 때. (안 지우면 G 복구가 예전 판본을 되살린다)
  Future<void> deleteBackup(String songId) async {
    try {
      final bak = File('${(await fileFor(songId)).path}.bak');
      if (await bak.exists()) await bak.delete();
    } catch (e) {
      debugPrint('lrc 백업 삭제 실패($songId): $e');
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
