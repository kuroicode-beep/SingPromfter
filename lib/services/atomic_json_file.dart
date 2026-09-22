// file: lib/services/atomic_json_file.dart
//
// 작은 데이터 파일을 **한 줄로 세워서, 원자적으로** 쓰는 공용 헬퍼 (v5.17.0).
//
// RecordingStore(v5.16.0)가 녹음 목록을 지키려고 만든 저장 규칙을 그대로 옮겼다.
// 곡 목록·생성곡·연습 기록·일일 목표도 똑같이 「정본에 곧바로 writeAsString +
// 못 읽으면 빈 값」이었다 — 두 쓰기가 한 파일에서 섞이면 JSON이 깨지고, 깨진 파일은
// 빈 목록으로 읽히고, 그 다음 저장이 **전체를 지운다.** 규칙은 하나로 모은다.
//
//   · 직렬 — 인스턴스의 쓰기는 Future 사슬 하나에 세우고, 줄에 선 것이 여럿이면
//     가장 새 값만 쓴다(통째로 쓰는 파일이라 옛 스냅샷을 거쳐 갈 이유가 없다).
//   · 경로 잠금 — 같은 파일을 쓰는 인스턴스가 여럿일 수 있다(연습 기록: 화면·백업
//     병합·폰 동기화). 인스턴스별 사슬만으로는 같은 `.tmp`를 동시에 쓰게 되므로,
//     임계 구역은 **경로 단위**로 한 번 더 세운다.
//   · 원자 — `<파일>.tmp`에 쓰고 flush → 크기 확인 → rename. 쓰다 죽어도 정본
//     자리에 반쪽짜리 파일이 남지 않는다.
//   · 백업 — 바꾸기 직전의 **읽히는** 정본을 `<파일>.bak`에 한 벌 둔다. 못 읽는
//     정본으로 멀쩡한 백업을 덮지 않는다.
//   · 「못 읽음(null)」은 「빈 값」이 아니다. `.bak`으로 되살리고, 그것도 안 되면
//     깨진 파일을 `.corrupt-<시각>`으로 옆에 남긴 뒤에만 새로 쓴다. 빈 값으로는
//     아예 덮지 않는다.
//   · 「지금 못 연」 정본(잠김·오프라인 자리표시자)은 **값이 있어도 덮지 않는다** —
//     내용을 본 적이 없어 백업도 사본도 뜰 수 없다.
//   · 못 열고 시작한 메모리 값은 정본의 후손이 아니다. 정본이 다시 열리면 거기에만
//     있던 항목을 골라 이번 실행 내내 함께 싣는다([AtomicRescue]). 안 그러면 저장
//     두 번에 정본과 `.bak`이 모두 새 값으로 덮인다. 단 **호출자가 본 값(`.bak`)에
//     있던 항목**은 살리지 않는다 — 없으면 지운 것이다(유령 항목 방지).
//   · 상위 schemaVersion은 「깨짐(null)」이 아니라 [AtomicSchemaException]이다 —
//     읽기 거부라 어떤 저장도 덮지 않는다(구버전 exe로 되돌아간 경우).
//   · 실패는 삼키지 않는다 — 반환값으로 올린다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 파일을 못 열었을 때(읽기·정본 교체) 다시 해 보는 횟수.
///
/// Windows에서는 누가 그 파일을 쥐고 있는 순간에 열기·rename이 거절된다(errno 32).
/// 백신·동기화·제어 API의 목록 조회가 그렇고, **우리 자신의 정본 교체 순간**에
/// 다른 핸들이 읽어도 그렇다(테스트에서 실측). 길어야 수십 ms라 **조건 루프**로
/// 잠깐 다시 해 본다 — 이걸 「파일이 깨졌다」로 읽으면 안 된다.
const int kAtomicIoAttempts = 8;

/// 다시 해 보는 간격.
const Duration kAtomicIoRetryDelay = Duration(milliseconds: 40);

/// 앞머리의 BOM을 뗀다. 밖에서 손본 파일(파이썬 utf-8-sig·메모장)에 붙어 온다.
String stripBom(String raw) =>
    raw.startsWith('\uFEFF') ? raw.substring(1) : raw;

/// decode가 「이 앱 버전이 읽을 수 없는 파일」을 만났다는 표시(상위 schemaVersion).
///
/// 🔴 null(깨짐)이 아니라 **예외**여야 한다 — null이면 헬퍼가 「깨진 파일」로 분류해
/// 첫 저장에서 `.corrupt-`로 옮기고 구버전 봉투로 갈아 끼운다(더 새 빌드가 써 둔 기록이
/// 정본에서 빠진다). 예외면 「읽기 거부」라 어떤 저장도 그 정본을 덮지 않는다.
/// 각 저장소의 load()가 이걸 잡아 빈 값으로 돌려주되 [AtomicJsonFile.lastLoadState]는
/// unreadable로 남는다(화면이 「앱을 업데이트해 주세요」로 알린다).
class AtomicSchemaException implements Exception {
  final String message;

  const AtomicSchemaException(this.message);

  @override
  String toString() => message;
}

/// 값을 어디서 읽었는가. 화면이 「되살림」·「읽지 못함」을 알릴 때 쓴다.
enum AtomicLoadState {
  /// 정본을 그대로 읽었다(파일이 아직 없는 첫 실행 포함).
  ok,

  /// 정본을 읽지 못해 직전 백업(`.bak`)에서 되살렸다.
  recoveredFromBackup,

  /// 정본도 백업도 읽지 못했다. 깨진 파일은 지우지 않고 옆에 남긴다.
  unreadable,
}

/// 저장 실패를 **연속 실패의 첫 번째**에만 알리게 해 주는 문지기.
///
/// 저장 실패는 큰 경고(CenterAlert)로 올리는데, 문서 폴더가 오프라인인 동안에는 모든
/// 저장이 실패한다. 곡 목록은 싱크 미세조정(./,) 한 번마다 저장되므로, 그때마다 경고를
/// 띄우면 노래하는 내내 가사가 가려진다. 실패로 **바뀐 순간**에만 알리고, 한 번 성공하면
/// 다시 알릴 수 있게 된다.
class SaveFailureGate {
  bool _failing = false;

  /// 저장 결과를 받는다. 이번 실패를 화면에 알려야 하면 true.
  bool shouldNotify({required bool saved}) {
    final notify = !saved && !_failing;
    _failing = !saved;
    return notify;
  }
}

/// 못 열고 시작한 정본을 나중에 만났을 때, 메모리에 없는 항목을 살리는 규칙.
///
/// 목록을 통째로 쓰는 저장소는 호출자가 든 값이 곧 정본이 된다. 그런데 부팅 때
/// 정본을 못 열어 빈 값(또는 한 박자 낡은 `.bak`)으로 시작했다면, 그 값은 정본을
/// 본 적이 없다. 정본이 다시 열린 첫 저장에서 [onlyInDisk]로 「정본에만 있던 항목」을
/// 골라 두고, 이후 저장마다 [join]으로 함께 싣는다. 호출자가 그 항목을 볼 수 없어
/// 지울 수도 없으므로, 다음 실행에서 정상으로 읽힐 때까지 그대로 들고 간다.
class AtomicRescue<T> {
  /// [disk]에서 [mine]에 없는 항목만 골라낸다.
  final T Function(T disk, T mine) onlyInDisk;

  /// [mine]에 [carried]를 얹는다. 같은 키는 [mine]이 이긴다.
  final T Function(T carried, T mine) join;

  const AtomicRescue({required this.onlyInDisk, required this.join});

  /// id로 가르는 목록용 규칙. 살린 항목이 앞에 온다(대개 더 오래된 것이다).
  static AtomicRescue<List<E>> listById<E>(String Function(E item) idOf) {
    List<E> missing(List<E> from, List<E> mine) {
      final ids = {for (final item in mine) idOf(item)};
      return [
        for (final item in from)
          if (!ids.contains(idOf(item))) item,
      ];
    }

    return AtomicRescue<List<E>>(
      onlyInDisk: missing,
      join: (carried, mine) => [...missing(carried, mine), ...mine],
    );
  }

  /// 키로 가르는 맵용 규칙.
  static AtomicRescue<Map<String, V>> mapByKey<V>() {
    return AtomicRescue<Map<String, V>>(
      onlyInDisk: (disk, mine) => {
        for (final entry in disk.entries)
          if (!mine.containsKey(entry.key)) entry.key: entry.value,
      },
      join: (carried, mine) => {...carried, ...mine},
    );
  }
}

/// 파일 하나를 읽은 결과. 없음 / 읽었는데 깨짐 / 지금 못 엶 / 읽기 거부를 가른다.
typedef _ReadResult<T> = ({
  bool exists,
  bool corrupt,
  T? value,
  Object? refusal,
  StackTrace? refusalStack,
});

/// decode가 「읽기를 거부」했다는 표시. load()가 원래 예외로 되돌려 던진다.
class _Refused implements Exception {
  final Object error;
  final StackTrace stack;

  const _Refused(this.error, this.stack);
}

/// 데이터 파일 하나의 읽기·쓰기 규칙. [T]는 파일 전체의 값(목록·맵)이다.
class AtomicJsonFile<T> {
  /// 파일 자리를 돌려준다. **IO마다 try 안에서** 부른다 — 폴더를 만들다 던질 수
  /// 있고(권한·잠금), 그건 그 차례만의 실패여야 한다.
  final Future<File> Function() _fileBuilder;

  /// 값을 파일 본문으로 만든다. (순수 함수)
  final String Function(T value) _encode;

  /// 본문을 값으로 푼다. 못 읽으면 **null** — 빈 문자열도 null이어야 한다(쓰다 죽은
  /// 파일이 남기는 모양이 길이 0이다). 예외를 던지면 「읽기 거부」다: load()는 그
  /// 예외를 그대로 다시 던지고(`.bak` 폴백 없음), 저장은 그 정본을 덮지 않는다.
  /// 상위 버전 파일처럼 「깨진 게 아니라 내가 못 읽는」 경우에 쓴다.
  final T? Function(String text) _decode;

  /// 빈 값인가. 못 읽은 정본을 빈 값으로 덮지 않으려고 묻는다.
  final bool Function(T value) _isEmpty;

  /// 로그에 찍을 파일 이름.
  final String _label;

  /// 직전 정본을 `.bak`으로 남길지.
  final bool _keepBackup;

  /// 못 열고 시작한 정본을 살리는 규칙. 없으면 살리지 않는다(호출자가 직접 합친다).
  final AtomicRescue<T>? _rescue;

  /// 파일 열기·정본 교체 재시도 간격. 테스트는 짧게 준다.
  final Duration _ioRetryDelay;

  /// 쓰기를 한 줄로 세우는 사슬. 끝 값은 「마지막 쓰기가 성공했는가」.
  Future<bool> _writeChain = Future<bool>.value(true);

  /// 아직 디스크에 안 닿은 최신 값. 줄에 선 쓰기가 여럿이면 **가장 새 것만** 쓴다.
  T? _pending;
  bool _hasPending = false;

  bool _lastWriteOk = true;
  AtomicLoadState _lastLoadState = AtomicLoadState.ok;

  /// 마지막 load()가 정본을 **열지 못했다** — 메모리 값이 정본의 후손이 아니다.
  bool _mainUnseen = false;

  /// 정본에만 있던 항목. 이번 실행 내내 저장마다 함께 싣는다.
  T? _carried;

  /// 못 열고 시작할 때 호출자에게 준 값(`.bak`). 이 안의 키는 호출자가 이미 **봤으므로**
  /// 첫 저장에 없으면 지운 것이다 — 되살리지 않는다. 정본을 정상으로 읽으면 비운다.
  ///
  /// 🔴 없으면 「지금 저장하는 값」을 기준으로 정본과 견주게 되고, 그러면 `.bak`으로
  /// 시작한 세션에서 지운 곡이 첫 저장마다 되살아난다(파일은 이미 지워져 유령 항목).
  T? _seenAtLoad;

  /// 위 상태가 어느 파일의 것인지. 자리가 바뀌면(테스트의 임시 폴더) 상태를 버린다.
  String? _statePath;

  AtomicJsonFile({
    required Future<File> Function() fileBuilder,
    required String Function(T value) encode,
    required T? Function(String text) decode,
    required bool Function(T value) isEmpty,
    required String label,
    bool keepBackup = true,
    AtomicRescue<T>? rescue,
    Duration ioRetryDelay = kAtomicIoRetryDelay,
  }) : _fileBuilder = fileBuilder,
       _encode = encode,
       _decode = decode,
       _isEmpty = isEmpty,
       _label = label,
       _keepBackup = keepBackup,
       _rescue = rescue,
       _ioRetryDelay = ioRetryDelay;

  /// 마지막 [load]가 값을 어디서 읽었는지.
  AtomicLoadState get lastLoadState => _lastLoadState;

  /// 값을 읽는다. 정본을 못 읽으면 `.bak`에서 되살린다.
  ///
  /// 파일이 없거나(첫 실행) 둘 다 못 읽으면 null이고, 둘은 [lastLoadState]로 가른다.
  /// decode가 던진 예외(읽기 거부)는 그대로 다시 던진다.
  Future<T?> load() async {
    // 줄에 선 쓰기가 있으면 끝난 뒤에 읽는다(rename 순간과 겹치지 않게).
    await _writeChain;
    try {
      final file = await _resolve();
      return await _withPathLock(file.path, () async {
        final main = await _read(file);
        _throwIfRefused(main);
        final mainValue = main.value;
        if (mainValue != null) {
          _lastLoadState = AtomicLoadState.ok;
          // 🔴 정본을 다시 읽는 호출자가 화면만이 아니다 — 백업 내보내기처럼 **읽기만
          // 하고** 화면 목록은 그대로인 길이 있다. 못 열고 시작한 뒤의 첫 읽기가 그런
          // 호출자면, 「정본에만 있던 항목」을 여기서 골라 두어야 화면의 다음 저장(그
          // 항목을 본 적이 없는 목록)이 그것들을 지우지 않는다. _carried도 비우지 않는다
          // (같은 이유). 비용은 유령 항목 하나(다시 읽은 뒤 지운 곡이 한 번 더 되살아남)
          // 뿐이라 그쪽을 택한다 — 반대쪽은 옛 곡 전부의 유실이다.
          if (_mainUnseen) _rememberMainOnly(mainValue);
          _mainUnseen = false;
          _seenAtLoad = null;
          return mainValue;
        }
        // 있는데 깨지지도 않았다 = 열지 못했다. 내용을 본 적이 없다.
        _mainUnseen = main.exists && !main.corrupt;
        final backup = await _read(File('${file.path}.bak'));
        final backupValue = backup.value;
        if (backupValue != null) {
          debugPrint('$_label을(를) 읽지 못해 .bak에서 되살린다.');
          _lastLoadState = AtomicLoadState.recoveredFromBackup;
          _seenAtLoad = backupValue;
          return backupValue;
        }
        // 둘 다 없으면 첫 실행이다. 있는데 못 읽었으면 알린다.
        _lastLoadState = (main.exists || backup.exists)
            ? AtomicLoadState.unreadable
            : AtomicLoadState.ok;
        _seenAtLoad = null;
        return null;
      });
    } on _Refused catch (refused) {
      _lastLoadState = AtomicLoadState.unreadable;
      Error.throwWithStackTrace(refused.error, refused.stack);
    } catch (e, stack) {
      debugPrint('$_label 로드 실패: $e\n$stack');
      _lastLoadState = AtomicLoadState.unreadable;
      _mainUnseen = true;
      _seenAtLoad = null;
      return null;
    }
  }

  /// 값을 저장한다. 디스크에 닿았으면 true.
  ///
  /// 호출 순서대로 한 줄에 서고, 자기 차례에는 **그때의 최신 값**을 쓴다. 그래서
  /// 동시에 불린 저장들이 한 파일에서 섞이지 않는다.
  Future<bool> save(T value) {
    _pending = value;
    _hasPending = true;
    final step = _writeChain.then((_) async {
      // 앞 차례가 내 값까지 이미 썼다 — 그 결과가 곧 내 결과다.
      if (!_hasPending) return _lastWriteOk;
      final latest = _pending as T;
      _pending = null;
      _hasPending = false;
      final ok = await _writeAtomically(latest);
      // 실패했으면 다음 차례가 다시 해 보도록 되돌려 둔다(더 새 값이 있으면 그쪽).
      if (!ok && !_hasPending) {
        _pending = latest;
        _hasPending = true;
      }
      return _lastWriteOk = ok;
    });
    _writeChain = step;
    return step;
  }

  /// 경로 잠금 안에서 **읽고-바꾸고-쓴다.** 쓴 값을 돌려주고, 못 썼으면 null.
  ///
  /// 같은 파일을 쓰는 인스턴스가 여럿일 때 쓴다. 각자 메모리에 든 목록을 통째로
  /// 저장하면 서로의 추가분을 덮는다 — 쓰는 순간의 디스크 값에서 출발해야 한다.
  /// [change]가 받는 값은 정본(못 읽었으면 `.bak`, 그것도 없으면 null)이다.
  /// 받은 객체를 **그대로** 돌려주면 바뀐 게 없다는 뜻이라 파일을 다시 쓰지 않는다.
  /// 한 인스턴스에서 [save]와 섞어 쓰지 않는다(줄에 선 옛 값이 뒤에 덮는다).
  Future<T?> update(T Function(T? current) change) {
    T? written;
    final step = _writeChain.then((_) async {
      try {
        final file = await _resolve();
        return await _withPathLock(file.path, () async {
          final current = await _read(file);
          if (!_mayReplace(current)) return false;
          // 깨졌거나 없는 정본이면 직전 백업에서 이어 간다.
          final base =
              current.value ?? (await _read(File('${file.path}.bak'))).value;
          final next = change(base);
          // 정본에서 출발해 같은 객체를 돌려줬으면 바뀐 게 없다 — 다시 쓰지 않는다.
          if (current.value != null && identical(next, current.value)) {
            written = next;
            return true;
          }
          final ok = await _commit(file, current, next);
          if (ok) written = next;
          return ok;
        });
      } catch (e, stack) {
        debugPrint('$_label 갱신 실패: $e\n$stack');
        return false;
      }
    });
    _writeChain = step;
    return step.then((_) => written);
  }

  /// 파일 자리를 구한다. 자리가 바뀌었으면 옛 자리의 상태를 버린다.
  Future<File> _resolve() async {
    final file = await _fileBuilder();
    final key = _lockKey(file.path);
    if (_statePath != null && _statePath != key) {
      _mainUnseen = false;
      _carried = null;
      _seenAtLoad = null;
      _lastLoadState = AtomicLoadState.ok;
    }
    _statePath = key;
    return file;
  }

  /// 파일 하나를 값으로 읽는다. 네 가지를 가른다:
  /// 없음(exists=false) / 내용이 깨짐(corrupt) / 지금 열 수 없음 / 읽기 거부(refusal).
  ///
  /// 열기 거절은 조건 루프로 다시 해 본 뒤에야 포기한다. 포기해도 「깨짐」은 아니다 —
  /// 내용을 본 적이 없으므로 옆으로 치우거나 백업을 갈지 않는다.
  Future<_ReadResult<T>> _read(File file) async {
    for (var attempt = 1; ; attempt++) {
      try {
        if (!await file.exists()) {
          return (
            exists: false,
            corrupt: false,
            value: null,
            refusal: null,
            refusalStack: null,
          );
        }
        // 깨진 UTF-8에서 예외가 나지 않게 바이트로 읽어 너그럽게 푼다 —
        // 그러면 남는 파일 예외는 전부 「못 엶」이다.
        final text = utf8.decode(
          await file.readAsBytes(),
          allowMalformed: true,
        );
        try {
          final value = _decode(text);
          return (
            exists: true,
            corrupt: value == null,
            value: value,
            refusal: null,
            refusalStack: null,
          );
        } catch (e, stack) {
          return (
            exists: true,
            corrupt: false,
            value: null,
            refusal: e,
            refusalStack: stack,
          );
        }
      } on FileSystemException catch (e) {
        if (attempt >= kAtomicIoAttempts) {
          debugPrint('${file.path} 열기 실패: $e');
          return (
            exists: true,
            corrupt: false,
            value: null,
            refusal: null,
            refusalStack: null,
          );
        }
        await Future<void>.delayed(_ioRetryDelay);
      }
    }
  }

  /// 읽기 거부였으면 load()가 되던질 수 있게 감싸 던진다.
  void _throwIfRefused(_ReadResult<T> result) {
    final refusal = result.refusal;
    if (refusal != null) {
      throw _Refused(refusal, result.refusalStack ?? StackTrace.current);
    }
  }

  /// 이 정본을 바꿔 써도 되는가. 읽기를 거부당했거나 지금 못 여는 정본은 안 된다.
  ///
  /// 🔴 「지금 못 연」 정본은 값이 있어도 덮지 않는다. 깨진 파일은 옆에 사본을 남기고
  /// 덮지만, 못 연 파일은 사본도 백업도 뜰 수 없다 — 읽기만 막힌 파일(오프라인
  /// OneDrive 자리표시자 등)이 흔적 없이 교체된다. 저장은 실패로 올린다.
  bool _mayReplace(_ReadResult<T> current) {
    if (current.refusal != null) {
      debugPrint('$_label은(는) 이 버전이 읽을 수 없는 파일이라 덮지 않는다.');
      return false;
    }
    if (current.exists && current.value == null && !current.corrupt) {
      debugPrint('$_label을(를) 지금 열 수 없어 덮지 않는다.');
      return false;
    }
    return true;
  }

  /// 자기 차례의 값을 디스크에 쓴다. 성공하면 true.
  Future<bool> _writeAtomically(T value) async {
    try {
      final file = await _resolve();
      return await _withPathLock(file.path, () async {
        final current = await _read(file);
        if (!_mayReplace(current)) return false;
        return _commit(file, current, _withCarried(current, value));
      });
    } catch (e, stack) {
      debugPrint('$_label 저장 실패: $e\n$stack');
      return false;
    }
  }

  /// 못 열고 시작했던 정본을 이제 읽었으면, 거기에만 있던 항목을 골라 함께 싣는다.
  ///
  /// 견주는 기준은 「지금 저장하는 값」이 아니라 **부팅 때 호출자가 본 값**(`.bak`)이다.
  /// `.bak`에 있던 항목을 호출자가 지웠으면 그건 지운 것이지 못 본 것이 아니다 — 정본에만
  /// 있던(`.bak`보다 새로 생긴) 항목만 살린다. `.bak` 없이 null로 시작했으면 본 것이
  /// 없으니 지금 값을 기준으로 한다(예전과 같다).
  T _withCarried(_ReadResult<T> current, T value) {
    final rescue = _rescue;
    if (rescue == null) return value;
    if (_mainUnseen) {
      // 여기까지 왔으면 정본은 없거나·깨졌거나·읽혔다. 읽힌 경우만 살릴 것이 있다.
      _mainUnseen = false;
      final disk = current.value;
      if (disk != null) _rememberMainOnly(disk, mine: value);
      _seenAtLoad = null;
    }
    final carried = _carried;
    return carried == null ? value : rescue.join(carried, value);
  }

  /// 못 열고 시작한 뒤 처음 읽힌 정본 [disk]에서, 호출자가 못 본 항목을 [_carried]에 둔다.
  ///
  /// 기준은 부팅 때 호출자가 본 값(`.bak`)이고, 그것도 없으면 [mine](지금 저장하는 값),
  /// 그것마저 없으면(읽기만 하는 호출자의 load) 정본 전부다 — join이 같은 키를
  /// 메모리 쪽으로 가르므로 호출자가 이미 가진 항목은 두 번 실리지 않는다.
  void _rememberMainOnly(T disk, {T? mine}) {
    final rescue = _rescue;
    if (rescue == null) return;
    final seen = _seenAtLoad ?? mine;
    final missing = seen == null ? disk : rescue.onlyInDisk(disk, seen);
    if (_isEmpty(missing)) return;
    debugPrint('$_label: 못 열고 시작한 정본에만 있던 항목을 함께 싣는다.');
    _carried = missing;
  }

  /// `.tmp` → flush → (직전 정본을 `.bak`으로) → rename. 성공하면 true.
  Future<bool> _commit(File file, _ReadResult<T> current, T value) async {
    File? tmp;
    try {
      // 🔴 못 읽은 정본을 빈 값으로 덮지 않는다. 손으로 되살릴 마지막 단서다.
      if (current.exists && current.value == null && _isEmpty(value)) {
        debugPrint('$_label을(를) 읽지 못한 상태라 빈 값으로 덮지 않는다.');
        return false;
      }

      final bytes = utf8.encode(_encode(value));
      tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      if (await tmp.length() != bytes.length) {
        throw FileSystemException('임시 파일 크기가 맞지 않는다', tmp.path);
      }

      if (current.corrupt) {
        // 깨진 정본은 옆에 남긴다. 못 남기면 덮지도 않는다(예외 → false).
        await file.copy('${file.path}.corrupt-${_stamp(DateTime.now())}');
      } else if (current.value != null && _keepBackup) {
        // 읽히는 정본만 백업으로 보낸다. 못 연 정본은 백업도 복사도 하지 않는다 —
        // 멀쩡한 .bak을 내용 모를 파일로 덮을 수 없다.
        await _backupQuietly(file);
      }

      await _replaceFile(tmp, file.path, _ioRetryDelay);
      return true;
    } catch (e, stack) {
      debugPrint('$_label 저장 실패: $e\n$stack');
      await _deleteQuietly(tmp);
      return false;
    }
  }

  /// 읽히는 직전 정본을 `.bak`에 둔다. 실패해도 저장은 계속한다 —
  /// 백업을 못 떴다고 새 값을 버리는 쪽이 더 큰 손해다.
  Future<void> _backupQuietly(File file) async {
    try {
      await file.copy('${file.path}.bak');
    } catch (e) {
      debugPrint('$_label 백업 실패: $e');
    }
  }

  /// 파일 이름에 쓸 시각 도장(yyyyMMdd_HHmmss).
  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }
}

/// 텍스트 파일 하나를 원자적으로 쓴다(`.tmp` → flush → rename). 성공하면 true.
///
/// 싱크 가사(.lrc)·가사 txt용이다. **백업은 돌리지 않는다** — `.lrc.bak`은 이미
/// 「재타이밍 전 원본」이라는 다른 뜻으로 쓰이고 있어, 여기서 덮으면 G 복구가 엉뚱한
/// 판본을 되살린다.
Future<bool> writeTextAtomically(
  File target,
  String text, {
  Duration ioRetryDelay = kAtomicIoRetryDelay,
}) {
  return _withPathLock(target.path, () async {
    File? tmp;
    try {
      final bytes = utf8.encode(text);
      tmp = File('${target.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      if (await tmp.length() != bytes.length) {
        throw FileSystemException('임시 파일 크기가 맞지 않는다', tmp.path);
      }
      await _replaceFile(tmp, target.path, ioRetryDelay);
      return true;
    } catch (e, stack) {
      debugPrint('${target.path} 저장 실패: $e\n$stack');
      await _deleteQuietly(tmp);
      return false;
    }
  });
}

/// 같은 파일을 쓰는 모든 인스턴스가 공유하는 잠금. 끝나면 항목을 지운다.
final Map<String, Future<void>> _pathLocks = {};

/// 잠금 키. 같은 파일을 가리키는 다른 표기(역슬래시·대소문자)를 하나로 모은다.
/// (path 패키지가 직접 의존성이 아니라 손으로 정규화한다.)
String _lockKey(String path) =>
    File(path).absolute.path.replaceAll('\\', '/').toLowerCase();

/// 같은 경로의 임계 구역을 한 줄로 세운다. 앞의 것이 끝나야 [body]가 돈다.
Future<R> _withPathLock<R>(String path, Future<R> Function() body) async {
  final key = _lockKey(path);
  final previous = _pathLocks[key];
  final done = Completer<void>();
  _pathLocks[key] = done.future;
  try {
    // 앞 차례는 complete()로만 끝나므로 여기서 예외가 넘어오지 않는다.
    if (previous != null) await previous;
    return await body();
  } finally {
    done.complete();
    // 내가 줄의 끝이면 항목을 지운다(테스트 사이에 상태가 남지 않게).
    if (identical(_pathLocks[key], done.future)) {
      _pathLocks.remove(key);
    }
  }
}

/// 임시 파일을 정본 자리로 옮긴다. 거절되면 조건 루프로 잠깐 다시 해 본다.
Future<void> _replaceFile(File tmp, String targetPath, Duration delay) async {
  for (var attempt = 1; ; attempt++) {
    try {
      await tmp.rename(targetPath);
      return;
    } on FileSystemException {
      if (attempt >= kAtomicIoAttempts) rethrow;
      await Future<void>.delayed(delay);
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
