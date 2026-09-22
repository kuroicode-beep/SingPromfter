// file: lib/services/compose_library_service.dart
//
// AI 생성곡 목록의 저장·관리. RecordingStore와 같은 구조 —
// data/compose/ 폴더 + compositions.json(schemaVersion 1, 상위 버전 거부).
//
// 🔴 v5.17.0: 쓰기는 공용 헬퍼(atomic_json_file.dart)로 한다. 예전에는 정본을 곧바로
// 덮어썼고 저장 예외를 삼켰으며, 못 읽은 파일을 빈 목록으로 읽었다 — 그 다음 add가
// 목록 전체를 덮어 가사·스타일 프롬프트·시드가 날아가고 오디오 파일만 남는다.
// 화면·제어 API·작곡 완료가 겹쳐 부를 수 있어 쓰기도 한 줄로 세운다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/composition.dart';
import 'atomic_json_file.dart';

/// 저장 실패를 화면에 알릴 때 쓰는 문구.
const String kComposeSaveFailedMessage =
    '생성곡 목록을 저장하지 못했습니다 — 오디오 파일은 남아 있지만, 이대로 앱을 끄면 '
    '방금 바꾼 내용이 목록에서 빠질 수 있습니다. 디스크 공간과 문서 폴더 쓰기 권한을 '
    '확인해 주세요.';

/// compositions.json 본문을 만든다. (순수 함수)
String encodeCompositionIndex(List<Composition> items) {
  return const JsonEncoder.withIndent('  ').convert({
    'schemaVersion': ComposeStore.schemaVersion,
    'compositions': items.map((c) => c.toJson()).toList(),
  });
}

/// compositions.json 본문을 생성곡 목록으로 푼다. 못 읽으면 null. (순수 함수)
///
/// 🔴 「못 읽음(null)」과 「빈 목록([])」을 가른다. 빈 파일·잘린 JSON을 빈 목록으로
/// 읽으면 다음 저장이 목록 전체를 지운다. 상위 버전은 null이 아니라
/// [AtomicSchemaException]이다 — null이면 헬퍼가 「깨진 파일」로 보고 첫 저장에서
/// `.corrupt-`로 옮긴 뒤 구버전 봉투로 갈아 끼운다.
List<Composition>? decodeCompositionIndex(String raw) {
  final text = stripBom(raw);
  if (text.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) return null;
    final version = (decoded['schemaVersion'] as num?)?.toInt() ?? 1;
    if (version > ComposeStore.schemaVersion) {
      throw AtomicSchemaException(
        'compositions.json 버전($version)이 이 앱 버전(최대 '
        '${ComposeStore.schemaVersion})보다 높아 읽지 않습니다. 앱을 업데이트해 주세요.',
      );
    }
    final items = decoded['compositions'];
    if (items is! List) return null;
    return items
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => Composition.fromJson(e.cast<String, dynamic>()))
        .toList();
  } on AtomicSchemaException {
    rethrow;
  } catch (e) {
    debugPrint('compositions.json 해석 실패: $e');
    return null;
  }
}

class ComposeStore {
  static const int schemaVersion = 1;

  /// 데이터 폴더의 뿌리(기본: 문서 폴더). 테스트는 임시 폴더를 준다.
  final Future<Directory> Function() _baseDirBuilder;

  late final AtomicJsonFile<List<Composition>> _index;

  ComposeStore({
    Future<Directory> Function()? baseDirBuilder,
    Duration ioRetryDelay = kAtomicIoRetryDelay,
  }) : _baseDirBuilder = baseDirBuilder ?? getApplicationDocumentsDirectory {
    _index = AtomicJsonFile<List<Composition>>(
      fileBuilder: () => _indexFile,
      encode: encodeCompositionIndex,
      decode: decodeCompositionIndex,
      isEmpty: (items) => items.isEmpty,
      label: 'compositions.json',
      // 못 열고 시작한 목록으로 저장해도 정본에만 있던 생성곡이 사라지지 않게 한다.
      rescue: AtomicRescue.listById<Composition>((item) => item.id),
      ioRetryDelay: ioRetryDelay,
    );
  }

  /// 마지막 [load]가 목록을 어디서 읽었는지(정본·백업·읽지 못함).
  AtomicLoadState get lastLoadState => _index.lastLoadState;

  Future<Directory> get composeDir async {
    final base = await _baseDirBuilder();
    final dir = Directory('${base.path}/data/compose');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> get _indexFile async {
    final dir = await composeDir;
    return File('${dir.path}/compositions.json');
  }

  /// 목록을 읽는다. 정본을 못 읽으면 `.bak`에서 되살리고, 둘 다 안 되면 [].
  ///
  /// 상위 버전 파일은 빈 목록이지만 [lastLoadState]가 unreadable로 서고, 헬퍼가
  /// 그 정본을 어떤 저장으로도 덮지 않는다(save는 false).
  Future<List<Composition>> load() async {
    try {
      return await _index.load() ?? [];
    } on AtomicSchemaException catch (e) {
      debugPrint('$e');
      return [];
    }
  }

  /// 목록을 저장한다. 디스크에 닿았으면 true. 호출 순서대로 한 줄에 선다.
  Future<bool> save(List<Composition> items) => _index.save(items);

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

  /// 목록 저장이 실패하면 불린다. 조용히 넘기면 다음 실행에서 방금 만든 곡이 목록에
  /// 없다(오디오 파일만 남는다). 연속 실패는 첫 번째만 알린다.
  void Function(String message)? onSaveFailed;

  final SaveFailureGate _saveFailureGate = SaveFailureGate();

  ComposeLibraryService({ComposeStore? store}) : _store = store ?? ComposeStore();

  /// 마지막 [load]가 목록을 어디서 읽었는지(정본·백업·읽지 못함).
  AtomicLoadState get loadState => _store.lastLoadState;

  /// 최신 생성이 위로 오게 정렬해 돌려준다.
  List<Composition> get items {
    final sorted = List<Composition>.from(_items)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(sorted);
  }

  Future<void> load() async {
    _items = await _store.load();
  }

  /// 지금 목록을 저장한다. 실패하면 [onSaveFailed]로 알리고 false.
  /// 메모리의 목록은 그대로 두므로 다음 저장이 성공하면 함께 디스크에 닿는다.
  Future<bool> _persist() async {
    final ok = await _store.save(_items);
    if (_saveFailureGate.shouldNotify(saved: ok)) {
      onSaveFailed?.call(kComposeSaveFailedMessage);
    }
    return ok;
  }

  /// 생성곡을 목록에 더한다. 디스크에 닿았으면 true.
  Future<bool> add(Composition item) {
    _items = [..._items, item];
    return _persist();
  }

  /// 같은 id의 생성곡을 **통째로** 바꿔 끼운다. 디스크에 닿았으면 true.
  ///
  /// 예전에 집어 둔 사본을 고쳐서 넘기면 그사이의 다른 변경이 되돌아간다 — 필드 몇 개만
  /// 바꾸는 일은 [patch]를 쓴다.
  Future<bool> update(Composition item) {
    _items = _items.map((c) => c.id == item.id ? item : c).toList();
    return _persist();
  }

  /// 같은 id의 **지금** 생성곡에 [change]를 얹는다. 바뀐 생성곡을 돌려주고, 목록에
  /// 없으면 아무것도 하지 않고 null(저장도 돌지 않는다).
  ///
  /// 곡으로 등록하는 일은 파일 복사를 기다린다 — 그사이 제목을 바꾸면, 등록이 시작할 때
  /// 집어 둔 사본을 통째로 저장하는 [update]가 새 제목을 되돌렸다(반대로 제목 저장은
  /// 등록 표시를 지웠다). 읽기~교체 사이에 await가 없어 끼어들 틈이 없다.
  Future<Composition?> patch(
    String id,
    Composition Function(Composition current) change,
  ) async {
    final index = _items.indexWhere((c) => c.id == id);
    // 그사이 지운 생성곡이다 — 되살리지 않는다.
    if (index < 0) return null;
    final next = change(_items[index]);
    assert(next.id == id, 'patch는 같은 생성곡을 돌려줘야 한다');
    _items = [..._items]..[index] = next;
    await _persist();
    return next;
  }

  /// 생성곡과 그 오디오 파일을 지운다. 목록이 디스크에 닿았으면 true.
  Future<bool> remove(Composition item) async {
    await _store.deleteFile(item.fileName);
    _items = _items.where((c) => c.id != item.id).toList();
    return _persist();
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
