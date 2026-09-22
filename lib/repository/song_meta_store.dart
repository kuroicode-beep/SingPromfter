// file: lib/repository/song_meta_store.dart
//
// 곡 메타데이터를 data/songs.json에 저장하고 가사 파일을 함께 로드한다.
//
// 🔴 v5.17.0: 쓰기는 공용 헬퍼(atomic_json_file.dart)로 한다 — 한 줄로 세워서,
// `.tmp`→rename으로, 직전 정본은 `.bak`에 남긴다. 예전에는 정본을 곧바로 덮어썼고
// (사슬 밖 직접 저장이 8곳), 깨진 파일·빈 파일·**가사 txt 하나의 디코드 예외**까지
// 전부 빈 목록으로 읽었다. 그 상태의 첫 저장이 곡 목록 전체를 지운다.
//   · 「못 읽음」은 빈 목록이 아니다 — `.bak`에서 되살리고, 빈 목록으로는 덮지 않는다.
//   · 가사 txt는 곡 단위로 따로 읽는다. 하나가 안 읽혀도 목록은 살아 있다.
//   · 상위 버전 파일은 「깨진 것」이 아니다 — 예외로 올려 저장을 통째로 막는다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';
import '../services/atomic_json_file.dart';

/// songs.json 스키마 버전을 다루다 생긴 문제를 호출자에게 알린다.
class SongMetaSchemaException implements Exception {
  final String message;

  const SongMetaSchemaException(this.message);

  @override
  String toString() => message;
}

class SongMetaStore {
  /// 이 빌드가 읽고 쓸 수 있는 songs.json 스키마 버전.
  ///
  /// v1: 최상위가 곡 배열 (버전 필드 없음)
  /// v2: `{"schemaVersion": 2, "songs": [...]}` 봉투
  static const int schemaVersion = 2;

  /// 데이터 폴더의 뿌리(기본: 문서 폴더). 테스트는 임시 폴더를 준다.
  final Future<Directory> Function() _baseDirBuilder;

  /// songs.json의 읽기·쓰기 규칙. 값은 곡 메타 항목(JSON 맵)의 목록이다 —
  /// 가사는 txt에서 따로 읽으므로(비동기) 여기서는 Song으로 풀지 않는다.
  late final AtomicJsonFile<List<Map<String, dynamic>>> _file;

  SongMetaStore({
    Future<Directory> Function()? baseDirBuilder,
    Duration ioRetryDelay = kAtomicIoRetryDelay,
  }) : _baseDirBuilder = baseDirBuilder ?? getApplicationDocumentsDirectory {
    _file = AtomicJsonFile<List<Map<String, dynamic>>>(
      fileBuilder: () => _songsFile,
      encode: encodeEntries,
      decode: tryDecodeEntries,
      isEmpty: (entries) => entries.isEmpty,
      label: 'songs.json',
      // 못 열고 시작한 목록으로 저장해도 정본에만 있던 곡이 사라지지 않게 한다.
      // (id는 글자로 바꿔 견준다 — 손으로 고친 파일의 id가 문자열이 아닐 수도 있다.)
      rescue: AtomicRescue.listById<Map<String, dynamic>>(
        (entry) => '${entry['id'] ?? ''}',
      ),
      ioRetryDelay: ioRetryDelay,
    );
  }

  /// 마지막 [load]에서 Song으로 풀지 못한 항목(원문). 저장 때 그대로 다시 싣는다.
  List<Map<String, dynamic>> _unparsed = const [];

  /// 마지막 [load]에 Song으로 못 푼 항목이 있었는가 — 정본에는 있지만 목록에는 없는
  /// 곡이다. 그 곡의 반주·가사 파일은 목록 기준 고아 점검에서 「사용하지 않는 파일」로
  /// 보이므로, 정리를 막는 근거가 된다.
  bool get hasUnparsedEntries => _unparsed.isNotEmpty;

  /// 마지막 [load]가 목록을 어디서 읽었는지(정본·백업·읽지 못함).
  AtomicLoadState get lastLoadState => _file.lastLoadState;

  Future<Directory> get _dataDir async {
    final base = await _baseDirBuilder();
    final dir = Directory('${base.path}/data');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> get _lyricsDir async {
    final dir = Directory('${(await _dataDir).path}/txt');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> get _songsFile async =>
      File('${(await _dataDir).path}/songs.json');

  /// 곡 목록 파일이 있는가. 정본이 사라졌어도 `.bak`이 있으면 있는 것으로 본다 —
  /// 없다고 답하면 호출자가 옛 저장소(SharedPreferences) 이관 경로로 빠진다.
  Future<bool> exists() async {
    try {
      final file = await _songsFile;
      return await file.exists() || await File('${file.path}.bak').exists();
    } catch (e) {
      // 모르면 있다고 본다 — load()가 「못 읽음」으로 가르고, 그래야 저장이 정본을 지킨다.
      debugPrint('songs.json 확인 실패: $e');
      return true;
    }
  }

  /// 곡 목록을 읽는다. 정본을 못 읽으면 `.bak`에서 되살린다.
  ///
  /// 둘 다 못 읽으면 []를 주지만 [lastLoadState]가 unreadable로 선다. 상위 버전
  /// 파일은 [SongMetaSchemaException]으로 올린다(호출자가 저장을 막는다).
  Future<List<Song>> load() async {
    final entries = await _file.load();
    if (entries == null) return [];

    final songs = <Song>[];
    final unparsed = <Map<String, dynamic>>[];
    for (final json in entries) {
      try {
        final lyricsText = await _readLyricsForMeta(json);
        songs.add(Song.fromMetaJson(json, lyricsText: lyricsText));
      } catch (e, stack) {
        // 항목 하나가 이상하다고 목록 전체를 버리지 않는다. 못 푼 항목은 원문 그대로
        // 들고 있다가 저장 때 다시 싣는다 — 조용히 빠뜨리면 다음 저장이 지운다.
        debugPrint('songs.json 항목 해석 실패(${json['id']}): $e\n$stack');
        unparsed.add(json);
      }
    }
    _unparsed = unparsed;
    return songs;
  }

  /// v1(맨 배열)과 v2(봉투)를 모두 읽는다. 상위 버전은 거부한다.
  @visibleForTesting
  static List<Map<String, dynamic>> decodeEntries(String raw) {
    return _entriesOf(jsonDecode(raw)) ?? const [];
  }

  /// 파일 본문을 곡 항목 목록으로 푼다. 못 읽으면 null. (순수 함수)
  ///
  /// 🔴 「못 읽음(null)」과 「빈 목록([])」을 반드시 가른다. 빈 문자열·잘린 JSON·
  /// 엉뚱한 모양은 전부 null이다 — 빈 목록으로 읽으면 다음 저장이 곡 목록 전체를
  /// 지운다. 상위 버전만은 null이 아니라 예외다(깨진 게 아니라 이 앱이 못 읽는 것).
  static List<Map<String, dynamic>>? tryDecodeEntries(String raw) {
    // 밖에서 손본 파일(파이썬 utf-8-sig 등)에는 BOM이 붙어 올 수 있다.
    final text = stripBom(raw);
    if (text.trim().isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      debugPrint('songs.json 해석 실패: $e');
      return null;
    }
    return _entriesOf(decoded);
  }

  /// 곡 항목 목록을 songs.json 본문(v2 봉투)으로 만든다. (순수 함수)
  static String encodeEntries(List<Map<String, dynamic>> entries) {
    return const JsonEncoder.withIndent(
      '  ',
    ).convert({'schemaVersion': schemaVersion, 'songs': entries});
  }

  /// 풀린 JSON에서 곡 항목을 꺼낸다. 모양이 맞지 않으면 null, 상위 버전은 예외.
  static List<Map<String, dynamic>>? _entriesOf(Object? decoded) {
    if (decoded is List) {
      // v1 레거시 — 다음 저장 때 v2 봉투로 승격된다.
      return _castEntries(decoded);
    }

    if (decoded is Map<String, dynamic>) {
      final map = decoded.cast<String, dynamic>();
      final version = (map['schemaVersion'] as num?)?.toInt() ?? schemaVersion;
      if (version > schemaVersion) {
        throw SongMetaSchemaException(
          '곡 데이터 버전이 $version이라 이 앱 버전(최대 $schemaVersion)에서는 열 수 없습니다. '
          '앱을 최신 버전으로 업데이트해 주세요.',
        );
      }
      final songs = map['songs'];
      if (songs is List) {
        return _castEntries(songs);
      }
    }

    return null;
  }

  static List<Map<String, dynamic>> _castEntries(List<dynamic> raw) {
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  /// 곡 목록을 저장한다. 디스크에 닿았으면 true.
  ///
  /// 호출 순서대로 한 줄에 서고, 자기 차례에는 **그때의 최신 목록**을 쓴다 —
  /// 즐겨찾기 토글·가져오기 완료·동기화가 겹쳐도 한 파일에서 섞이지 않는다.
  Future<bool> save(List<Song> songs) {
    final ids = {for (final song in songs) song.id};
    return _file.save([
      for (final song in songs) song.toMetaJson(),
      for (final raw in _unparsed)
        if (!ids.contains(raw['id'])) raw,
    ]);
  }

  /// 곡의 가사 txt를 읽는다. 없거나 못 읽으면 빈 문자열.
  Future<String> _readLyricsForMeta(Map<String, dynamic> json) async {
    final id = json['id'] as String? ?? '';
    final path = json['lyricsPath'] as String? ?? '';
    final candidates = <File>[
      if (path.isNotEmpty) File(path),
      if (id.isNotEmpty) File('${(await _lyricsDir).path}/$id.txt'),
    ];

    for (final file in candidates) {
      try {
        if (await file.exists()) {
          return decodeLyricsBytes(await file.readAsBytes()).trim();
        }
      } on FileSystemException catch (e) {
        // 🔴 가사 파일 하나가 안 열린다고 곡 목록 전체를 빈 목록으로 만들지 않는다.
        debugPrint('가사 파일 읽기 실패(${file.path}): $e');
      }
    }
    return '';
  }

  /// 가사 파일의 바이트를 글자로 푼다. (순수 함수)
  ///
  /// 가사 txt는 사용자가 직접 여는 파일이라 메모장의 「ANSI」 저장본(이 PC는 cp949)이
  /// 섞일 수 있다. 예전에는 그 파일 하나의 디코드 예외가 곡 목록 전체를 []로 만들었다.
  ///
  /// 🔴 UTF-8이 한 바이트만 깨져도(예전 부분 쓰기로 끝이 잘린 한글) 통째로 cp949로 풀면
  /// 본문 전체가 「뷁」 계열로 깨진다(줄바꿈까지, 실측). 그래서 먼저 너그럽게 UTF-8로
  /// 풀어 보고, 깨진 자리(U+FFFD)가 온전한 비ASCII 글자보다 **적으면** UTF-8로 본다 —
  /// cp949 저장본은 음절마다 U+FFFD가 나와 반대쪽으로 갈린다(실측 67:8 / 잘린 UTF-8 1:43).
  /// 시스템 코드페이지도 안 되면 깨진 글자를 감수하고 푼다.
  @visibleForTesting
  static String decodeLyricsBytes(List<int> bytes) {
    try {
      return stripBom(utf8.decode(bytes));
    } on FormatException {
      final loose = stripBom(utf8.decode(bytes, allowMalformed: true));
      final bad = '�'.allMatches(loose).length;
      final good = loose.runes.where((r) => r > 0x7F && r != 0xFFFD).length;
      if (bad <= good) return loose;
      try {
        return systemEncoding.decode(bytes);
      } catch (_) {
        return loose;
      }
    }
  }
}
