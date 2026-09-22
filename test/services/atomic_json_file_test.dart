// file: test/services/atomic_json_file_test.dart
//
// 공용 원자 저장 헬퍼의 데이터 안전 — 경로 잠금·읽고-바꾸고-쓰기·못 읽은 정본 보호.
//
// RecordingStore에서 옮겨 온 규칙(직렬·원자 교체·`.bak`·`.corrupt`)은
// recording_library_service_test.dart가 그대로 지킨다. 여기서는 헬퍼가 새로 맡은
// 것을 본다: 같은 파일을 쓰는 **여러 인스턴스**, update(), 읽기 거부, 못 열고 시작한
// 정본을 살리는 rescue, 텍스트 원자 쓰기.
//
// 실제 파일 IO를 기다리므로 전부 plain test()다(testWidgets의 가짜 시계 금지).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/services/atomic_json_file.dart';

/// 테스트용 본문: `{"items": [...]}`. 못 읽으면 null, 'refuse' 표식이 있으면 예외.
List<String>? decodeItems(String raw) {
  final text = stripBom(raw);
  if (text.trim().isEmpty) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  if (decoded['refuse'] == true) throw const FormatException('상위 버전');
  final items = decoded['items'];
  if (items is! List) return null;
  return items.whereType<String>().toList();
}

String encodeItems(List<String> items) => jsonEncode({'items': items});

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sp_atomic_json_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  File mainFile() => File('${tmp.path}/items.json');
  File backupFile() => File('${mainFile().path}.bak');

  AtomicJsonFile<List<String>> newFile({
    bool rescue = false,
    bool keepBackup = true,
  }) => AtomicJsonFile<List<String>>(
    fileBuilder: () async => mainFile(),
    encode: encodeItems,
    decode: decodeItems,
    isEmpty: (items) => items.isEmpty,
    label: 'items.json',
    keepBackup: keepBackup,
    rescue: rescue ? AtomicRescue.listById<String>((item) => item) : null,
    ioRetryDelay: const Duration(milliseconds: 1),
  );

  /// 디스크의 정본을 직접 읽는다(JSON이 깨졌으면 여기서 실패).
  Future<List<String>> itemsOnDisk() async =>
      decodeItems(await mainFile().readAsString())!;

  /// 폴더에 남은 파일 이름들.
  Future<List<String>> files() async => [
    await for (final e in tmp.list())
      if (e is File) e.uri.pathSegments.last,
  ]..sort();

  group('같은 파일을 쓰는 인스턴스가 여럿이어도 섞이지 않는다 (경로 잠금)', () {
    test('두 인스턴스가 기다리지 않고 50번 교차 저장 → JSON 유효, .tmp 없음', () async {
      final a = newFile();
      final b = newFile();
      final results = <Future<bool>>[];
      for (var n = 1; n <= 25; n++) {
        results.add(a.save([for (var i = 0; i < n; i++) 'a$i']));
        results.add(b.save([for (var i = 0; i < n; i++) 'b$i']));
      }
      expect(await Future.wait(results), everyElement(isTrue));

      // 인스턴스별로 가장 새 값만 쓰므로, 남는 것은 둘 중 한쪽의 **마지막 목록 전체**다.
      final onDisk = await itemsOnDisk();
      expect(onDisk.length, 25);
      expect(onDisk.every((item) => item.startsWith(onDisk.first[0])), isTrue);
      expect((await files()).where((f) => f.endsWith('.tmp')), isEmpty);
    });

    test('쓰는 도중에도 정본은 언제나 읽히는 JSON이다', () async {
      final a = newFile();
      final b = newFile();
      final results = <Future<bool>>[];
      for (var n = 1; n <= 20; n++) {
        results.add(a.save([for (var i = 0; i < n; i++) 'a$i']));
        await Future<void>.delayed(Duration.zero);
        results.add(b.save([for (var i = 0; i < n; i++) 'b$i']));
        await Future<void>.delayed(Duration.zero);
        String? raw;
        try {
          // 🔴 동기로 읽는다. Windows는 다른 핸들이 정본을 쥔 동안 .tmp→정본 rename을
          // 거절한다(errno 5). 비동기 읽기는 IO 스레드를 오가는 사이 핸들을 잡고
          // 있어서, 스위트가 병렬로 돌 때 8×1ms 재시도 예산보다 오래 쥘 수 있다
          // (song_meta_store_test에서 실측). 동기 읽기는 μs 단위라 창이 사실상 없다.
          if (mainFile().existsSync()) raw = mainFile().readAsStringSync();
        } on FileSystemException {
          // 교체 순간의 열기 거절(Windows errno 32)은 깨진 게 아니다.
        }
        if (raw != null) {
          expect(decodeItems(raw), isNotNull, reason: '$n번째 뒤의 정본이 깨져 있다');
        }
      }
      expect(await Future.wait(results), everyElement(isTrue));
    });

    test('update()는 서로 다른 인스턴스의 추가분을 잃지 않는다', () async {
      final instances = [newFile(), newFile(), newFile()];
      final results = <Future<List<String>?>>[];
      for (var n = 0; n < 45; n++) {
        results.add(instances[n % 3].update((disk) => [...?disk, 'item$n']));
      }
      expect(await Future.wait(results), everyElement(isNotNull));

      expect((await itemsOnDisk()).toSet(), {
        for (var n = 0; n < 45; n++) 'item$n',
      });
      expect((await files()).where((f) => f.endsWith('.tmp')), isEmpty);
    });

    test('update()와 다른 인스턴스의 load()가 겹쳐도 온전한 값만 읽힌다', () async {
      final writer = newFile();
      final reader = newFile();
      await writer.save(['seed']);
      final writes = <Future<List<String>?>>[];
      for (var n = 0; n < 20; n++) {
        writes.add(writer.update((disk) => [...?disk, 'w$n']));
        final seen = await reader.load();
        expect(seen, isNotNull);
        expect(seen!.first, 'seed');
        expect(reader.lastLoadState, AtomicLoadState.ok);
      }
      await Future.wait(writes);
      expect((await itemsOnDisk()).length, 21);
    });
  });

  group('update — 읽고-바꾸고-쓰기', () {
    test('파일이 없으면 null에서 출발한다', () async {
      final file = newFile();
      expect(await file.update((disk) => [...?disk, 'x']), ['x']);
      expect(await itemsOnDisk(), ['x']);
    });

    test('받은 객체를 그대로 돌려주면 파일을 다시 쓰지 않는다', () async {
      final file = newFile();
      await file.save(['a']);
      final before = await mainFile().lastModified();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(await file.update((disk) => disk!), ['a']);
      expect(await mainFile().lastModified(), before);
      // 다시 쓰지 않았으니 백업도 돌지 않았다.
      expect(await backupFile().exists(), isFalse);
    });

    test('깨진 정본이면 .bak에서 이어 가고, 깨진 원본은 옆에 남긴다', () async {
      final file = newFile();
      await file.save(['a']);
      await file.save(['a', 'b']); // .bak = [a]
      await mainFile().writeAsString('{"items":["a","b"');

      expect(await newFile().update((disk) => [...?disk, 'c']), ['a', 'c']);
      expect(await itemsOnDisk(), ['a', 'c']);
      // 멀쩡한 백업을 깨진 정본으로 덮지 않았다.
      expect(decodeItems(await backupFile().readAsString()), ['a']);
      expect(
        (await files())
            .where((f) => f.startsWith('items.json.corrupt-'))
            .length,
        1,
      );
    });

    test('깨진 정본 + 백업 없음 + 빈 결과 → 덮지 않는다', () async {
      const broken = '{"items":["a"';
      await mainFile().writeAsString(broken);
      expect(await newFile().update((disk) => disk ?? const []), isNull);
      expect(await mainFile().readAsString(), broken);
      expect(await files(), ['items.json']);
    });
  });

  group('「못 읽음」은 「빈 값」이 아니다', () {
    test('빈 파일·잘린 JSON → load는 null + unreadable, 빈 값 저장은 거절', () async {
      for (final body in ['', '   \n', '{"items":["a","b"', '[1,2]']) {
        await mainFile().writeAsString(body);
        final file = newFile();
        expect(await file.load(), isNull, reason: body);
        expect(file.lastLoadState, AtomicLoadState.unreadable, reason: body);
        expect(await file.save(const []), isFalse, reason: body);
        expect(await mainFile().readAsString(), body);
      }
      expect(await files(), ['items.json']);
    });

    test('파일이 없는 첫 실행은 null이지만 정상(ok)이다', () async {
      final file = newFile();
      expect(await file.load(), isNull);
      expect(file.lastLoadState, AtomicLoadState.ok);
      // 없는 파일에는 빈 값도 쓸 수 있다.
      expect(await file.save(const []), isTrue);
      expect(await itemsOnDisk(), isEmpty);
    });

    test('깨진 정본 + 멀쩡한 .bak → .bak을 읽고 recoveredFromBackup', () async {
      final file = newFile();
      await file.save(['a']);
      await file.save(['a', 'b']); // .bak = [a]
      await mainFile().writeAsString('');

      final fresh = newFile();
      expect(await fresh.load(), ['a']);
      expect(fresh.lastLoadState, AtomicLoadState.recoveredFromBackup);
    });

    test('못 읽은 정본에 값을 저장하면 깨진 원본이 .corrupt로 남는다', () async {
      const broken = '이건 JSON이 아니다';
      await mainFile().writeAsString(broken);
      final file = newFile();
      expect(await file.load(), isNull);
      expect(await file.save(['new']), isTrue);

      expect(await itemsOnDisk(), ['new']);
      final corrupt = (await files()).where(
        (f) => f.startsWith('items.json.corrupt-'),
      );
      expect(corrupt.length, 1);
      expect(
        await File('${tmp.path}/${corrupt.single}').readAsString(),
        broken,
      );
      // 깨진 정본이 백업 자리로 들어가지 않았다.
      expect(await backupFile().exists(), isFalse);
    });

    test('keepBackup: false면 .bak을 만들지 않는다', () async {
      final file = newFile(keepBackup: false);
      await file.save(['a']);
      await file.save(['a', 'b']);
      expect(await files(), ['items.json']);
    });
  });

  group('읽기 거부(decode가 던짐) — 깨진 게 아니라 이 앱이 못 읽는 파일', () {
    const newer = '{"refuse":true,"items":["future"]}';

    test('load는 그 예외를 그대로 던지고 .bak으로 넘어가지 않는다', () async {
      final file = newFile();
      await file.save(['a']);
      await file.save(['a', 'b']); // .bak = [a]
      await mainFile().writeAsString(newer);

      final fresh = newFile();
      await expectLater(fresh.load(), throwsA(isA<FormatException>()));
      expect(fresh.lastLoadState, AtomicLoadState.unreadable);
    });

    test('save·update 모두 그 정본을 덮지 않는다(.corrupt로 치우지도 않는다)', () async {
      await mainFile().writeAsString(newer);
      final file = newFile();
      expect(await file.save(['mine']), isFalse);
      expect(await file.update((disk) => [...?disk, 'mine']), isNull);
      expect(await mainFile().readAsString(), newer);
      expect(await files(), ['items.json']);
    });
  });

  group('못 열고 시작한 정본을 살린다 (rescue, Windows 잠금)', () {
    // Windows의 배타 잠금은 다른 핸들의 읽기를 거절한다 — 백신·동기화·오프라인
    // 자리표시자의 「지금은 못 엶」의 대역이다. 다른 OS의 잠금은 권고라 막지 않는다.
    final skip = Platform.isWindows ? null : 'Windows 전용(강제 잠금)';

    test('🔴 부팅 때 정본이 안 열렸어도, 이후 저장 두 번에 옛 항목이 사라지지 않는다', () async {
      // .bak이 아직 없는 첫 실행(업데이트 직후)의 모양 — 정본만 있다.
      await mainFile().writeAsString(encodeItems(['old1', 'old2', 'old3']));
      final lock = await mainFile().open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);

      final file = newFile(rescue: true);
      expect(await file.load(), isNull);
      expect(file.lastLoadState, AtomicLoadState.unreadable);
      // 잠긴 동안에는 값이 있어도 덮지 않는다.
      expect(await file.save(['new1']), isFalse);
      await lock.unlock();
      await lock.close();

      // 호출자는 옛 항목을 모른 채 자기 목록만 두 번 저장한다. 예전 방식이면 첫
      // 저장이 옛 목록을 .bak으로 밀고, 둘째 저장이 그 .bak마저 덮는다.
      expect(await file.save(['new1']), isTrue);
      expect(await file.save(['new1', 'new2']), isTrue);

      expect(await itemsOnDisk(), ['old1', 'old2', 'old3', 'new1', 'new2']);
      expect(
        decodeItems(await backupFile().readAsString()),
        containsAll(['old1', 'old2', 'old3']),
      );
    }, skip: skip);

    test('같은 키는 메모리 쪽이 이기고, 살린 항목은 한 번만 실린다', () async {
      await mainFile().writeAsString(encodeItems(['a', 'b']));
      final lock = await mainFile().open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      final file = newFile(rescue: true);
      await file.load();
      await lock.unlock();
      await lock.close();

      expect(await file.save(['b', 'c']), isTrue);
      expect(await itemsOnDisk(), ['a', 'b', 'c']);
      // 호출자가 나중에 같은 키를 직접 갖게 되면 살린 사본은 물러난다.
      expect(await file.save(['a', 'b', 'c', 'd']), isTrue);
      expect(await itemsOnDisk(), ['a', 'b', 'c', 'd']);
    }, skip: skip);

    test('정상으로 읽고 시작했으면 아무것도 얹지 않는다(지운 항목이 되살아나지 않는다)', () async {
      await mainFile().writeAsString(encodeItems(['a', 'b', 'c']));
      final file = newFile(rescue: true);
      expect(await file.load(), ['a', 'b', 'c']);
      expect(await file.save(['a', 'c']), isTrue);
      expect(await itemsOnDisk(), ['a', 'c']);
    });

    test('🔴 .bak으로 시작한 세션에서 지운 항목은 첫 저장에 되살아나지 않는다(유령 항목)', () async {
      // 정본과 .bak이 같은 [a,b,c]. 정본이 잠겨 .bak으로 떴고, 사용자가 b를 지웠다.
      // 예전에는 첫 저장이 「지금 값 [a,c]」와 정본 [a,b,c]를 견줘 b를 살려 실었다 —
      // 파일은 이미 지워져 목록에만 남는 유령 항목이 됐다.
      await mainFile().writeAsString(encodeItems(['a', 'b', 'c']));
      await backupFile().writeAsString(encodeItems(['a', 'b', 'c']));
      final lock = await mainFile().open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);

      final file = newFile(rescue: true);
      expect(await file.load(), ['a', 'b', 'c']);
      expect(file.lastLoadState, AtomicLoadState.recoveredFromBackup);
      await lock.unlock();
      await lock.close();

      expect(await file.save(['a', 'c']), isTrue);
      expect(await itemsOnDisk(), ['a', 'c']);
      // 같은 세션에서 다시 저장해도 되돌아오지 않는다.
      expect(await file.save(['a', 'c']), isTrue);
      expect(await itemsOnDisk(), ['a', 'c']);
    }, skip: skip);

    test('.bak보다 새로 정본에만 있던 항목만 살린다', () async {
      // 정본 [a,b,c,d], .bak [a,b,c] — 사용자는 .bak을 보고 b를 지웠다.
      await mainFile().writeAsString(encodeItems(['a', 'b', 'c', 'd']));
      await backupFile().writeAsString(encodeItems(['a', 'b', 'c']));
      final lock = await mainFile().open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);

      final file = newFile(rescue: true);
      expect(await file.load(), ['a', 'b', 'c']);
      await lock.unlock();
      await lock.close();

      expect(await file.save(['a', 'c']), isTrue);
      // d는 본 적이 없으니 살리고, b는 봤으니 지운 것이다.
      expect(await itemsOnDisk(), ['d', 'a', 'c']);
    }, skip: skip);

    test('🔴 정본을 다시 읽어도(백업 내보내기 같은 읽기 전용 호출자) 살려 둔 항목은 남는다', () async {
      // 화면은 살려 둔 곡을 본 적이 없는 목록을 계속 들고 있다. 다시 읽었다고 살려 둔
      // 것을 비우면, 그 뒤 화면의 첫 저장이 옛 곡 전부를 지운다(유령 항목보다 훨씬 비싸다).
      await mainFile().writeAsString(encodeItems(['old1', 'old2']));
      final lock = await mainFile().open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      final file = newFile(rescue: true);
      expect(await file.load(), isNull);
      await lock.unlock();
      await lock.close();

      expect(await file.save(['new1']), isTrue);
      expect(await itemsOnDisk(), ['old1', 'old2', 'new1']);

      // 백업 내보내기가 정본을 읽어 갔다 — 화면 목록은 여전히 [new1]이다.
      expect(await file.load(), ['old1', 'old2', 'new1']);
      expect(file.lastLoadState, AtomicLoadState.ok);
      expect(await file.save(['new1', 'new2']), isTrue);
      expect(await itemsOnDisk(), ['old1', 'old2', 'new1', 'new2']);
    }, skip: skip);

    test('🔴 못 열고 시작한 뒤 첫 읽기가 읽기 전용 호출자여도 정본에만 있던 항목은 살려 둔다', () async {
      // 잠긴 채 뜬 뒤 첫 저장 전에 백업 내보내기가 정본을 읽어 갔다. 예전에는 그 읽기가
      // 「처음 본 정본」을 소비만 하고 살려 두지 않아, 화면의 다음 저장이 옛 곡을 지웠다.
      await mainFile().writeAsString(encodeItems(['old1', 'old2']));
      final lock = await mainFile().open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      final file = newFile(rescue: true);
      expect(await file.load(), isNull);
      await lock.unlock();
      await lock.close();

      expect(await file.load(), ['old1', 'old2']); // 백업 내보내기
      expect(await file.save(['new1']), isTrue); // 화면(빈 목록으로 떴다)
      expect(await itemsOnDisk(), ['old1', 'old2', 'new1']);

      // .bak으로 떴으면 본 항목(b)은 지운 것이고, 정본에만 있던 d만 살린다.
      await mainFile().writeAsString(encodeItems(['a', 'b', 'c', 'd']));
      await backupFile().writeAsString(encodeItems(['a', 'b', 'c']));
      final lock2 = await mainFile().open(mode: FileMode.append);
      await lock2.lock(FileLock.exclusive);
      final again = newFile(rescue: true);
      expect(await again.load(), ['a', 'b', 'c']);
      await lock2.unlock();
      await lock2.close();
      expect(await again.load(), ['a', 'b', 'c', 'd']); // 백업 내보내기
      expect(await again.save(['a', 'c']), isTrue); // 화면이 b를 지웠다
      expect(await itemsOnDisk(), ['d', 'a', 'c']);
    }, skip: skip);

    test('rescue가 없으면 얹지 않는다(호출자가 직접 합치는 저장소)', () async {
      await mainFile().writeAsString(encodeItems(['old']));
      final lock = await mainFile().open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      final file = newFile();
      await file.load();
      await lock.unlock();
      await lock.close();

      expect(await file.save(['new']), isTrue);
      expect(await itemsOnDisk(), ['new']);
      // 그래도 직전 정본은 .bak에 한 벌 남는다.
      expect(decodeItems(await backupFile().readAsString()), ['old']);
    }, skip: skip);
  });

  group('자리가 바뀌면 옛 자리의 상태를 버린다 (싱글턴 저장소 + 테스트 폴더)', () {
    test('못 읽음 상태가 다른 폴더로 새지 않는다', () async {
      var dir = Directory('${tmp.path}/one')..createSync();
      File('${dir.path}/items.json').writeAsStringSync('깨짐');
      final file = AtomicJsonFile<List<String>>(
        fileBuilder: () async => File('${dir.path}/items.json'),
        encode: encodeItems,
        decode: decodeItems,
        isEmpty: (items) => items.isEmpty,
        label: 'items.json',
        ioRetryDelay: const Duration(milliseconds: 1),
      );
      expect(await file.load(), isNull);
      expect(file.lastLoadState, AtomicLoadState.unreadable);

      dir = Directory('${tmp.path}/two')..createSync();
      expect(await file.save(['x']), isTrue);
      expect(file.lastLoadState, AtomicLoadState.ok);
    });
  });

  group('SaveFailureGate — 연속 실패는 첫 번째만 알린다', () {
    test('실패로 바뀐 순간에만 true, 성공하면 다시 알릴 수 있다', () {
      final gate = SaveFailureGate();
      expect(gate.shouldNotify(saved: true), isFalse);
      expect(gate.shouldNotify(saved: false), isTrue);
      expect(gate.shouldNotify(saved: false), isFalse);
      expect(gate.shouldNotify(saved: false), isFalse);
      expect(gate.shouldNotify(saved: true), isFalse);
      expect(gate.shouldNotify(saved: false), isTrue);
    });
  });

  group('writeTextAtomically — 가사·싱크 가사용', () {
    test('내용이 그대로 쓰이고 .tmp·.bak이 남지 않는다', () async {
      final target = File('${tmp.path}/song.lrc');
      expect(await writeTextAtomically(target, '[00:01.00]첫 줄\n'), isTrue);
      expect(await writeTextAtomically(target, '[00:02.00]둘째 판\n'), isTrue);
      expect(await target.readAsString(), '[00:02.00]둘째 판\n');
      expect(await files(), ['song.lrc']);
    });

    test('기존 .bak(재타이밍 전 원본)을 건드리지 않는다', () async {
      final target = File('${tmp.path}/song.lrc');
      await target.writeAsString('원본');
      await File('${target.path}.bak').writeAsString('재타이밍 전 원본');

      expect(await writeTextAtomically(target, '새 판'), isTrue);
      expect(await File('${target.path}.bak').readAsString(), '재타이밍 전 원본');
    });

    test('기다리지 않고 30번 겹쳐 써도 마지막에 온전한 한 판이 남는다', () async {
      final target = File('${tmp.path}/song.txt');
      final bodies = [for (var n = 0; n < 30; n++) '판 $n\n' * (n + 1)];
      final results = [
        for (final body in bodies)
          writeTextAtomically(
            target,
            body,
            ioRetryDelay: const Duration(milliseconds: 1),
          ),
      ];
      expect(await Future.wait(results), everyElement(isTrue));
      expect(await target.readAsString(), bodies.last);
      expect(await files(), ['song.txt']);
    });

    test('못 쓰면 false이고 임시 파일을 남기지 않는다', () async {
      // 정본 자리에 폴더가 있으면 rename이 거절된다(권한·잠금 실패의 대역).
      final obstacle = Directory('${tmp.path}/blocked.txt')..createSync();
      expect(
        await writeTextAtomically(
          File(obstacle.path),
          '내용',
          ioRetryDelay: const Duration(milliseconds: 1),
        ),
        isFalse,
      );
      expect(await files(), isEmpty);
    });
  });
}
