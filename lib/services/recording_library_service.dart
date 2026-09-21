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
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/recording_take.dart';
import '../utils/korean_text.dart';

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

/// 파일을 못 열었을 때(읽기·정본 교체) 다시 해 보는 횟수.
///
/// Windows에서는 누가 그 파일을 쥐고 있는 순간에 열기·rename이 거절된다(errno 32).
/// 백신·동기화·제어 API의 목록 조회가 그렇고, **우리 자신의 정본 교체 순간**에
/// 다른 핸들이 읽어도 그렇다(테스트에서 실측). 길어야 수십 ms라 **조건 루프**로
/// 잠깐 다시 해 본다 — 이걸 「파일이 깨졌다」로 읽으면 안 된다.
const int kIndexIoAttempts = 8;

/// 다시 해 보는 간격.
const Duration kIndexIoRetryDelay = Duration(milliseconds: 40);

/// 저장 실패를 화면에 알릴 때 쓰는 문구.
const String kRecordingSaveFailedMessage =
    '녹음 목록을 저장하지 못했습니다 — 녹음 파일은 남아 있지만, 이대로 앱을 끄면 '
    '목록에서 빠질 수 있습니다. 디스크 공간과 문서 폴더 쓰기 권한을 확인해 주세요.';

/// 녹음 목록을 어디서 읽었는가. 화면이 「되살림」·「읽지 못함」을 알릴 때 쓴다.
enum RecordingIndexState {
  /// 정본을 그대로 읽었다(파일이 아직 없는 첫 실행 포함).
  ok,

  /// 정본을 읽지 못해 직전 백업(`.bak`)에서 되살렸다.
  recoveredFromBackup,

  /// 정본도 백업도 읽지 못했다. 깨진 파일은 지우지 않고 옆에 남긴다.
  unreadable,
}

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
      debugPrint('recordings.json 버전($version)이 높아 읽지 않는다.');
      return null;
    }
    final takes = decoded['takes'];
    if (takes is! List) return null;
    return takes
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => RecordingTake.fromJson(e.cast<String, dynamic>()))
        .toList();
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

  /// 파일 열기·정본 교체 재시도 간격. 테스트는 짧게 준다.
  final Duration _ioRetryDelay;

  /// 쓰기를 한 줄로 세우는 사슬. 끝 값은 「마지막 쓰기가 성공했는가」.
  Future<bool> _writeChain = Future<bool>.value(true);

  /// 아직 디스크에 안 닿은 최신 목록. 줄에 선 쓰기가 여럿이면 **가장 새 것만** 쓴다 —
  /// 목록은 통째로 쓰므로 옛 스냅샷을 거쳐 갈 이유가 없다.
  List<RecordingTake>? _pending;

  bool _lastWriteOk = true;
  RecordingIndexState _lastLoadState = RecordingIndexState.ok;

  RecordingStore({
    Future<Directory> Function()? baseDirBuilder,
    Duration ioRetryDelay = kIndexIoRetryDelay,
  }) : _baseDirBuilder = baseDirBuilder ?? getApplicationDocumentsDirectory,
       _ioRetryDelay = ioRetryDelay;

  /// 마지막 [load]가 목록을 어디서 읽었는지.
  RecordingIndexState get lastLoadState => _lastLoadState;

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
  /// 저장은 깨진 정본을 옆에 남긴 뒤에만 덮는다([_writeAtomically]).
  Future<List<RecordingTake>> load() async {
    // 줄에 선 쓰기가 있으면 끝난 뒤에 읽는다(rename 순간과 겹치지 않게).
    await _writeChain;
    try {
      final file = await _indexFile;
      final main = await _readIndex(file);
      final mainTakes = main.takes;
      if (mainTakes != null) {
        _lastLoadState = RecordingIndexState.ok;
        return mainTakes;
      }
      final backup = await _readIndex(File('${file.path}.bak'));
      final backupTakes = backup.takes;
      if (backupTakes != null) {
        debugPrint('recordings.json을 읽지 못해 .bak에서 되살린다.');
        _lastLoadState = RecordingIndexState.recoveredFromBackup;
        return backupTakes;
      }
      // 둘 다 없으면 첫 실행이다. 있는데 못 읽었으면 알린다.
      _lastLoadState = (main.exists || backup.exists)
          ? RecordingIndexState.unreadable
          : RecordingIndexState.ok;
      return [];
    } catch (e, stack) {
      debugPrint('recordings.json 로드 실패: $e\n$stack');
      _lastLoadState = RecordingIndexState.unreadable;
      return [];
    }
  }

  /// 목록을 저장한다. 디스크에 닿았으면 true.
  ///
  /// 호출 순서대로 한 줄에 서고, 자기 차례에는 **그때의 최신 목록**을 쓴다. 그래서
  /// 동시에 불린 add()/update()/remove()가 한 파일에서 섞이지 않는다.
  Future<bool> save(List<RecordingTake> takes) {
    _pending = takes;
    final step = _writeChain.then((_) async {
      final latest = _pending;
      // 앞 차례가 내 목록까지 이미 썼다 — 그 결과가 곧 내 결과다.
      if (latest == null) return _lastWriteOk;
      _pending = null;
      final ok = await _writeAtomically(latest);
      // 실패했으면 다음 차례가 다시 해 보도록 되돌려 둔다(더 새 목록이 있으면 그쪽).
      if (!ok) _pending ??= latest;
      return _lastWriteOk = ok;
    });
    _writeChain = step;
    return step;
  }

  /// 파일 하나를 목록으로 읽는다. 세 가지를 가른다:
  /// 없음(exists=false) / 읽었는데 내용이 깨짐(corrupt=true) / 지금 열 수 없음.
  ///
  /// 열기 거절은 조건 루프로 다시 해 본 뒤에야 포기한다. 포기해도 「깨짐」은 아니다 —
  /// 내용을 본 적이 없으므로 옆으로 치우거나 백업을 갈지 않는다.
  Future<({bool exists, bool corrupt, List<RecordingTake>? takes})> _readIndex(
    File file,
  ) async {
    for (var attempt = 1; ; attempt++) {
      try {
        if (!await file.exists()) {
          return (exists: false, corrupt: false, takes: null);
        }
        // 깨진 UTF-8에서 예외가 나지 않게 바이트로 읽어 너그럽게 푼다 —
        // 그러면 남는 예외는 전부 「못 엶」이다.
        final text = utf8.decode(
          await file.readAsBytes(),
          allowMalformed: true,
        );
        final takes = decodeRecordingIndex(text);
        return (exists: true, corrupt: takes == null, takes: takes);
      } on FileSystemException catch (e) {
        if (attempt >= kIndexIoAttempts) {
          debugPrint('${file.path} 열기 실패: $e');
          return (exists: true, corrupt: false, takes: null);
        }
        await Future<void>.delayed(_ioRetryDelay);
      }
    }
  }

  /// `.tmp` → flush → (직전 정본을 `.bak`으로) → rename. 성공하면 true.
  Future<bool> _writeAtomically(List<RecordingTake> takes) async {
    File? tmp;
    try {
      final file = await _indexFile;
      final current = await _readIndex(file);
      final unreadable = current.exists && current.takes == null;

      // 🔴 못 읽은 정본을 빈 목록으로 덮지 않는다. 손으로 되살릴 마지막 단서다.
      // (깨졌든 지금 못 열든 같다 — 안에 무엇이 있는지 모른다.)
      if (unreadable && takes.isEmpty) {
        debugPrint('recordings.json을 읽지 못한 상태라 빈 목록으로 덮지 않는다.');
        return false;
      }
      // 🔴 「지금 못 연」 정본은 목록이 있어도 덮지 않는다. 깨진 파일은 옆에 사본을
      // 남기고 덮지만, 못 연 파일은 사본도 백업도 뜰 수 없다 — 읽기만 막힌 파일
      // (오프라인 OneDrive 자리표시자 등)이 흔적 없이 교체된다. 저장은 실패로 올리고,
      // 메모리 목록은 다음 저장에 함께 실린다.
      if (unreadable && !current.corrupt) {
        debugPrint('recordings.json을 지금 열 수 없어 덮지 않는다.');
        return false;
      }

      final bytes = utf8.encode(encodeRecordingIndex(takes));
      tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      if (await tmp.length() != bytes.length) {
        throw FileSystemException('임시 파일 크기가 맞지 않는다', tmp.path);
      }

      if (current.corrupt) {
        // 깨진 정본은 옆에 남긴다. 못 남기면 덮지도 않는다(예외 → false).
        await file.copy('${file.path}.corrupt-${_stamp(DateTime.now())}');
      } else if (current.takes != null) {
        // 읽히는 정본만 백업으로 보낸다. 못 연 정본은 백업도 복사도 하지 않는다 —
        // 멀쩡한 .bak을 내용 모를 파일로 덮을 수 없다.
        await _backupQuietly(file);
      }

      await _replace(tmp, file.path);
      return true;
    } catch (e, stack) {
      debugPrint('recordings.json 저장 실패: $e\n$stack');
      await _deleteQuietly(tmp);
      return false;
    }
  }

  /// 읽히는 직전 정본을 `.bak`에 둔다. 실패해도 저장은 계속한다 —
  /// 백업을 못 떴다고 새 녹음을 목록에서 빼는 쪽이 더 큰 손해다.
  Future<void> _backupQuietly(File file) async {
    try {
      await file.copy('${file.path}.bak');
    } catch (e) {
      debugPrint('recordings.json 백업 실패: $e');
    }
  }

  /// 임시 파일을 정본 자리로 옮긴다. 거절되면 조건 루프로 잠깐 다시 해 본다.
  Future<void> _replace(File tmp, String targetPath) async {
    for (var attempt = 1; ; attempt++) {
      try {
        await tmp.rename(targetPath);
        return;
      } on FileSystemException {
        if (attempt >= kIndexIoAttempts) rethrow;
        await Future<void>.delayed(_ioRetryDelay);
      }
    }
  }

  /// 있으면 지운다. 실패는 넘어간다(다음 저장이 같은 이름을 덮어쓴다).
  Future<void> _deleteQuietly(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// 파일 이름에 쓸 시각 도장(yyyyMMdd_HHmmss).
  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

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

  /// 같은 id의 테이크를 바꿔 끼운다. 디스크에 닿았으면 true.
  Future<bool> update(RecordingTake take) {
    _takes = _takes.map((t) => t.id == take.id ? take : t).toList();
    return _persist();
  }

  /// 테이크와 그 파일들을 지운다. 목록이 디스크에 닿았으면 true.
  Future<bool> remove(RecordingTake take) async {
    // 보컬 원본과 함께 부속 파일(반주 조각·믹스·분리 보컬)도 지운다.
    await purgeFiles(take);
    _takes = _takes.where((t) => t.id != take.id).toList();
    _noteRemoved(take.id);
    return _persist();
  }

  /// 목록에서만 빼고 **파일은 남긴다.** 실행취소(Ctrl+R 직후)를 위한 경로다 —
  /// 파일까지 지우면 되돌릴 수가 없다. 되살리지 않으면 [purgeFiles]로 치운다.
  Future<bool> removeRecordOnly(RecordingTake take) {
    _takes = _takes.where((t) => t.id != take.id).toList();
    _noteRemoved(take.id);
    return _persist();
  }

  /// [removeRecordOnly]로 뺀 테이크의 파일들을 실제로 지운다.
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
