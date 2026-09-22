// file: lib/repository/practice_log_store.dart
//
// 연습 세션 로그를 data/practice_log.json에 저장한다.
// songs.json과 분리하는 이유: 즐겨찾기 토글마다 재작성되는 핫 파일에
// 무한히 늘어나는 로그를 섞지 않고, 곡이 삭제돼도 기록은 남기기 위해서다.
//
// 🔴 v5.17.0: 쓰기는 **합치기(merge) 한 길뿐**이다.
//
// 이 파일은 쓰는 쪽이 셋이다 — 화면의 연습 기록 서비스, 백업 가져오기, 폰 동기화.
// 예전에는 각자 메모리에 든 목록을 통째로 저장했다. 화면은 부팅 때 한 번 읽은 목록을
// 계속 들고 있으므로, 폰이 올린 세션이나 백업에서 합친 세션을 **다음 연습 기록이
// 통째로 덮었다**(논리적 유실). 두 쓰기가 한 파일에서 섞이면 JSON도 깨졌고, 깨진
// 파일은 빈 목록으로 읽혀 그 다음 저장이 전체를 지웠다.
//   · 쓰는 순간의 디스크 목록에서 출발해 id로 합친다(경로 잠금 안에서 읽고-쓰기).
//   · 원자 교체·`.bak`·못 읽은 정본 보호는 공용 헬퍼(atomic_json_file.dart)가 맡는다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/practice_session.dart';
import '../services/atomic_json_file.dart';

/// [base]에 [incoming]을 id로 합친다. (순수 함수)
///
/// 모르는 id는 뒤에 붙인다. 아는 id는 [incomingWins]일 때만 그 자리에서 갈아끼운다 —
/// 화면의 「직전 세션에 이어 붙이기」(durationMs 증가)는 메모리 쪽이 이겨야 하고,
/// 백업·폰에서 온 같은 id는 이미 있는 것을 건드리지 않는다. id가 빈 세션은 버린다.
/// 바뀐 게 없으면 [base] **그 객체**를 돌려준다(저장소가 다시 쓰지 않는다).
List<PracticeSession> mergePracticeSessions(
  List<PracticeSession> base,
  List<PracticeSession> incoming, {
  bool incomingWins = false,
}) {
  final indexById = <String, int>{
    for (var i = 0; i < base.length; i++) base[i].id: i,
  };
  List<PracticeSession>? merged;
  for (final session in incoming) {
    if (session.id.isEmpty) continue;
    final index = indexById[session.id];
    if (index == null) {
      merged ??= List<PracticeSession>.of(base);
      indexById[session.id] = merged.length;
      merged.add(session);
    } else if (incomingWins && !identical((merged ?? base)[index], session)) {
      merged ??= List<PracticeSession>.of(base);
      merged[index] = session;
    }
  }
  return merged ?? base;
}

/// practice_log.json 본문을 만든다. (순수 함수)
String encodePracticeLog(List<PracticeSession> sessions) {
  return const JsonEncoder.withIndent('  ').convert({
    'schemaVersion': PracticeLogStore.schemaVersion,
    'sessions': sessions.map((s) => s.toJson()).toList(),
  });
}

/// practice_log.json 본문을 세션 목록으로 푼다. 못 읽으면 null. (순수 함수)
///
/// 🔴 「못 읽음(null)」과 「빈 목록([])」을 가른다. 빈 파일·잘린 JSON을 빈 목록으로
/// 읽으면 다음 저장이 기록 전체를 지운다. 상위 버전은 null이 아니라
/// [AtomicSchemaException]이다 — null이면 헬퍼가 「깨진 파일」로 보고 첫 저장에서
/// `.corrupt-`로 옮긴 뒤 구버전 봉투로 갈아 끼운다(더 새 빌드의 기록이 정본에서 빠진다).
List<PracticeSession>? decodePracticeLog(String raw) {
  final text = stripBom(raw);
  if (text.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) return null;
    _refuseNewerSchema(decoded);
    final sessions = decoded['sessions'];
    if (sessions is! List) return null;
    return sessions
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => PracticeSession.fromJson(e.cast<String, dynamic>()))
        .toList();
  } on AtomicSchemaException {
    rethrow;
  } catch (e) {
    debugPrint('practice_log.json 해석 실패: $e');
    return null;
  }
}

/// 이 빌드보다 높은 schemaVersion이면 읽기를 거부한다(예외).
void _refuseNewerSchema(Map<String, dynamic> decoded) {
  final version = (decoded['schemaVersion'] as num?)?.toInt() ?? 1;
  if (version > PracticeLogStore.schemaVersion) {
    throw AtomicSchemaException(
      'practice_log.json 버전($version)이 이 앱 버전(최대 '
      '${PracticeLogStore.schemaVersion})보다 높아 읽지 않습니다. 앱을 업데이트해 주세요.',
    );
  }
}

class PracticeLogStore {
  /// 처음부터 봉투 형식으로 저장한다(맨 배열 실수 반복 금지).
  static const int schemaVersion = 1;

  /// 데이터 폴더의 뿌리(기본: 문서 폴더). 테스트는 임시 폴더를 준다.
  final Future<Directory> Function() _baseDirBuilder;

  late final AtomicJsonFile<List<PracticeSession>> _file;

  PracticeLogStore({
    Future<Directory> Function()? baseDirBuilder,
    Duration ioRetryDelay = kAtomicIoRetryDelay,
  }) : _baseDirBuilder = baseDirBuilder ?? getApplicationDocumentsDirectory {
    _file = AtomicJsonFile<List<PracticeSession>>(
      fileBuilder: () => _logFile,
      encode: encodePracticeLog,
      decode: decodePracticeLog,
      isEmpty: (sessions) => sessions.isEmpty,
      label: 'practice_log.json',
      ioRetryDelay: ioRetryDelay,
    );
  }

  /// 마지막 [load]가 기록을 어디서 읽었는지(정본·백업·읽지 못함).
  AtomicLoadState get lastLoadState => _file.lastLoadState;

  Future<File> get _logFile async {
    final base = await _baseDirBuilder();
    final dir = Directory('${base.path}/data');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/practice_log.json');
  }

  /// 기록을 읽는다. 정본을 못 읽으면 `.bak`에서 되살리고, 둘 다 안 되면 [].
  ///
  /// 상위 버전 파일은 빈 목록이지만 [lastLoadState]가 unreadable로 서고, 헬퍼가
  /// 그 정본을 어떤 저장으로도 덮지 않는다(merge는 null을 돌려준다).
  Future<List<PracticeSession>> load() async {
    try {
      return await _file.load() ?? [];
    } on AtomicSchemaException catch (e) {
      debugPrint('$e');
      return [];
    }
  }

  /// [incoming]을 **지금 디스크의 기록**에 id로 합쳐 쓴다. 합친 목록을 돌려주고,
  /// 못 썼으면 null(정본을 지금 열 수 없을 때 등 — 호출자가 다음에 다시 싣는다).
  Future<List<PracticeSession>?> merge(
    List<PracticeSession> incoming, {
    bool incomingWins = false,
  }) async {
    // 합칠 게 없으면 파일을 건드리지 않는다(없는 파일을 빈 봉투로 만들지도 않는다).
    if (incoming.every((session) => session.id.isEmpty)) return load();
    return _file.update(
      (disk) => mergePracticeSessions(
        disk ?? const [],
        incoming,
        incomingWins: incomingWins,
      ),
    );
  }
}
