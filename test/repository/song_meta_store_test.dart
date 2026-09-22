// file: test/repository/song_meta_store_test.dart
//
// 곡 목록(songs.json) 저장의 데이터 안전 — 직렬 쓰기·원자 교체·백업 폴백.
//
// 만든 계기: songs.json은 피해 범위가 가장 큰 파일인데(곡·반주·가사 오프셋·조성·
// 즐겨찾기·폴더), 정본을 곧바로 덮어썼고 저장 사슬 밖에서 직접 쓰는 곳이 8곳이었다.
// 깨진 파일·빈 파일은 물론 **가사 txt 하나의 디코드 예외**까지 빈 목록으로 읽혀,
// 그 다음 저장이 곡 목록 전체를 지울 수 있었다. 그 길을 하나씩 막아 둔다.
//
// 실제 파일 IO를 기다리므로 전부 plain test()다(testWidgets의 가짜 시계 금지).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/repository/song_meta_store.dart';
import 'package:singpromfter_app/repository/song_repository.dart';
import 'package:singpromfter_app/services/atomic_json_file.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sp_song_meta_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  SongMetaStore newStore() => SongMetaStore(
    baseDirBuilder: () async => tmp,
    ioRetryDelay: const Duration(milliseconds: 1),
  );

  File songsFile() => File('${tmp.path}/data/songs.json');
  File backupFile() => File('${songsFile().path}.bak');

  Song song(int i, {String title = '', bool favorite = false}) => Song(
    id: 's$i',
    title: title.isEmpty ? '곡 $i' : title,
    artist: '가수',
    lyricsPath: '${tmp.path}/data/txt/s$i.txt',
    lyricsText: '',
    backingTracks: const [],
    createdAt: DateTime(2026, 9, 1, 10, 0, i),
    updatedAt: DateTime(2026, 9, 1, 10, 0, i),
    isFavorite: favorite,
  );

  /// 디스크의 정본을 직접 읽어 곡 id 목록으로 돌려준다(JSON이 깨졌으면 여기서 실패).
  Future<List<String>> idsOnDisk() async {
    final decoded =
        jsonDecode(await songsFile().readAsString()) as Map<String, dynamic>;
    return [
      for (final s in decoded['songs'] as List)
        (s as Map<String, dynamic>)['id'] as String,
    ];
  }

  /// 데이터 폴더에 남은 파일 이름들.
  Future<List<String>> dataFiles() async => [
    await for (final e in Directory('${tmp.path}/data').list())
      if (e is File) e.uri.pathSegments.last,
  ]..sort();

  Future<void> seed(String body) async {
    await Directory('${tmp.path}/data').create(recursive: true);
    await songsFile().writeAsString(body);
  }

  Future<void> writeLyrics(int i, List<int> bytes) async {
    final dir = Directory('${tmp.path}/data/txt');
    await dir.create(recursive: true);
    await File('${dir.path}/s$i.txt').writeAsBytes(bytes);
  }

  group('tryDecodeEntries — 「못 읽음」과 「빈 목록」을 가른다', () {
    test('v2 봉투·v1 맨 배열은 목록으로, 빈 songs는 빈 목록([])으로', () {
      final body = SongMetaStore.encodeEntries([song(1).toMetaJson()]);
      expect(SongMetaStore.tryDecodeEntries(body)!.single['id'], 's1');
      expect(SongMetaStore.tryDecodeEntries('[{"id":"a"}]')!.single['id'], 'a');
      expect(
        SongMetaStore.tryDecodeEntries(SongMetaStore.encodeEntries(const [])),
        isEmpty,
      );
    });

    test('빈 파일·잘린 JSON·엉뚱한 모양은 빈 목록이 아니라 null', () {
      final body = SongMetaStore.encodeEntries([song(1).toMetaJson()]);
      expect(SongMetaStore.tryDecodeEntries(''), isNull);
      expect(SongMetaStore.tryDecodeEntries('  \n'), isNull);
      expect(
        SongMetaStore.tryDecodeEntries(body.substring(0, body.length ~/ 2)),
        isNull,
      );
      expect(SongMetaStore.tryDecodeEntries('{"schemaVersion":2}'), isNull);
      expect(SongMetaStore.tryDecodeEntries('"문자열"'), isNull);
      expect(
        SongMetaStore.tryDecodeEntries('{"schemaVersion":2,"songs":"x"}'),
        isNull,
      );
    });

    test('상위 버전은 null이 아니라 예외다(덮어쓰기 방지의 근거)', () {
      expect(
        () => SongMetaStore.tryDecodeEntries('{"schemaVersion":99,"songs":[]}'),
        throwsA(isA<SongMetaSchemaException>()),
      );
    });

    test('파일 형식은 그대로다 — v2 봉투, 들여쓰기 2칸', () {
      final body = SongMetaStore.encodeEntries([song(1).toMetaJson()]);
      expect(body, startsWith('{\n  "schemaVersion": 2,\n  "songs": [\n'));
    });
  });

  group('save — 원자 교체와 겹친 쓰기', () {
    test('저장하면 읽히는 JSON이 남고, 두 번째부터 직전 정본이 .bak에 남는다', () async {
      final store = newStore();
      expect(await store.save([song(1)]), isTrue);
      expect(await dataFiles(), ['songs.json']);

      expect(await store.save([song(1), song(2)]), isTrue);
      expect(await idsOnDisk(), ['s1', 's2']);
      expect(
        SongMetaStore.tryDecodeEntries(
          await backupFile().readAsString(),
        )!.map((e) => e['id']),
        ['s1'],
      );
      expect(await dataFiles(), ['songs.json', 'songs.json.bak']);
    });

    test('기다리지 않고 50번 겹쳐 저장해도 마지막 목록이 온전히 남는다', () async {
      // 실제 모양: 즐겨찾기 토글·가져오기 완료·싱크 미세조정이 저장 사슬 밖에서도
      // 제각기 saveSongs를 부른다. 하나도 기다리지 않고 겹쳐 부른다.
      final store = newStore();
      final results = <Future<bool>>[];
      for (var n = 1; n <= 50; n++) {
        results.add(
          store.save([for (var i = 0; i < n; i++) song(i, favorite: n.isEven)]),
        );
      }
      expect(await Future.wait(results), everyElement(isTrue));

      expect((await idsOnDisk()).length, 50);
      expect((await dataFiles()).where((f) => f.endsWith('.tmp')), isEmpty);

      // 새로 켠 앱이 같은 목록을 본다.
      final reopened = newStore();
      final loaded = await reopened.load();
      expect(reopened.lastLoadState, AtomicLoadState.ok);
      expect(loaded.length, 50);
      expect(loaded.every((s) => s.isFavorite), isTrue, reason: '마지막(50번째) 저장');
    });

    test('쓰는 도중에도 정본은 언제나 읽히는 JSON이다', () async {
      final store = newStore();
      final results = <Future<bool>>[];
      for (var n = 1; n <= 25; n++) {
        results.add(store.save([for (var i = 0; i < n; i++) song(i)]));
        await Future<void>.delayed(Duration.zero);
        String? raw;
        try {
          // 🔴 동기로 읽는다. Windows는 다른 핸들이 정본을 쥔 동안 .tmp→정본 rename을
          // 거절한다(errno 5). 비동기 읽기는 열기·읽기·닫기가 IO 스레드를 오가는
          // 사이 핸들을 잡고 있어서, 전체 스위트가 병렬로 돌 때 이 테스트의
          // 8×1ms 재시도 예산보다 오래 쥘 수 있다(실측: 두 번째 저장이 false).
          // 동기 읽기는 μs 단위라 그 창이 사실상 없다.
          if (songsFile().existsSync()) raw = songsFile().readAsStringSync();
        } on FileSystemException {
          // 교체 순간의 열기 거절(Windows errno 32)은 깨진 게 아니다.
        }
        if (raw != null) {
          expect(
            SongMetaStore.tryDecodeEntries(raw),
            isNotNull,
            reason: '$n번째 호출 뒤의 정본이 깨져 있다',
          );
        }
      }
      expect(await Future.wait(results), everyElement(isTrue));
      expect((await idsOnDisk()).length, 25);
    });
  });

  group('load — 옛 파일이 그대로 읽힌다', () {
    test('v1 맨 배열을 읽고, 다음 저장에 v2 봉투로 올린다', () async {
      await seed(jsonEncode([song(1).toMetaJson(), song(2).toMetaJson()]));
      final store = newStore();
      final loaded = await store.load();
      expect(loaded.map((s) => s.id), ['s1', 's2']);
      expect(store.lastLoadState, AtomicLoadState.ok);

      expect(await store.save(loaded), isTrue);
      expect(await idsOnDisk(), ['s1', 's2']);
    });

    test('가사는 txt에서 읽어 붙인다', () async {
      await writeLyrics(1, utf8.encode('첫 줄\n둘째 줄\n'));
      final store = newStore();
      await store.save([song(1)]);
      expect((await newStore().load()).single.lyricsText, '첫 줄\n둘째 줄');
    });

    test('아무 파일도 없는 첫 실행은 빈 목록이고 정상이다', () async {
      final store = newStore();
      expect(await store.exists(), isFalse);
      expect(await store.load(), isEmpty);
      expect(store.lastLoadState, AtomicLoadState.ok);
    });
  });

  group('가사 txt 하나가 곡 목록 전체를 비우지 못한다', () {
    test('🔴 UTF-8이 아닌 가사 파일(메모장 ANSI 저장)이 있어도 목록은 전부 읽힌다', () async {
      // cp949로 저장한 '봄날' — UTF-8로는 풀리지 않는 바이트다. 예전에는 이 파일 하나의
      // FormatException이 곡 목록 전체를 []로 만들었고, 다음 저장이 songs.json을 덮었다.
      await writeLyrics(1, [0xBA, 0xBD, 0xB3, 0xAF]);
      await writeLyrics(2, utf8.encode('멀쩡한 가사'));
      await newStore().save([song(1), song(2)]);

      final store = newStore();
      final loaded = await store.load();
      expect(loaded.map((s) => s.id), ['s1', 's2']);
      expect(store.lastLoadState, AtomicLoadState.ok);
      expect(loaded[0].lyricsText, isNotEmpty, reason: '못 풀어도 비우지는 않는다');
      expect(loaded[1].lyricsText, '멀쩡한 가사');
    });

    test('decodeLyricsBytes: UTF-8은 그대로, BOM은 떼고, 깨진 바이트에도 던지지 않는다', () {
      expect(SongMetaStore.decodeLyricsBytes(utf8.encode('가사')), '가사');
      expect(
        SongMetaStore.decodeLyricsBytes([
          0xEF,
          0xBB,
          0xBF,
          ...utf8.encode('가사'),
        ]),
        '가사',
      );
      expect(SongMetaStore.decodeLyricsBytes([0xBA, 0xBD, 0xFF]), isNotEmpty);
    });

    test('🔴 decodeLyricsBytes: 끝이 한 바이트 잘린 UTF-8 가사는 마지막 글자만 잃고 본문은 그대로다', () {
      // 예전에는 바이트 하나가 깨지면 파일 전체를 cp949로 다시 풀어 본문 전체가
      // 「뷁」 계열로 깨졌다(줄바꿈까지). 그 본문이 다음 편집에서 txt를 영구히 덮었다.
      const text = '보고 싶다 이렇게 말하니까 더 보고 싶다\n너희 사진을 보고 있어도';
      final bytes = utf8.encode(text);
      final truncated = bytes.sublist(0, bytes.length - 1);
      final decoded = SongMetaStore.decodeLyricsBytes(truncated);
      expect(decoded, startsWith('보고 싶다 이렇게 말하니까 더 보고 싶다\n너희 사진을 보고 있어'));
      expect(decoded, isNot(contains('?')));
      expect(decoded.replaceAll('�', ''), text.substring(0, text.length - 1));
      // 중간 한 바이트가 상해도 마찬가지다.
      final damaged = [...bytes]..[10] = 0xFF;
      expect(
        SongMetaStore.decodeLyricsBytes(damaged),
        contains('이렇게 말하니까 더 보고 싶다\n너희 사진을'),
      );
      // 통째로 cp949인 파일은 여전히 cp949로 푼다(Windows).
      final cp949 = SongMetaStore.decodeLyricsBytes([0xBA, 0xBD, 0xB3, 0xAF]);
      expect(cp949, Platform.isWindows ? '봄날' : isNotEmpty);
    });

    test('Song으로 못 푼 항목은 원문 그대로 다시 저장된다(조용히 빠지지 않는다)', () async {
      // id가 문자열이 아니라 Song.fromJson이 던지는 항목.
      await seed(
        jsonEncode({
          'schemaVersion': 2,
          'songs': [
            song(1).toMetaJson(),
            {'id': 42, 'title': '손으로 고치다 틀린 항목', 'memo': '지우면 안 됨'},
            song(2).toMetaJson(),
          ],
        }),
      );
      final store = newStore();
      final loaded = await store.load();
      expect(loaded.map((s) => s.id), ['s1', 's2']);

      expect(await store.save([...loaded, song(3)]), isTrue);
      final decoded =
          jsonDecode(await songsFile().readAsString()) as Map<String, dynamic>;
      final songs = (decoded['songs'] as List).cast<Map<String, dynamic>>();
      expect(songs.map((s) => s['id']), ['s1', 's2', 's3', 42]);
      expect(songs.last['memo'], '지우면 안 됨');
    });
  });

  group('정본을 못 읽으면 .bak에서 되살린다', () {
    test('깨진 정본 + 멀쩡한 .bak → .bak을 읽는다', () async {
      final store = newStore();
      await store.save([song(1)]);
      await store.save([song(1), song(2)]); // .bak = [s1]
      await songsFile().writeAsString('{"schemaVersion":2,"songs":[{"id":"s1"');

      final fresh = newStore();
      expect((await fresh.load()).map((s) => s.id), ['s1']);
      expect(fresh.lastLoadState, AtomicLoadState.recoveredFromBackup);
    });

    test('길이 0인 정본(쓰다 죽은 모양) + 멀쩡한 .bak → .bak을 읽는다', () async {
      final store = newStore();
      await store.save([song(1), song(2)]);
      await store.save([song(1), song(2), song(3)]); // .bak = [s1, s2]
      await songsFile().writeAsString('');

      final fresh = newStore();
      expect((await fresh.load()).map((s) => s.id), ['s1', 's2']);
      expect(fresh.lastLoadState, AtomicLoadState.recoveredFromBackup);
    });

    test('되살린 뒤 저장해도 백업·깨진 원본이 다 남는다', () async {
      final store = newStore();
      await store.save([song(1), song(2)]);
      await store.save([song(1), song(2), song(3)]); // .bak = [s1, s2]
      const broken = '{"schemaVersion":2,"songs":[{"id":"s1"},{"id":';
      await songsFile().writeAsString(broken);

      final fresh = newStore();
      final loaded = await fresh.load();
      expect(await fresh.save([...loaded, song(9)]), isTrue);

      expect(await idsOnDisk(), ['s1', 's2', 's9']);
      // 🔴 멀쩡한 백업을 깨진 정본으로 덮지 않았다.
      expect(
        SongMetaStore.tryDecodeEntries(
          await backupFile().readAsString(),
        )!.map((e) => e['id']),
        ['s1', 's2'],
      );
      final corrupt = (await dataFiles()).where(
        (f) => f.startsWith('songs.json.corrupt-'),
      );
      expect(corrupt.length, 1);
      expect(
        await File('${tmp.path}/data/${corrupt.single}').readAsString(),
        broken,
      );
    });

    test('정본이 사라지고 .bak만 있어도 「있다」고 답한다(옛 저장소 이관으로 빠지지 않는다)', () async {
      final store = newStore();
      await store.save([song(1)]);
      await store.save([song(1), song(2)]);
      await songsFile().delete();

      final fresh = newStore();
      expect(await fresh.exists(), isTrue);
      expect((await fresh.load()).map((s) => s.id), ['s1']);
      expect(fresh.lastLoadState, AtomicLoadState.recoveredFromBackup);
    });
  });

  group('못 읽은 곡 목록이 다음 저장에서 증발하지 않는다', () {
    test('🔴 못 읽은 정본을 빈 목록으로는 덮지 않는다', () async {
      for (final broken in ['', '이건 JSON이 아니다', '{"songs":[{"id":"s1"']) {
        await seed(broken);
        final store = newStore();
        expect(await store.load(), isEmpty, reason: broken);
        expect(store.lastLoadState, AtomicLoadState.unreadable, reason: broken);
        expect(await store.save(const []), isFalse, reason: broken);
        expect(await songsFile().readAsString(), broken);
      }
      expect(await dataFiles(), ['songs.json']);
    });

    test('못 읽은 정본에 곡을 저장하면 깨진 원본이 .corrupt로 옆에 남는다', () async {
      const broken = '{"schemaVersion":2,"songs":[{"id":"s1","title":"봄';
      await seed(broken);
      final store = newStore();
      expect(await store.load(), isEmpty);
      expect(await store.save([song(7)]), isTrue);

      expect(await idsOnDisk(), ['s7']);
      final corrupt = (await dataFiles()).where(
        (f) => f.startsWith('songs.json.corrupt-'),
      );
      expect(corrupt.length, 1);
      expect(
        await File('${tmp.path}/data/${corrupt.single}').readAsString(),
        broken,
      );
      expect(await backupFile().exists(), isFalse);
    });

    test('상위 버전 파일은 예외로 올리고, 어떤 저장으로도 덮지 않는다', () async {
      const newer = '{"schemaVersion":99,"songs":[{"id":"future"}]}';
      await seed(newer);
      final store = newStore();
      await expectLater(store.load(), throwsA(isA<SongMetaSchemaException>()));
      expect(await store.save([song(1)]), isFalse);
      expect(await store.save(const []), isFalse);
      expect(await songsFile().readAsString(), newer);
      expect(await dataFiles(), ['songs.json']);
    });
  });

  group('못 열고 시작한 곡 목록 (Windows 잠금)', () {
    // Windows의 배타 잠금은 다른 핸들의 읽기를 거절한다 — 백신·OneDrive 동기화·
    // 오프라인 자리표시자의 「지금은 못 엶」의 대역이다.
    final skip = Platform.isWindows ? null : 'Windows 전용(강제 잠금)';

    test('🔴 부팅 때 songs.json이 안 열렸어도, 이후 저장 두 번에 옛 곡이 사라지지 않는다', () async {
      await seed(
        SongMetaStore.encodeEntries([
          for (var i = 1; i <= 3; i++) song(i).toMetaJson(),
        ]),
      );
      final before = await songsFile().readAsString();
      final lock = await songsFile().open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);

      final store = newStore();
      expect(await store.load(), isEmpty);
      expect(store.lastLoadState, AtomicLoadState.unreadable);
      // 잠긴 동안에는 곡이 있어도 덮지 않는다(사본도 백업도 뜰 수 없다).
      expect(await store.save([song(9)]), isFalse);
      await lock.unlock();
      await lock.close();
      expect(await songsFile().readAsString(), before);

      // 화면은 빈 목록으로 떴다. 곡 하나를 가져오고(저장), 즐겨찾기를 누른다(저장).
      // 예전 방식이면 첫 저장이 옛 목록을 .bak으로 밀고 둘째 저장이 그것마저 덮는다.
      expect(await store.save([song(9)]), isTrue);
      expect(await store.save([song(9, favorite: true)]), isTrue);

      expect((await idsOnDisk()).toSet(), {'s1', 's2', 's3', 's9'});
      final reopened = await newStore().load();
      expect(reopened.firstWhere((s) => s.id == 's9').isFavorite, isTrue);
    }, skip: skip);
  });

  group('SongRepository — 저장 실패를 삼키지 않는다', () {
    test('못 쓰면 false + onSaveFailed, 고치면 다음 저장이 닿는다', () async {
      // 정본 자리에 폴더가 있으면 rename이 거절된다(권한·잠금 실패의 대역).
      final obstacle = Directory(songsFile().path);
      await obstacle.create(recursive: true);

      final messages = <String>[];
      final repo = SongRepository.forTest(metaStore: newStore())
        ..onSaveFailed = messages.add;
      expect(await repo.saveSongs([song(1)]), isFalse);
      expect(messages, [kSongsSaveFailedMessage]);
      expect((await dataFiles()).where((f) => f.endsWith('.tmp')), isEmpty);

      await obstacle.delete();
      expect(await repo.saveSongs([song(1), song(2)]), isTrue);
      expect(messages.length, 1);
      expect(await idsOnDisk(), ['s1', 's2']);
    });

    test('연속 실패는 첫 번째만 알리고, 한 번 성공한 뒤의 실패는 다시 알린다', () async {
      // 문서 폴더가 오프라인인 동안에는 모든 저장이 실패한다. 곡 목록은 싱크 미세조정
      // 한 번마다 저장되므로, 매번 큰 경고를 띄우면 노래하는 내내 가사가 가려진다.
      final obstacle = Directory(songsFile().path);
      await obstacle.create(recursive: true);

      final messages = <String>[];
      final repo = SongRepository.forTest(metaStore: newStore())
        ..onSaveFailed = messages.add;
      for (var n = 0; n < 5; n++) {
        expect(await repo.saveSongs([song(1)]), isFalse);
      }
      expect(messages.length, 1);

      await obstacle.delete();
      expect(await repo.saveSongs([song(1)]), isTrue);
      await songsFile().delete();
      await obstacle.create(recursive: true);
      expect(await repo.saveSongs([song(1), song(2)]), isFalse);
      expect(messages.length, 2);
    });

    test('loadSongs가 못 읽음을 상태로 알리고, 빈 목록 저장은 파일을 건드리지 않는다', () async {
      const broken = '{"schemaVersion":2,"songs":[';
      await seed(broken);
      final repo = SongRepository.forTest(metaStore: newStore());
      expect(await repo.loadSongs(), isEmpty);
      expect(repo.songsLoadState, AtomicLoadState.unreadable);
      expect(repo.schemaLoadError, isNull);

      expect(await repo.saveSongs(const []), isFalse);
      expect(await songsFile().readAsString(), broken);
    });

    test('🔴 songsListTrusted — 온전히 읽은 목록만 고아 판정의 근거가 된다(라이브러리 정리 관문)', () async {
      // 빈 목록·낡은 목록과 대조하면 실제 곡의 반주·싱크 가사가 전부 「사용하지 않는
      // 파일」로 잡혀 정리 한 번에 지워진다. 네 가지 「온전하지 않음」을 전부 거른다.
      // ① 정상 파일 → 신뢰.
      await newStore().save([song(1)]);
      final ok = SongRepository.forTest(metaStore: newStore());
      await ok.loadSongs();
      expect(ok.songsListTrusted, isTrue);
      // 파일이 아직 없는 첫 실행도 정상이다(정리할 곡이 없을 뿐).
      await songsFile().delete();
      final fresh = SongRepository.forTest(metaStore: newStore());
      await fresh.loadSongs();
      expect(fresh.songsListTrusted, isTrue);

      // ② 못 읽음(잘린 JSON, .bak 없음).
      await seed('{"schemaVersion":2,"songs":[');
      final unreadable = SongRepository.forTest(metaStore: newStore());
      expect(await unreadable.loadSongs(), isEmpty);
      expect(unreadable.songsLoadState, AtomicLoadState.unreadable);
      expect(unreadable.songsListTrusted, isFalse);

      // ③ .bak에서 되살림 — 한 박자 낡아 마지막 추가곡의 파일이 고아로 보인다.
      await backupFile().writeAsString(
        SongMetaStore.encodeEntries([song(1).toMetaJson()]),
      );
      final recovered = SongRepository.forTest(metaStore: newStore());
      expect((await recovered.loadSongs()).map((s) => s.id), ['s1']);
      expect(recovered.songsLoadState, AtomicLoadState.recoveredFromBackup);
      expect(recovered.songsListTrusted, isFalse);
      await backupFile().delete();

      // ④ Song으로 못 푼 항목 — 정본에는 있는데 목록에 없는 곡.
      await seed(
        jsonEncode({
          'schemaVersion': 2,
          'songs': [
            song(1).toMetaJson(),
            {'id': 42, 'title': '손으로 고치다 틀린 항목'},
          ],
        }),
      );
      final partial = SongRepository.forTest(metaStore: newStore());
      expect((await partial.loadSongs()).map((s) => s.id), ['s1']);
      expect(partial.songsLoadState, AtomicLoadState.ok);
      expect(partial.songsListTrusted, isFalse);

      // ⑤ 상위 버전 거부.
      await seed('{"schemaVersion":99,"songs":[]}');
      final newer = SongRepository.forTest(metaStore: newStore());
      await newer.loadSongs();
      expect(newer.schemaLoadError, isNotNull);
      expect(newer.songsListTrusted, isFalse);
    });

    test('상위 버전이면 안내 문구를 기억하고 저장을 통째로 막는다(기존 동작)', () async {
      const newer = '{"schemaVersion":99,"songs":[]}';
      await seed(newer);
      final repo = SongRepository.forTest(metaStore: newStore());
      expect(await repo.loadSongs(), isEmpty);
      expect(repo.schemaLoadError, contains('업데이트'));
      expect(await repo.saveSongs([song(1)]), isFalse);
      expect(await songsFile().readAsString(), newer);
    });
  });
}
