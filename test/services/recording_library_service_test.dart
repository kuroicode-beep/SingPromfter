// file: test/services/recording_library_service_test.dart
//
// 녹음 목록 저장의 데이터 안전 — 직렬 쓰기·원자 교체·백업 폴백.
//
// 만든 계기: save()가 정본을 곧바로 덮어쓰던 시절, 녹음 직후의 add()와 기다리지
// 않고 도는 반주 컷의 update()가 겹치면 JSON이 깨졌고, load()가 그걸 빈 목록으로
// 읽어 다음 저장이 **목록 전체를 지웠다.** 그 길을 하나씩 막아 둔다.
//
// 실제 파일 IO를 기다리므로 전부 plain test()다(testWidgets의 가짜 시계 금지).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/recording_take.dart';
import 'package:singpromfter_app/services/recording_library_service.dart';

RecordingTake take(int i, {String comment = ''}) => RecordingTake(
  id: 't$i',
  songId: 's1',
  songTitle: '봄날',
  fileName: 't$i.wav',
  recordedAt: DateTime(2026, 9, 22, 10, 0, i),
  durationMs: 2000 + i,
  songPositionMs: 1000 * i,
  comment: comment,
  peakDbfs: -20.0 - i,
);

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sp_recording_store_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  RecordingStore newStore() => RecordingStore(
    baseDirBuilder: () async => tmp,
    ioRetryDelay: const Duration(milliseconds: 1),
  );

  File indexFile() => File('${tmp.path}/data/recordings.json');
  File backupFile() => File('${indexFile().path}.bak');

  /// 디스크의 정본을 직접 읽어 테이크 id 목록으로 돌려준다(JSON이 깨졌으면 여기서 실패).
  Future<List<String>> idsOnDisk() async {
    final decoded =
        jsonDecode(await indexFile().readAsString()) as Map<String, dynamic>;
    return [
      for (final t in decoded['takes'] as List)
        (t as Map<String, dynamic>)['id'] as String,
    ];
  }

  /// 데이터 폴더에 남은 파일 이름들.
  Future<List<String>> dataFiles() async => [
    await for (final e in Directory('${tmp.path}/data').list())
      if (e is File) e.uri.pathSegments.last,
  ];

  /// 지금 열 수 있으면 본문을, 없거나 잠깐 거절되면 null을 준다.
  Future<String?> readIfOpenable(File file) async {
    try {
      return await file.readAsString();
    } on FileSystemException {
      return null;
    }
  }

  Future<void> seedIndex(String body) async {
    await Directory('${tmp.path}/data').create(recursive: true);
    await indexFile().writeAsString(body);
  }

  group('decodeRecordingIndex — 「못 읽음」과 「빈 목록」을 가른다', () {
    test('정상 본문은 목록으로, 빈 takes는 빈 목록([])으로 읽는다', () {
      final body = encodeRecordingIndex([take(1), take(2)]);
      expect(decodeRecordingIndex(body)!.map((t) => t.id), ['t1', 't2']);
      expect(decodeRecordingIndex(encodeRecordingIndex(const [])), isEmpty);
    });

    test('빈 파일은 빈 목록이 아니라 못 읽음(null)이다', () {
      // 쓰다 죽은 파일이 남기는 모양이 길이 0이다. 빈 목록으로 읽으면 다음 저장이
      // 목록 전체를 지운다.
      expect(decodeRecordingIndex(''), isNull);
      expect(decodeRecordingIndex('  \n'), isNull);
    });

    test('잘린 JSON·엉뚱한 모양·높은 버전은 전부 null', () {
      final body = encodeRecordingIndex([take(1), take(2)]);
      expect(decodeRecordingIndex(body.substring(0, body.length ~/ 2)), isNull);
      expect(decodeRecordingIndex('[]'), isNull);
      expect(decodeRecordingIndex('{"schemaVersion":2,"takes":"x"}'), isNull);
      expect(decodeRecordingIndex('{"schemaVersion":99,"takes":[]}'), isNull);
    });

    test('두 쓰기가 한 파일에 섞인 모양(실사고 재현)은 null', () {
      final a = encodeRecordingIndex([take(1)]);
      final b = encodeRecordingIndex([take(1), take(2)]);
      // 긴 본문 위에 짧은 본문이 덮이다 만 상태.
      final mixed = a + b.substring(a.length);
      expect(decodeRecordingIndex(mixed), isNull);
    });

    test('BOM이 붙은 파일도 읽는다(밖에서 손본 파일)', () {
      final body = '\u{FEFF}${encodeRecordingIndex([take(1)])}';
      expect(decodeRecordingIndex(body)!.single.id, 't1');
    });

    test('peakDbfs까지 왕복한다', () {
      final back = decodeRecordingIndex(encodeRecordingIndex([take(3)]))!;
      expect(back.single.peakDbfs, -23.0);
    });
  });

  group('RecordingStore.save — 원자 교체와 백업', () {
    test('저장하면 읽히는 JSON이 남고 임시 파일은 남지 않는다', () async {
      final store = newStore();
      expect(await store.save([take(1), take(2)]), isTrue);

      expect(await idsOnDisk(), ['t1', 't2']);
      expect(await dataFiles(), ['recordings.json']);
    });

    test('두 번째 저장부터 직전 정본이 .bak에 남는다', () async {
      final store = newStore();
      await store.save([take(1)]);
      await store.save([take(1), take(2)]);

      expect(await idsOnDisk(), ['t1', 't2']);
      final bak = decodeRecordingIndex(await backupFile().readAsString())!;
      expect(bak.map((t) => t.id), ['t1']);
      expect((await dataFiles())..sort(), [
        'recordings.json',
        'recordings.json.bak',
      ]);
    });

    test('기다리지 않고 50번 연달아 불러도 마지막 목록이 온전히 남는다', () async {
      final store = newStore();
      final results = <Future<bool>>[];
      for (var n = 1; n <= 50; n++) {
        results.add(store.save([for (var i = 0; i < n; i++) take(i)]));
      }
      expect(await Future.wait(results), everyElement(isTrue));

      expect((await idsOnDisk()).length, 50);
      expect((await dataFiles()).where((f) => f.endsWith('.tmp')), isEmpty);
    });

    test('load()는 줄에 선 쓰기가 끝난 뒤에 읽는다', () async {
      final store = newStore();
      unawaited(store.save([take(1), take(2), take(3)]));
      expect((await store.load()).map((t) => t.id), ['t1', 't2', 't3']);
    });
  });

  group('RecordingLibraryService — 동시에 불린 add/update가 섞이지 않는다', () {
    test('add/update 50회 교차 → JSON 유효, 항목 수·내용 일치', () async {
      final library = RecordingLibraryService(store: newStore());
      await library.load();

      // 녹음 고정의 실제 모양: 조각 저장(add) 직후에 기다리지 않는 반주 컷이
      // update를 부른다. 하나도 기다리지 않고 50번을 겹쳐 부른다.
      final results = <Future<bool>>[];
      for (var i = 0; i < 25; i++) {
        results.add(library.add(take(i)));
        results.add(library.update(take(i, comment: '반주 $i')));
      }
      expect(results.length, 50);
      expect(await Future.wait(results), everyElement(isTrue));

      // 디스크의 정본이 그대로 읽힌다(깨졌으면 jsonDecode에서 터진다).
      expect((await idsOnDisk()).toSet(), {for (var i = 0; i < 25; i++) 't$i'});
      expect((await dataFiles()).where((f) => f.endsWith('.tmp')), isEmpty);

      // 새로 켠 앱이 같은 목록을 본다.
      final reopened = RecordingLibraryService(store: newStore());
      await reopened.load();
      expect(reopened.loadState, RecordingIndexState.ok);
      expect(reopened.takes.length, 25);
      for (final t in reopened.takes) {
        expect(t.comment, '반주 ${t.id.substring(1)}', reason: '${t.id}의 update');
      }
    });

    test('앞의 쓰기가 도는 중에 다음 호출이 들어와도 정본이 깨지지 않는다', () async {
      final library = RecordingLibraryService(store: newStore());
      await library.load();

      // 호출 사이마다 이벤트 루프에 양보한다 — 앞의 쓰기가 디스크 IO를 기다리는
      // 바로 그 틈에 다음 add/update가 들어온다(예전 코드가 파일을 섞던 모양).
      final results = <Future<bool>>[];
      for (var i = 0; i < 25; i++) {
        results.add(library.add(take(i)));
        await Future<void>.delayed(Duration.zero);
        results.add(library.update(take(i, comment: '반주 $i')));
        await Future<void>.delayed(Duration.zero);
        // 도는 중간에도 정본은 언제나 읽히는 JSON이다(없거나, 온전하거나).
        // 교체 순간에는 Windows가 열기를 잠깐 거절한다(errno 32) — 그건 깨진 게
        // 아니므로 건너뛴다. 보려는 것은 「읽혔는데 반쪽짜리」인 경우다.
        final raw = await readIfOpenable(indexFile());
        if (raw != null) {
          expect(
            decodeRecordingIndex(raw),
            isNotNull,
            reason: '$i번째 호출 뒤의 정본이 깨져 있다',
          );
        }
      }
      expect(await Future.wait(results), everyElement(isTrue));

      final onDisk = decodeRecordingIndex(await indexFile().readAsString())!;
      expect(onDisk.length, 25);
      expect(
        onDisk.every((t) => t.comment == '반주 ${t.id.substring(1)}'),
        isTrue,
      );
      expect((await dataFiles()).where((f) => f.endsWith('.tmp')), isEmpty);
    });

    test('add·update·remove·removeRecordOnly를 섞어도 마지막 상태가 남는다', () async {
      final library = RecordingLibraryService(store: newStore());
      await library.load();

      final results = <Future<bool>>[
        for (var i = 0; i < 10; i++) library.add(take(i)),
        library.update(take(3, comment: '수정')),
        library.removeRecordOnly(take(4)),
        library.remove(take(5)),
        library.add(take(10)),
      ];
      expect(await Future.wait(results), everyElement(isTrue));

      final expected = {for (var i = 0; i <= 10; i++) 't$i'}
        ..removeAll({'t4', 't5'});
      expect((await idsOnDisk()).toSet(), expected);

      final reopened = RecordingLibraryService(store: newStore());
      await reopened.load();
      expect(reopened.takes.firstWhere((t) => t.id == 't3').comment, '수정');
    });
  });

  group('load — 정본을 못 읽으면 .bak에서 되살린다', () {
    test('깨진 정본 + 멀쩡한 .bak → .bak을 읽는다', () async {
      final store = newStore();
      await store.save([take(1)]);
      await store.save([take(1), take(2)]); // .bak = [t1]
      await indexFile().writeAsString('{"schemaVersion":2,"takes":[{"id":"t1"');

      final fresh = newStore();
      final loaded = await fresh.load();
      expect(loaded.map((t) => t.id), ['t1']);
      expect(fresh.lastLoadState, RecordingIndexState.recoveredFromBackup);
    });

    test('길이 0인 정본(쓰다 죽은 모양) + 멀쩡한 .bak → .bak을 읽는다', () async {
      final store = newStore();
      await store.save([take(1), take(2)]);
      await store.save([take(1), take(2), take(3)]); // .bak = [t1, t2]
      await indexFile().writeAsString('');

      final fresh = newStore();
      expect((await fresh.load()).map((t) => t.id), ['t1', 't2']);
      expect(fresh.lastLoadState, RecordingIndexState.recoveredFromBackup);
    });

    test('정본이 멀쩡하면 .bak은 보지 않는다', () async {
      final store = newStore();
      await store.save([take(1)]);
      await store.save([take(1), take(2)]);

      final fresh = newStore();
      expect((await fresh.load()).length, 2);
      expect(fresh.lastLoadState, RecordingIndexState.ok);
    });

    test('아무 파일도 없는 첫 실행은 빈 목록이고 정상이다', () async {
      final store = newStore();
      expect(await store.load(), isEmpty);
      expect(store.lastLoadState, RecordingIndexState.ok);
    });

    test('정본도 백업도 못 읽으면 빈 목록이지만 unreadable로 선다', () async {
      await seedIndex('이건 JSON이 아니다');
      final store = newStore();
      expect(await store.load(), isEmpty);
      expect(store.lastLoadState, RecordingIndexState.unreadable);
    });
  });

  group('잠깐 못 여는 정본은 깨진 파일이 아니다 (Windows 잠금)', () {
    // Windows의 배타 잠금은 다른 핸들의 읽기를 거절한다 — 백신·동기화·정본 교체
    // 순간에 생기는 「지금은 못 엶」의 대역이다. 다른 OS의 잠금은 권고라 막지 않는다.
    final skip = Platform.isWindows ? null : 'Windows 전용(강제 잠금)';

    test('읽는 도중에 풀리면 다시 해 봐서 정본을 그대로 읽는다', () async {
      final store = newStore();
      await store.save([take(1), take(2)]);
      await store.save([take(1), take(2), take(3)]); // .bak = [t1, t2]

      final lock = await indexFile().open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      Timer(const Duration(milliseconds: 5), () async {
        await lock.unlock();
        await lock.close();
      });

      final fresh = RecordingStore(
        baseDirBuilder: () async => tmp,
        ioRetryDelay: const Duration(milliseconds: 4),
      );
      // 한 박자 낡은 .bak([t1, t2])이 아니라 정본([t1, t2, t3])이어야 한다.
      expect((await fresh.load()).map((t) => t.id), ['t1', 't2', 't3']);
      expect(fresh.lastLoadState, RecordingIndexState.ok);
    }, skip: skip);

    test('끝내 못 열어도 정본을 깨진 파일로 취급하지 않는다', () async {
      final store = newStore();
      await store.save([take(1), take(2)]);
      await store.save([take(1), take(2), take(3)]); // .bak = [t1, t2]

      final lock = await indexFile().open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      final fresh = newStore();
      expect((await fresh.load()).map((t) => t.id), ['t1', 't2']);
      expect(fresh.lastLoadState, RecordingIndexState.recoveredFromBackup);
      // 잠긴 동안의 저장은 되든 안 되든 상관없다 — 보려는 것은 부작용이다.
      await fresh.save([take(1), take(2), take(9)]);
      await lock.unlock();
      await lock.close();

      expect(await fresh.save([take(1), take(2), take(9)]), isTrue);
      expect(await idsOnDisk(), ['t1', 't2', 't9']);
      // 내용을 본 적 없는 파일을 「깨짐」으로 옆에 치우지 않았다.
      expect(
        (await dataFiles()).where((f) => f.contains('.corrupt-')),
        isEmpty,
      );
    }, skip: skip);
  });

  group('못 읽고 시작한 목록은 저장 전에 정본을 다시 읽어 합친다 (Windows 잠금)', () {
    final skip = Platform.isWindows ? null : 'Windows 전용(강제 잠금)';

    test('🔴 부팅 때 정본이 잠깐 안 열렸어도, 이후 저장 두 번에 옛 목록이 사라지지 않는다', () async {
      // .bak이 아직 없는 첫 실행(v5.16 직후)의 모양 — 정본만 있다.
      await seedIndex(encodeRecordingIndex([take(1), take(2), take(3)]));
      final lock = await indexFile().open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);

      final library = RecordingLibraryService(store: newStore());
      await library.load();
      expect(library.takes, isEmpty);
      expect(library.loadState, RecordingIndexState.unreadable);
      await lock.unlock();
      await lock.close();

      // 고정 조각 하나(add)와 약 1초 뒤의 반주 컷(update). 예전에는 첫 저장이 옛
      // 목록을 .bak으로 밀고, 둘째 저장이 그 .bak마저 덮어 두 파일에서 다 사라졌다.
      expect(await library.add(take(9)), isTrue);
      expect(await library.update(take(9, comment: '반주 붙음')), isTrue);

      expect((await idsOnDisk()).toSet(), {'t1', 't2', 't3', 't9'});
      expect(library.loadState, RecordingIndexState.ok);
      expect(library.takes.map((t) => t.id).toSet(), {'t1', 't2', 't3', 't9'});
      expect(library.takes.firstWhere((t) => t.id == 't9').comment, '반주 붙음');
      final bak = decodeRecordingIndex(await backupFile().readAsString())!;
      expect(bak.map((t) => t.id).toSet(), containsAll(['t1', 't2', 't3']));
    }, skip: skip);

    test('한 박자 낡은 .bak으로 시작했어도 정본에만 있던 테이크를 되찾는다', () async {
      final store = newStore();
      await store.save([take(1), take(2)]);
      await store.save([take(1), take(2), take(3)]); // .bak = [t1, t2]
      final lock = await indexFile().open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);

      final library = RecordingLibraryService(store: newStore());
      await library.load();
      expect(library.loadState, RecordingIndexState.recoveredFromBackup);
      expect(library.takes.map((t) => t.id).toSet(), {'t1', 't2'});
      await lock.unlock();
      await lock.close();

      expect(await library.add(take(9)), isTrue);
      expect((await idsOnDisk()).toSet(), {'t1', 't2', 't3', 't9'});
    }, skip: skip);

    test('못 읽은 동안 지운 테이크는 되읽어도 되살아나지 않는다', () async {
      final store = newStore();
      await store.save([take(1), take(2)]);
      await store.save([take(1), take(2), take(3)]); // .bak = [t1, t2]
      final lock = await indexFile().open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);

      final library = RecordingLibraryService(store: newStore());
      await library.load();
      // 잠긴 동안의 삭제 — 저장은 실패하지만(정본을 못 연다) 메모리에서는 빠진다.
      expect(await library.removeRecordOnly(take(2)), isFalse);
      await lock.unlock();
      await lock.close();

      expect(await library.add(take(9)), isTrue);
      expect((await idsOnDisk()).toSet(), {'t1', 't3', 't9'});
    }, skip: skip);

    test('🔴 지금 못 여는 정본은 목록이 있어도 덮지 않는다(사본을 뜰 수 없다)', () async {
      await seedIndex(encodeRecordingIndex([take(1), take(2), take(3)]));
      final before = await indexFile().readAsString();
      final lock = await indexFile().open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);

      final messages = <String>[];
      final library = RecordingLibraryService(store: newStore())
        ..onSaveFailed = messages.add;
      await library.load();
      expect(await library.add(take(9)), isFalse);
      expect(messages, [kRecordingSaveFailedMessage]);
      await lock.unlock();
      await lock.close();

      expect(await indexFile().readAsString(), before);
      expect((await dataFiles()).where((f) => f.endsWith('.tmp')), isEmpty);
      // 메모리의 새 테이크는 다음 저장에 옛 목록과 함께 실린다.
      expect(await library.update(take(9, comment: '다시')), isTrue);
      expect((await idsOnDisk()).toSet(), {'t1', 't2', 't3', 't9'});
    }, skip: skip);
  });

  group('파싱 실패가 다음 저장에서 데이터 손실로 이어지지 않는다', () {
    test('깨진 정본을 .bak으로 되살린 뒤 저장해도 백업·깨진 원본이 다 남는다', () async {
      final store = newStore();
      await store.save([take(1), take(2)]);
      await store.save([take(1), take(2), take(3)]); // .bak = [t1, t2]
      const broken = '{"schemaVersion":2,"takes":[{"id":"t1"},{"id":';
      await indexFile().writeAsString(broken);

      final library = RecordingLibraryService(store: newStore());
      await library.load();
      expect(library.takes.length, 2, reason: '.bak에서 되살린 목록');
      expect(await library.add(take(9)), isTrue);

      // 새 정본 = 되살린 목록 + 새 테이크. 빈 목록에서 시작하지 않았다.
      expect((await idsOnDisk()).toSet(), {'t1', 't2', 't9'});
      // 🔴 멀쩡한 백업을 깨진 정본으로 덮지 않았다.
      final bak = decodeRecordingIndex(await backupFile().readAsString())!;
      expect(bak.map((t) => t.id), ['t1', 't2']);
      // 깨진 원본은 손으로 되살릴 수 있게 옆에 남는다.
      final corrupt = (await dataFiles()).where(
        (f) => f.startsWith('recordings.json.corrupt-'),
      );
      expect(corrupt.length, 1);
      expect(
        await File('${tmp.path}/data/${corrupt.single}').readAsString(),
        broken,
      );
    });

    test('백업도 없을 때: 새 테이크는 저장되고 깨진 원본은 옆에 남는다', () async {
      const broken = '{"schemaVersion":2,"takes":[{"id":"t1","songId":"s1"';
      await seedIndex(broken);

      final library = RecordingLibraryService(store: newStore());
      await library.load();
      expect(library.takes, isEmpty);
      expect(library.loadState, RecordingIndexState.unreadable);
      expect(await library.add(take(7)), isTrue);

      expect(await idsOnDisk(), ['t7']);
      final corrupt = (await dataFiles()).where(
        (f) => f.startsWith('recordings.json.corrupt-'),
      );
      expect(corrupt.length, 1);
      expect(
        await File('${tmp.path}/data/${corrupt.single}').readAsString(),
        broken,
      );
      // 깨진 정본이 백업 자리로 들어가지도 않았다.
      expect(await backupFile().exists(), isFalse);
    });

    test('🔴 못 읽은 정본을 빈 목록으로는 덮지 않는다', () async {
      const broken = '{"schemaVersion":2,"takes":[{"id":"t1"';
      await seedIndex(broken);

      final store = newStore();
      expect(await store.load(), isEmpty);
      expect(await store.save(const []), isFalse);

      expect(await indexFile().readAsString(), broken);
      expect(await dataFiles(), ['recordings.json']);
    });

    test('버전이 높은 파일도 빈 목록으로 덮이지 않는다(옛 앱으로 되돌아간 경우)', () async {
      const newer = '{"schemaVersion":99,"takes":[{"id":"future"}]}';
      await seedIndex(newer);

      final store = newStore();
      expect(await store.load(), isEmpty);
      expect(await store.save(const []), isFalse);
      expect(await indexFile().readAsString(), newer);
    });
  });

  group('저장 실패를 삼키지 않는다', () {
    test('정본을 못 바꾸면 false + onSaveFailed, 고치면 다음 저장에 함께 실린다', () async {
      // 정본 자리에 폴더가 있으면 rename이 거절된다(권한·잠금 실패의 대역).
      final obstacle = Directory(indexFile().path);
      await obstacle.create(recursive: true);

      final messages = <String>[];
      final library = RecordingLibraryService(store: newStore())
        ..onSaveFailed = messages.add;
      await library.load();

      expect(await library.add(take(1)), isFalse);
      expect(messages, [kRecordingSaveFailedMessage]);
      // 메모리의 목록은 그대로다 — 방금 녹음이 화면에서 사라지지 않는다.
      expect(library.takes.single.id, 't1');
      // 실패한 임시 파일을 남기지 않는다.
      expect((await dataFiles()).where((f) => f.endsWith('.tmp')), isEmpty);

      await obstacle.delete();
      expect(await library.add(take(2)), isTrue);
      expect(messages.length, 1);
      expect((await idsOnDisk()).toSet(), {'t1', 't2'});
    });

    test('앞 차례가 실패하면 줄에 서 있던 다음 차례가 다시 해 본다', () async {
      // 첫 쓰기에서만 디스크가 거절한다(일시적인 잠금의 대역).
      var failuresLeft = 1;
      final store = RecordingStore(
        baseDirBuilder: () async {
          if (failuresLeft-- > 0) throw const FileSystemException('잠김');
          return tmp;
        },
      );

      // 둘 다 기다리지 않고 부른다 — 첫 차례가 최신 목록을 들고 나갔다가 실패한다.
      final first = store.save([take(1)]);
      final second = store.save([take(1), take(2)]);
      expect(await first, isFalse);
      // 둘째 차례가 「앞에서 이미 썼다」고 넘어가면 안 된다.
      expect(await second, isTrue);
      expect(await idsOnDisk(), ['t1', 't2']);
    });
  });
}
