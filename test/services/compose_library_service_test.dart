// file: test/services/compose_library_service_test.dart
//
// AI 생성곡 목록(compositions.json) 저장의 데이터 안전.
//
// 만든 계기: 저장 예외를 삼켰고, 못 읽은 파일을 빈 목록으로 읽었다 — 그 다음 add가
// 목록 전체를 덮으면 가사·스타일 프롬프트·시드가 날아가고 오디오 파일만 남는다.
// 화면(제목 바꾸기·삭제)·제어 API(삭제)·작곡 완료(add)가 겹쳐 부를 수 있다.
//
// 실제 파일 IO를 기다리므로 전부 plain test()다(testWidgets의 가짜 시계 금지).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/composition.dart';
import 'package:singpromfter_app/services/atomic_json_file.dart';
import 'package:singpromfter_app/services/compose_library_service.dart';

Composition comp(int i, {String? title}) => Composition(
  id: 'c$i',
  title: title ?? '생성곡 $i',
  mode: ComposeMode.vocal,
  stylePromptKo: '잔잔한 발라드 $i',
  lyrics: '가사 $i',
  durationSec: 120,
  seed: 1000 + i,
  fileName: 'c$i.mp3',
  createdAt: DateTime(2026, 9, 22, 10, 0, i),
);

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sp_compose_store_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  ComposeStore newStore() => ComposeStore(
    baseDirBuilder: () async => tmp,
    ioRetryDelay: const Duration(milliseconds: 1),
  );

  File indexFile() => File('${tmp.path}/data/compose/compositions.json');
  File backupFile() => File('${indexFile().path}.bak');

  /// 디스크의 정본을 직접 읽어 id 목록으로 돌려준다(JSON이 깨졌으면 여기서 실패).
  Future<List<String>> idsOnDisk() async {
    final decoded =
        jsonDecode(await indexFile().readAsString()) as Map<String, dynamic>;
    return [
      for (final c in decoded['compositions'] as List)
        (c as Map<String, dynamic>)['id'] as String,
    ];
  }

  Future<List<String>> composeFiles() async => [
    await for (final e in Directory('${tmp.path}/data/compose').list())
      if (e is File) e.uri.pathSegments.last,
  ]..sort();

  Future<void> seed(String body) async {
    await Directory('${tmp.path}/data/compose').create(recursive: true);
    await indexFile().writeAsString(body);
  }

  group('decodeCompositionIndex — 「못 읽음」과 「빈 목록」을 가른다', () {
    test('정상 본문·빈 목록은 목록으로, 나머지는 null', () {
      final body = encodeCompositionIndex([comp(1)]);
      final back = decodeCompositionIndex(body)!.single;
      expect(back.id, 'c1');
      expect(back.lyrics, '가사 1');
      expect(back.seed, 1001);
      expect(decodeCompositionIndex(encodeCompositionIndex(const [])), isEmpty);
      expect(decodeCompositionIndex(''), isNull);
      expect(
        decodeCompositionIndex(body.substring(0, body.length ~/ 2)),
        isNull,
      );
      expect(decodeCompositionIndex('[]'), isNull);
    });

    test('상위 버전은 null(깨짐)이 아니라 예외다 — 헬퍼가 「읽기 거부」로 분류한다', () {
      // null이면 헬퍼가 첫 add에서 .corrupt-로 옮기고 구버전 봉투로 갈아 끼운다.
      expect(
        () => decodeCompositionIndex('{"schemaVersion":99,"compositions":[]}'),
        throwsA(isA<AtomicSchemaException>()),
      );
    });

    test('파일 형식은 그대로다 — 봉투, 들여쓰기 2칸', () {
      expect(
        encodeCompositionIndex([comp(1)]),
        startsWith('{\n  "schemaVersion": 1,\n  "compositions": [\n'),
      );
    });
  });

  group('겹쳐 불린 add/update/remove가 섞이지 않는다', () {
    test('add/update 50회 교차 → JSON 유효, 항목 수·내용 일치', () async {
      final library = ComposeLibraryService(store: newStore());
      await library.load();

      final results = <Future<bool>>[];
      for (var i = 0; i < 25; i++) {
        results.add(library.add(comp(i)));
        results.add(library.update(comp(i, title: '고친 제목 $i')));
      }
      expect(await Future.wait(results), everyElement(isTrue));

      expect((await idsOnDisk()).toSet(), {for (var i = 0; i < 25; i++) 'c$i'});
      expect((await composeFiles()).where((f) => f.endsWith('.tmp')), isEmpty);

      final reopened = ComposeLibraryService(store: newStore());
      await reopened.load();
      expect(reopened.loadState, AtomicLoadState.ok);
      expect(reopened.items.length, 25);
      for (final item in reopened.items) {
        expect(item.title, '고친 제목 ${item.id.substring(1)}');
        expect(item.lyrics, '가사 ${item.id.substring(1)}');
      }
    });

    test('add·update·remove를 섞어도 마지막 상태가 남는다', () async {
      final library = ComposeLibraryService(store: newStore());
      await library.load();
      final results = <Future<bool>>[
        for (var i = 0; i < 8; i++) library.add(comp(i)),
        library.update(comp(3, title: '수정')),
        library.remove(comp(5)),
        library.add(comp(8)),
      ];
      expect(await Future.wait(results), everyElement(isTrue));

      final expected = {for (var i = 0; i <= 8; i++) 'c$i'}..remove('c5');
      expect((await idsOnDisk()).toSet(), expected);
    });
  });

  group('patch — 지금 생성곡에 변경을 얹는다', () {
    test('🔴 곡 등록이 도는 사이에 바꾼 제목이 남고, 등록 표시도 남는다', () async {
      final library = ComposeLibraryService(store: newStore());
      await library.load();
      await library.add(comp(1));

      // 등록이 시작할 때 집어 둔 사본 — 파일 복사(OneDrive)를 기다리는 동안 제목을 바꾼다.
      final picked = library.byId('c1')!;
      await library.patch('c1', (c) => c.copyWith(title: '새 제목'));
      final registered = await library.patch(
        picked.id,
        (c) => c.copyWith(registeredSongId: 'song-1'),
      );

      // 예전(picked.copyWith(...)를 통째로 update)에는 제목이 「생성곡 1」로 되돌아갔다.
      expect(registered!.title, '새 제목');
      expect(registered.registeredSongId, 'song-1');

      final reopened = ComposeLibraryService(store: newStore());
      await reopened.load();
      expect(reopened.byId('c1')!.title, '새 제목');
      expect(reopened.byId('c1')!.registeredSongId, 'song-1');
    });

    test('없는 id는 null이고 목록 파일을 다시 쓰지 않는다', () async {
      final library = ComposeLibraryService(store: newStore());
      await library.load();
      await library.add(comp(1));

      // 저장이 한 번이라도 돌면 정본이 다시 생긴다 — 지워 두고 본다.
      await indexFile().delete();
      expect(
        await library.patch('ghost', (c) => c.copyWith(title: 'x')),
        isNull,
      );
      expect(await indexFile().exists(), isFalse);
      expect(library.items.single.title, '생성곡 1');
    });
  });

  group('정본을 못 읽어도 목록이 증발하지 않는다', () {
    test('깨진 정본 + 멀쩡한 .bak → .bak을 읽는다', () async {
      final store = newStore();
      await store.save([comp(1)]);
      await store.save([comp(1), comp(2)]); // .bak = [c1]
      await indexFile().writeAsString('{"schemaVersion":1,"compositions":[{');

      final library = ComposeLibraryService(store: newStore());
      await library.load();
      expect(library.items.map((c) => c.id), ['c1']);
      expect(library.loadState, AtomicLoadState.recoveredFromBackup);

      // 되살린 뒤 저장해도 멀쩡한 백업은 그대로, 깨진 원본은 옆에 남는다.
      expect(await library.add(comp(9)), isTrue);
      expect((await idsOnDisk()).toSet(), {'c1', 'c9'});
      expect(
        decodeCompositionIndex(await backupFile().readAsString())!.single.id,
        'c1',
      );
      expect(
        (await composeFiles()).where(
          (f) => f.startsWith('compositions.json.corrupt-'),
        ),
        hasLength(1),
      );
    });

    test('🔴 못 읽은 정본을 빈 목록으로는 덮지 않는다', () async {
      const broken = '{"schemaVersion":1,"compositions":[{"id":"c1","lyrics":"';
      await seed(broken);
      final store = newStore();
      expect(await store.load(), isEmpty);
      expect(store.lastLoadState, AtomicLoadState.unreadable);
      expect(await store.save(const []), isFalse);
      expect(await indexFile().readAsString(), broken);
      expect(await composeFiles(), ['compositions.json']);
    });

    test('못 읽은 정본에 add하면 깨진 원본이 .corrupt로 옆에 남는다', () async {
      const broken = '{"schemaVersion":1,"compositions":[{"id":"c1","lyrics":"';
      await seed(broken);
      final library = ComposeLibraryService(store: newStore());
      await library.load();
      expect(await library.add(comp(7)), isTrue);

      expect(await idsOnDisk(), ['c7']);
      final corrupt = (await composeFiles()).where(
        (f) => f.startsWith('compositions.json.corrupt-'),
      );
      expect(corrupt.length, 1);
      expect(
        await File('${tmp.path}/data/compose/${corrupt.single}').readAsString(),
        broken,
      );
    });

    test('🔴 상위 버전 파일(구버전 exe로 되돌아감)은 비어 있지 않은 add로도 덮지 않는다', () async {
      // 예전에는 「깨짐」으로 봐서 첫 add가 정본을 .corrupt-로 옮기고 구버전 봉투로
      // 갈아 끼웠다 — 새 빌드로 올라가면 그 사이 만든 생성곡이 목록에서 빠져 있다.
      const newer = '{"schemaVersion":99,"compositions":[{"id":"future"}]}';
      await seed(newer);
      final library = ComposeLibraryService(store: newStore());
      await library.load();
      expect(library.loadState, AtomicLoadState.unreadable);

      expect(await library.add(comp(7)), isFalse);
      expect(await indexFile().readAsString(), newer);
      expect(await composeFiles(), ['compositions.json']);
    });
  });

  group('저장 실패를 삼키지 않는다', () {
    test('못 쓰면 false + onSaveFailed, 고치면 다음 저장에 함께 실린다', () async {
      // 정본 자리에 폴더가 있으면 rename이 거절된다(권한·잠금 실패의 대역).
      final obstacle = Directory(indexFile().path);
      await obstacle.create(recursive: true);

      final messages = <String>[];
      final library = ComposeLibraryService(store: newStore())
        ..onSaveFailed = messages.add;
      await library.load();
      expect(await library.add(comp(1)), isFalse);
      expect(messages, [kComposeSaveFailedMessage]);
      // 메모리의 목록은 그대로다 — 방금 만든 곡이 화면에서 사라지지 않는다.
      expect(library.items.single.id, 'c1');
      expect((await composeFiles()).where((f) => f.endsWith('.tmp')), isEmpty);

      await obstacle.delete();
      expect(await library.add(comp(2)), isTrue);
      expect((await idsOnDisk()).toSet(), {'c1', 'c2'});
    });
  });

  group('못 열고 시작한 목록 (Windows 잠금)', () {
    final skip = Platform.isWindows ? null : 'Windows 전용(강제 잠금)';

    test('🔴 부팅 때 정본이 안 열렸어도, 이후 저장 두 번에 옛 생성곡이 사라지지 않는다', () async {
      await seed(encodeCompositionIndex([comp(1), comp(2)]));
      final lock = await indexFile().open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);

      final library = ComposeLibraryService(store: newStore());
      await library.load();
      expect(library.items, isEmpty);
      expect(library.loadState, AtomicLoadState.unreadable);
      await lock.unlock();
      await lock.close();

      expect(await library.add(comp(9)), isTrue);
      expect(await library.update(comp(9, title: '제목 고침')), isTrue);
      expect((await idsOnDisk()).toSet(), {'c1', 'c2', 'c9'});
    }, skip: skip);
  });
}
