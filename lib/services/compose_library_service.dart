// file: lib/services/compose_library_service.dart
//
// AI 생성곡 목록의 저장·관리. RecordingStore와 같은 구조 —
// data/compose/ 폴더 + compositions.json(schemaVersion 1, 상위 버전 거부).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/composition.dart';

class ComposeStore {
  static const int schemaVersion = 1;

  Future<Directory> get composeDir async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/data/compose');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> get _indexFile async {
    final dir = await composeDir;
    return File('${dir.path}/compositions.json');
  }

  Future<List<Composition>> load() async {
    try {
      final file = await _indexFile;
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return [];
      final version = (decoded['schemaVersion'] as num?)?.toInt() ?? 1;
      if (version > schemaVersion) {
        debugPrint('compositions.json 버전($version)이 높아 읽지 않는다.');
        return [];
      }
      final items = decoded['compositions'];
      if (items is! List) return [];
      return items
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => Composition.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (e, stack) {
      debugPrint('compositions.json 로드 실패: $e\n$stack');
      return [];
    }
  }

  Future<void> save(List<Composition> items) async {
    try {
      final file = await _indexFile;
      final payload = {
        'schemaVersion': schemaVersion,
        'compositions': items.map((c) => c.toJson()).toList(),
      };
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
      );
    } catch (e, stack) {
      debugPrint('compositions.json 저장 실패: $e\n$stack');
    }
  }

  Future<String> pathFor(String fileName) async =>
      '${(await composeDir).path}/$fileName';

  Future<void> deleteFile(String fileName) async {
    try {
      final file = File(await pathFor(fileName));
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('생성곡 파일 삭제 실패($fileName): $e');
    }
  }
}

class ComposeLibraryService {
  final ComposeStore _store;

  List<Composition> _items = [];

  ComposeLibraryService({ComposeStore? store}) : _store = store ?? ComposeStore();

  /// 최신 생성이 위로 오게 정렬해 돌려준다.
  List<Composition> get items {
    final sorted = List<Composition>.from(_items)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(sorted);
  }

  Future<void> load() async {
    _items = await _store.load();
  }

  Future<void> add(Composition item) async {
    _items = [..._items, item];
    await _store.save(_items);
  }

  Future<void> update(Composition item) async {
    _items = _items.map((c) => c.id == item.id ? item : c).toList();
    await _store.save(_items);
  }

  Future<void> remove(Composition item) async {
    await _store.deleteFile(item.fileName);
    _items = _items.where((c) => c.id != item.id).toList();
    await _store.save(_items);
  }

  Composition? byId(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<String> pathFor(Composition item) => _store.pathFor(item.fileName);

  Future<Directory> directory() => _store.composeDir;
}
