// file: lib/services/recording_library_service.dart
//
// 녹음 테이크 목록의 저장·필터. 순수 로직과 I/O를 나눠 둔다.
//
// 🔴 저장은 **한 줄로 세워서, 원자적으로** 한다 (v5.16.0).
//
// 예전 save()는 정본을 곧바로 덮어썼고 예외를 삼켰다. 녹음 직후의 add()와
// 기다리지 않고 도는 반주 컷의 update()가 겹치면 두 쓰기가 한 파일에서 섞여
// JSON이 깨졌고, load()는 깨진 파일을 「빈 목록」으로 읽었다 — 그 상태에서 한 번
// 더 저장하면 **녹음 목록 전체가 증발**한다. 녹음 고정은 스페이스로 멈출 때마다
// 이 두 쓰기를 짧은 간격으로 부르므로 노출이 훨씬 잦다.
//
//   · 직렬 — 쓰기는 Future 사슬 하나에 세운다. 앞의 것이 끝나야 다음이 돈다.
//   · 원자 — `<파일>.tmp`에 쓰고 flush → rename으로 정본을 바꾼다. 쓰다 죽어도
//     정본 자리에 반쪽짜리 JSON이 남지 않는다.
//   · 백업 — 바꾸기 직전의 **읽히는** 정본을 `<파일>.bak`에 한 벌 둔다. 못 읽는
//     정본으로 멀쩡한 백업을 덮지 않는다.
//   · 못 읽은 정본은 「빈 목록」이 아니다. `.bak`으로 되살리고, 그것도 안 되면
//     깨진 파일을 옆에 남긴 뒤에 새로 쓴다. 빈 목록으로는 아예 덮지 않는다.
//   · 「지금 못 연」 정본(잠김·오프라인 자리표시자)은 **아예 덮지 않는다** — 내용을 본
//     적이 없어 백업도 사본도 뜰 수 없다. 메모리 목록은 정본의 후손이 아니므로, 다음
//     저장 전에 정본을 다시 읽어 id로 합친다(RecordingLibraryService).
//   · 저장 실패는 삼키지 않는다 — 반환값(bool)과 onSaveFailed로 올린다.
//
// v5.17.0: 위 규칙의 구현은 공용 헬퍼(atomic_json_file.dart)로 옮겼다 — 곡 목록·
// 생성곡·연습 기록도 같은 규칙을 쓴다. 여기 남은 것은 본문 형식과 id 합치기다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/recording_take.dart';
import '../utils/korean_text.dart';
import 'atomic_json_file.dart';

/// 목록 필터 — 순수 함수라 파일 없이 테스트한다.
class RecordingFilter {
  RecordingFilter._();

  static List<RecordingTake> apply(
    List<RecordingTake> takes, {
    String query = '',
    RecordingFilterMode mode = RecordingFilterMode.all,
    String? songId,
  }) {
    final trimmed = query.trim();
    return takes.where((take) {
      if (songId != null && take.songId != songId) return false;

      switch (mode) {
        case RecordingFilterMode.all:
          break;
        case RecordingFilterMode.rated:
          if (!take.isRated) return false;
        case RecordingFilterMode.commented:
          if (!take.hasComment) return false;
        case RecordingFilterMode.keep:
          if (!take.isKeep) return false;
      }

      if (trimmed.isEmpty) return true;
      return KoreanText.matches(take.songTitle, trimmed) ||
          KoreanText.matches(take.comment, trimmed);
    }).toList(growable: false);
  }

  /// 최근 녹음이 위로 오도록 정렬한다.
  static List<RecordingTake> sortByNewest(List<RecordingTake> takes) {
    final sorted = List<RecordingTake>.from(takes)
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return List.unmodifiable(sorted);
  }
}

/// 파일 열기·정본 교체를 다시 해 보는 횟수와 간격 — 공용 헬퍼의 값을 그대로 쓴다.
/// (Windows의 순간 잠금 errno 32 때문에 둔다. 자세한 까닭은 atomic_json_file.dart.)
const int kIndexIoAttempts = kAtomicIoAttempts;

/// 다시 해 보는 간격.
const Duration kIndexIoRetryDelay = kAtomicIoRetryDelay;

/// 저장 실패를 화면에 알릴 때 쓰는 문구.
const String kRecordingSaveFailedMessage =
    '녹음 목록을 저장하지 못했습니다 — 녹음 파일은 남아 있지만, 이대로 앱을 끄면 '
    '목록에서 빠질 수 있습니다. 디스크 공간과 문서 폴더 쓰기 권한을 확인해 주세요.';

/// 녹음 목록을 어디서 읽었는가. 화면이 「되살림」·「읽지 못함」을 알릴 때 쓴다.
/// (ok / recoveredFromBackup / unreadable — 공용 헬퍼의 상태와 같은 것이다.)
typedef RecordingIndexState = AtomicLoadState;

/// recordings.json 본문을 만든다. (순수 함수)
String encodeRecordingIndex(List<RecordingTake> takes) {
  return const JsonEncoder.withIndent('  ').convert({
    'schemaVersion': RecordingStore.schemaVersion,
    'takes': takes.map((t) => t.toJson()).toList(),
  });
}

/// recordings.json 본문을 테이크 목록으로 푼다. 못 읽으면 null. (순수 함수)
///
/// 🔴 「못 읽음(null)」과 「빈 목록([])」을 반드시 가른다. 빈 문자열도 null이다 —
/// 쓰다 죽은 파일이 남기는 모양이 바로 길이 0이라, 이를 빈 목록으로 읽으면
/// 다음 저장이 목록 전체를 지운다.
List<RecordingTake>? decodeRecordingIndex(String raw) {
  // 밖에서 손본 파일(파이썬 utf-8-sig 등)에는 BOM이 붙어 올 수 있다.
  final text = raw.startsWith('\uFEFF') ? raw.substring(1) : raw;
  if (text.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) return null;
    final version = (decoded['schemaVersion'] as num?)?.toInt() ?? 1;
    if (version > RecordingStore.schemaVersion) {
      // 🔴 null(깨짐)이 아니라 예외(읽기 거부)다 — null이면 헬퍼가 첫 저장에서
      // `.corrupt-`로 옮기고 구버전 봉투로 갈아 끼운다(더 새 빌드의 목록이 빠진다).
      throw AtomicSchemaException(
        'recordings.json 버전($version)이 이 앱 버전(최대 '
        '${RecordingStore.schemaVersion})보다 높아 읽지 않습니다. 앱을 업데이트해 주세요.',
      );
    }
    final takes = decoded['takes'];
    if (takes is! List) return null;
    return takes
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => RecordingTake.fromJson(e.cast<String, dynamic>()))
        .toList();
  } on AtomicSchemaException {
    rethrow;
  } catch (e) {
    debugPrint('recordings.json 해석 실패: $e');
    return null;
  }
}

class RecordingStore {
  /// v2: 반주 조각·믹스 설정·분리 보컬 필드 추가 (additive — v1 파일 그대로 읽힘).
  static const int schemaVersion = 2;

  /// 데이터 폴더의 뿌리(기본: 문서 폴더). 테스트는 임시 폴더를 준다.
  final Future<Directory> Function() _baseDirBuilder;

  /// recordings.json의 읽기·쓰기 규칙(직렬·원자 교체·`.bak`·못 읽은 정본 보호).
  ///
  /// 🔴 못 열고 시작한 정본을 살리는 일(rescue)은 여기서 맡기지 않는다 — 그동안
  /// **지운** 테이크를 되살리면 안 되므로 [RecordingLibraryService]가 직접 합친다.
  late final AtomicJsonFile<List<RecordingTake>> _index;

  RecordingStore({
    Future<Directory> Function()? baseDirBuilder,
    Duration ioRetryDelay = kIndexIoRetryDelay,
  }) : _baseDirBuilder = baseDirBuilder ?? getApplicationDocumentsDirectory {
    _index = AtomicJsonFile<List<RecordingTake>>(
      fileBuilder: () => _indexFile,
      encode: encodeRecordingIndex,
      decode: decodeRecordingIndex,
      isEmpty: (takes) => takes.isEmpty,
      label: 'recordings.json',
      ioRetryDelay: ioRetryDelay,
    );
  }

  /// 마지막 [load]가 목록을 어디서 읽었는지.
  RecordingIndexState get lastLoadState => _index.lastLoadState;

  Future<Directory> get recordingsDir async {
    final base = await _baseDirBuilder();
    final dir = Directory('${base.path}/data/recordings');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> get _indexFile async {
    final base = await _baseDirBuilder();
    final dir = Directory('${base.path}/data');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/recordings.json');
  }

  /// 목록을 읽는다. 정본을 못 읽으면 `.bak`에서 되살린다.
  ///
  /// 둘 다 못 읽으면 []를 주지만 [lastLoadState]가 unreadable로 선다 — 그 상태의
  /// 저장은 깨진 정본을 옆에 남긴 뒤에만 덮는다(빈 목록으로는 아예 덮지 않는다).
  /// 상위 버전 파일도 []이지만 「읽기 거부」라 어떤 저장으로도 덮지 않는다(save는 false).
  Future<List<RecordingTake>> load() async {
    try {
      return await _index.load() ?? [];
    } on AtomicSchemaException catch (e) {
      debugPrint('$e');
      return [];
    }
  }

  /// 목록을 저장한다. 디스크에 닿았으면 true.
  ///
  /// 호출 순서대로 한 줄에 서고, 자기 차례에는 **그때의 최신 목록**을 쓴다. 그래서
  /// 동시에 불린 add()/update()/remove()가 한 파일에서 섞이지 않는다.
  Future<bool> save(List<RecordingTake> takes) => _index.save(takes);

  Future<String> pathFor(String fileName) async =>
      '${(await recordingsDir).path}/$fileName';

  Future<void> deleteFile(String fileName) async {
    try {
      final file = File(await pathFor(fileName));
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('녹음 파일 삭제 실패($fileName): $e');
    }
  }
}

class RecordingLibraryService {
  final RecordingStore _store;

  List<RecordingTake> _takes = [];

  /// 목록 저장이 실패하면 불린다. 조용히 넘기면 다음 실행에서 방금 녹음이 목록에
  /// 없다(파일만 남는다) — 화면이 큰 경고로 알려야 한다.
  void Function(String message)? onSaveFailed;

  RecordingLibraryService({RecordingStore? store})
    : _store = store ?? RecordingStore();

  List<RecordingTake> get takes => RecordingFilter.sortByNewest(_takes);

  /// 마지막 [load]가 목록을 어디서 읽었는지(정본·백업·읽지 못함).
  RecordingIndexState get loadState => _store.lastLoadState;

  Future<void> load() async {
    _takes = await _store.load();
  }

  /// 정본을 못 읽고 시작한 동안 지운 id — 되읽어 합칠 때 되살리지 않는다.
  final Set<String> _removedWhileIncomplete = {};

  /// 돌고 있는 되읽기. 기다리지 않고 연달아 불린 add()/update()가 같은 것을 기다린다.
  Future<void>? _healing;

  /// 부팅 때 정본을 못 읽었으면 쓰기 **전에** 다시 읽어 id로 합친다.
  ///
  /// 정본이 잠깐 안 열려(다른 프로세스의 잠금·오프라인 자리표시자) 빈 목록이나 한 박자
  /// 낡은 `.bak`으로 시작했다면, 메모리 목록은 정본의 후손이 아니다. 그대로 저장하면
  /// 첫 저장이 옛 전체 목록을 `.bak`으로 밀고, 다음 저장이 그 `.bak`마저 덮어 **목록
  /// 전체가 두 파일에서 사라진다**(WAV만 남는다). 정본이 읽히는 순간 합쳐 둔다.
  /// 진짜로 깨진 정본은 다시 읽어도 ok가 되지 않는다 — 기존 `.corrupt` 경로가 맡는다.
  Future<void> _mergeDiskIfIncomplete() {
    if (_store.lastLoadState == RecordingIndexState.ok) {
      return Future<void>.value();
    }
    return _healing ??= () async {
      try {
        final disk = await _store.load();
        if (_store.lastLoadState != RecordingIndexState.ok) return;
        final mine = {for (final take in _takes) take.id};
        _takes = [
          for (final take in disk)
            if (!mine.contains(take.id) &&
                !_removedWhileIncomplete.contains(take.id))
              take,
          // 같은 id는 메모리 쪽이 이긴다 — 그사이 고친 내용이다.
          ..._takes,
        ];
        _removedWhileIncomplete.clear();
      } finally {
        _healing = null;
      }
    }();
  }

  /// 지금 목록을 저장한다. 실패하면 [onSaveFailed]로 알리고 false.
  /// 메모리의 목록은 그대로 두므로 다음 저장이 성공하면 함께 디스크에 닿는다.
  Future<bool> _persist() async {
    await _mergeDiskIfIncomplete();
    final ok = await _store.save(_takes);
    if (!ok) onSaveFailed?.call(kRecordingSaveFailedMessage);
    return ok;
  }

  /// 목록에서 뺀 id를 적어 둔다 — 정본을 못 읽은 동안이면 되읽을 때 되살아나지 않게.
  void _noteRemoved(String id) {
    if (_store.lastLoadState != RecordingIndexState.ok) {
      _removedWhileIncomplete.add(id);
    }
  }

  /// 테이크를 목록에 더한다. 디스크에 닿았으면 true.
  Future<bool> add(RecordingTake take) {
    _takes = [..._takes, take];
    return _persist();
  }

  /// 같은 id의 테이크를 **통째로** 바꿔 끼운다. 디스크에 닿았으면 true.
  ///
  /// 🔴 예전에 집어 둔 사본을 고쳐서 넘기면 안 된다 — 그사이의 다른 변경이 되돌아간다.
  /// 필드 몇 개만 바꾸는 일은 [patch]를, 만든 파일을 붙이는 일은 [attachFile]을 쓴다.
  Future<bool> update(RecordingTake take) {
    _takes = _takes.map((t) => t.id == take.id ? take : t).toList();
    return _persist();
  }

  /// 같은 id의 **지금** 테이크. 목록에 없으면 null.
  RecordingTake? byId(String id) {
    for (final take in _takes) {
      if (take.id == id) return take;
    }
    return null;
  }

  /// 같은 id의 **지금** 테이크에 [change]를 얹는다. 바뀐 테이크를 돌려주고, 목록에
  /// 없으면 아무것도 하지 않고 null(저장도 돌지 않는다).
  ///
  /// 🔴 왜 [update]가 아닌가: 반주 컷·믹스·보컬 분리는 수 초~수십 초가 걸린다. 시작할 때
  /// 집어 둔 사본에 결과를 얹어 통째로 저장하면 **그사이에 준 별점·코멘트가 되돌아가고**,
  /// 거꾸로 코멘트 저장은 방금 붙은 반주 파일 이름을 null로 되돌려 파일을 고아로 만든다.
  /// 여기서는 읽기~교체 사이에 await가 없어 다른 변경이 끼어들 틈이 없고, 디스크 쓰기는
  /// 다른 add/update/remove와 같은 줄에 선다.
  Future<RecordingTake?> patch(
    String id,
    RecordingTake Function(RecordingTake current) change,
  ) async {
    final index = _takes.indexWhere((t) => t.id == id);
    // 그사이 지워졌거나 Ctrl+R로 물렸다 — 되살리지 않는다.
    if (index < 0) return null;
    final next = change(_takes[index]);
    assert(next.id == id, 'patch는 같은 테이크를 돌려줘야 한다');
    _takes = [..._takes]..[index] = next;
    await _persist();
    return next;
  }

  /// 오래 걸린 작업이 만든 부속 파일([fileName] — 반주 조각·믹스·분리 보컬)을 **지금**
  /// 테이크에 붙인다. 목록의 테이크에 붙였으면 그 테이크, 아니면 null.
  ///
  /// 목록에 없을 때는 파일이 갈 곳을 여기서 정한다 — 이름을 적어 둘 테이크가 없는 파일은
  /// [purgeFiles]가 못 지워 영영 고아로 남는다.
  /// · Ctrl+R로 물려 둔 조각이면 물린 사본에 얹는다. 되살리면 따라오고, 확정되면 함께 지워진다.
  /// · 아예 지워졌으면 그 파일을 지운다.
  Future<RecordingTake?> attachFile(
    String id,
    String fileName,
    RecordingTake Function(RecordingTake current) change,
  ) async {
    final patched = await patch(id, change);
    if (patched != null) return patched;
    final parked = _parked[id];
    if (parked != null) {
      _parked[id] = change(parked);
      return null;
    }
    await _store.deleteFile(fileName);
    return null;
  }

  /// 테이크와 그 파일들을 지운다. 목록이 디스크에 닿았으면 true.
  Future<bool> remove(RecordingTake take) async {
    // 넘겨받은 사본이 아니라 목록의 지금 것으로 지운다 — 그사이 붙은 파일 이름은 거기에만 있다.
    final current = byId(take.id) ?? take;
    // 🔴 목록에서 **먼저** 뺀다. 파일을 지우는 동안 끝난 반주 컷·믹스가 아직 목록에 있는
    // 이 테이크에 파일을 붙이면 그 파일은 지울 길이 없다. 빠진 뒤라면 [attachFile]이
    // 붙일 곳이 없음을 알고 그 파일을 직접 지운다.
    _takes = _takes.where((t) => t.id != take.id).toList();
    _noteRemoved(take.id);
    // 보컬 원본과 함께 부속 파일(반주 조각·믹스·분리 보컬)도 지운다.
    await purgeFiles(current);
    return _persist();
  }

  /// [removeRecordOnly]로 물려 둔 테이크 — 목록에는 없지만 파일은 남아 있고 되살릴 수 있다.
  ///
  /// 🔴 화면이 들고 있는 사본만으로는 모자란다. 물린 뒤에 끝난 반주 컷·믹스가 붙인 파일
  /// 이름이 그 사본에는 없어서, 되살리면 파일이 테이크에서 떨어지고 확정해도 안 지워졌다
  /// (`<id>_acc.m4a` 고아). [attachFile]이 여기에 얹어 두고 [restoreParked]·[purgeParked]가
  /// 그 최신 사본을 쓴다.
  final Map<String, RecordingTake> _parked = {};

  /// 목록에서만 빼고 **파일은 남긴다.** 실행취소(Ctrl+R 직후)를 위한 경로다 —
  /// 파일까지 지우면 되돌릴 수가 없다. [restoreParked]로 되살리거나 [purgeParked]로 치운다.
  Future<bool> removeRecordOnly(RecordingTake take) {
    // 넘겨받은 사본보다 목록의 지금 것이 새롭다(그사이 붙은 파일 이름이 들어 있다).
    _parked[take.id] = byId(take.id) ?? take;
    _takes = _takes.where((t) => t.id != take.id).toList();
    _noteRemoved(take.id);
    return _persist();
  }

  /// 물려 둔 테이크를 목록에 되돌린다. 되돌린 테이크를 주고, 물려 둔 것이 없으면 null.
  Future<RecordingTake?> restoreParked(String id) async {
    final take = _parked.remove(id);
    if (take == null) return null;
    await add(take);
    return take;
  }

  /// 물려 둔 테이크의 파일들을 실제로 지운다(되살릴 기회가 지났다).
  Future<void> purgeParked(String id) async {
    final take = _parked.remove(id);
    if (take != null) await purgeFiles(take);
  }

  /// 테이크의 파일들(보컬 원본 + 테이크에 **적힌** 부속 파일)을 실제로 지운다.
  Future<void> purgeFiles(RecordingTake take) async {
    await _store.deleteFile(take.fileName);
    for (final attached in [
      take.accompanimentFileName,
      take.mixedFileName,
      take.separatedFileName,
    ]) {
      if (attached != null && attached.isNotEmpty) {
        await _store.deleteFile(attached);
      }
    }
  }

  Future<String> pathFor(RecordingTake take) => _store.pathFor(take.fileName);

  Future<Directory> directory() => _store.recordingsDir;
}
