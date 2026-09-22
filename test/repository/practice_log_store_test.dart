// file: test/repository/practice_log_store_test.dart
//
// 연습 기록(practice_log.json) 저장의 데이터 안전.
//
// 만든 계기: 이 파일은 쓰는 쪽이 셋이다(화면의 연습 기록·백업 가져오기·폰 동기화).
// 화면은 부팅 때 한 번 읽은 목록을 통째로 저장했으므로, 그사이 폰이 올린 세션과
// 백업에서 합친 세션을 **다음 연습 기록이 덮었다**(확정된 논리 유실). 두 쓰기가 한
// 파일에서 섞이면 JSON도 깨졌고, 깨진 파일은 빈 목록으로 읽혀 전체가 지워졌다.
//
// 실제 파일 IO를 기다리므로 전부 plain test()다(testWidgets의 가짜 시계 금지).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/controllers/playback_controller.dart';
import 'package:singpromfter_app/models/practice_session.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/repository/practice_log_store.dart';
import 'package:singpromfter_app/services/atomic_json_file.dart';
import 'package:singpromfter_app/services/practice_log_service.dart';

PracticeSession session(
  String id, {
  String songId = 's1',
  int durationMs = 60000,
}) => PracticeSession(
  id: id,
  songId: songId,
  songTitle: '봄날',
  startedAt: DateTime(2026, 9, 22, 10),
  durationMs: durationMs,
);

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sp_practice_log_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  PracticeLogStore newStore() => PracticeLogStore(
    baseDirBuilder: () async => tmp,
    ioRetryDelay: const Duration(milliseconds: 1),
  );

  File logFile() => File('${tmp.path}/data/practice_log.json');
  File backupFile() => File('${logFile().path}.bak');

  /// 디스크의 정본을 직접 읽어 세션 id 목록으로 돌려준다(JSON이 깨졌으면 여기서 실패).
  Future<List<String>> idsOnDisk() async {
    final decoded =
        jsonDecode(await logFile().readAsString()) as Map<String, dynamic>;
    return [
      for (final s in decoded['sessions'] as List)
        (s as Map<String, dynamic>)['id'] as String,
    ];
  }

  Future<List<String>> dataFiles() async => [
    await for (final e in Directory('${tmp.path}/data').list())
      if (e is File) e.uri.pathSegments.last,
  ]..sort();

  Future<void> seed(String body) async {
    await Directory('${tmp.path}/data').create(recursive: true);
    await logFile().writeAsString(body);
  }

  Song song(String id) => Song(
    id: id,
    title: '봄날',
    artist: '',
    lyricsPath: '',
    lyricsText: '',
    backingTracks: const [],
    createdAt: DateTime(2026, 9, 1),
    updatedAt: DateTime(2026, 9, 1),
  );

  group('mergePracticeSessions (순수 함수)', () {
    test('모르는 id는 뒤에 붙이고, 아는 id는 건드리지 않는다', () {
      final base = [session('a'), session('b')];
      final merged = mergePracticeSessions(base, [
        session('b', durationMs: 1),
        session('c'),
      ]);
      expect(merged.map((s) => s.id), ['a', 'b', 'c']);
      expect(merged[1].durationMs, 60000);
    });

    test('incomingWins면 같은 id를 그 자리에서 갈아끼운다', () {
      final merged = mergePracticeSessions(
        [session('a'), session('b')],
        [session('a', durationMs: 90000)],
        incomingWins: true,
      );
      expect(merged.map((s) => s.id), ['a', 'b']);
      expect(merged.first.durationMs, 90000);
    });

    test('id가 빈 세션은 버리고, 바뀐 게 없으면 받은 목록 그 객체를 돌려준다', () {
      final base = [session('a')];
      expect(
        identical(mergePracticeSessions(base, [session('')]), base),
        isTrue,
      );
      expect(
        identical(mergePracticeSessions(base, [session('a')]), base),
        isTrue,
      );
    });
  });

  group('decodePracticeLog — 「못 읽음」과 「빈 목록」을 가른다', () {
    test('정상 본문·빈 sessions는 목록으로, 나머지는 null', () {
      final body = encodePracticeLog([session('a')]);
      expect(decodePracticeLog(body)!.single.id, 'a');
      expect(decodePracticeLog(encodePracticeLog(const [])), isEmpty);
      expect(decodePracticeLog(''), isNull);
      expect(decodePracticeLog(body.substring(0, body.length ~/ 2)), isNull);
      expect(decodePracticeLog('[]'), isNull);
    });

    test('상위 버전은 null(깨짐)이 아니라 예외다 — 헬퍼가 「읽기 거부」로 분류한다', () {
      // null이면 헬퍼가 첫 저장에서 .corrupt-로 옮기고 구버전 봉투로 갈아 끼운다.
      expect(
        () => decodePracticeLog('{"schemaVersion":99,"sessions":[]}'),
        throwsA(isA<AtomicSchemaException>()),
      );
    });

    test('파일 형식은 그대로다 — 봉투, 들여쓰기 2칸', () {
      expect(
        encodePracticeLog([session('a')]),
        startsWith('{\n  "schemaVersion": 1,\n  "sessions": [\n'),
      );
    });
  });

  group('쓰는 쪽이 셋이어도 서로의 세션을 잃지 않는다', () {
    test('세 인스턴스가 기다리지 않고 60번 교차로 합쳐도 전부 남는다', () async {
      // 화면·백업 병합·폰 동기화가 각자 저장소 인스턴스를 들고 있다.
      final stores = [newStore(), newStore(), newStore()];
      final results = <Future<List<PracticeSession>?>>[];
      for (var n = 0; n < 60; n++) {
        results.add(stores[n % 3].merge([session('p$n')]));
      }
      expect(await Future.wait(results), everyElement(isNotNull));

      expect((await idsOnDisk()).toSet(), {for (var n = 0; n < 60; n++) 'p$n'});
      expect((await dataFiles()).where((f) => f.endsWith('.tmp')), isEmpty);
      final reopened = newStore();
      expect((await reopened.load()).length, 60);
      expect(reopened.lastLoadState, AtomicLoadState.ok);
    });

    test('🔴 폰이 올린 세션을 화면의 다음 연습 기록이 덮지 않는다', () async {
      final service = PracticeLogService(store: newStore());
      await service.load();
      await service.record(
        snapshot: PlaybackSnapshot(song: song('s1')),
        played: const Duration(minutes: 2),
        now: DateTime(2026, 9, 22, 10),
      );

      // 그사이 폰 동기화(다른 인스턴스)가 세션 두 개를 디스크에 합쳤다.
      await newStore().merge([session('phone1'), session('phone2')]);

      // 화면은 그걸 모른 채 다른 곡의 연습을 기록한다. 예전에는 메모리 목록을 통째로
      // 써서 phone1·phone2가 사라졌다.
      await service.record(
        snapshot: PlaybackSnapshot(song: song('s2')),
        played: const Duration(minutes: 3),
        now: DateTime(2026, 9, 22, 11),
      );

      final onDisk = await idsOnDisk();
      expect(onDisk, containsAll(['phone1', 'phone2']));
      expect(onDisk.length, 4);
      // 화면의 목록도 디스크에 합쳐진 세션을 되받는다.
      expect(
        service.sessions.map((s) => s.id),
        containsAll(['phone1', 'phone2']),
      );
    });

    test('직전 세션에 이어 붙인 시간은 메모리 쪽이 이긴다', () async {
      final service = PracticeLogService(store: newStore());
      await service.load();
      final start = DateTime(2026, 9, 22, 10);
      await service.record(
        snapshot: PlaybackSnapshot(song: song('s1')),
        played: const Duration(minutes: 1),
        now: start,
      );
      // 60초 안에 같은 곡을 다시 — 새 세션이 아니라 직전 세션에 합친다.
      await service.record(
        snapshot: PlaybackSnapshot(song: song('s1')),
        played: const Duration(minutes: 2),
        now: start.add(const Duration(seconds: 30)),
      );

      final loaded = await newStore().load();
      expect(loaded.length, 1);
      expect(
        loaded.single.durationMs,
        const Duration(minutes: 3).inMilliseconds,
      );
    });
  });

  group('정본을 못 읽어도 기록이 증발하지 않는다', () {
    test('깨진 정본 + 멀쩡한 .bak → .bak을 읽는다', () async {
      final store = newStore();
      await store.merge([session('a')]);
      await store.merge([session('b')]); // .bak = [a]
      await logFile().writeAsString('{"schemaVersion":1,"sessions":[{"id":"a"');

      final fresh = newStore();
      expect((await fresh.load()).map((s) => s.id), ['a']);
      expect(fresh.lastLoadState, AtomicLoadState.recoveredFromBackup);
    });

    test('깨진 정본에 합치면 .bak에서 이어 가고, 깨진 원본은 옆에 남는다', () async {
      final store = newStore();
      await store.merge([session('a')]);
      await store.merge([session('b')]); // .bak = [a]
      const broken = '{"schemaVersion":1,"sessions":[{"id":"a"},{"id":';
      await logFile().writeAsString(broken);

      final merged = await newStore().merge([session('c')]);
      expect(merged!.map((s) => s.id), ['a', 'c']);
      expect(await idsOnDisk(), ['a', 'c']);
      // 멀쩡한 백업을 깨진 정본으로 덮지 않았다.
      expect(
        decodePracticeLog(await backupFile().readAsString())!.single.id,
        'a',
      );
      final corrupt = (await dataFiles()).where(
        (f) => f.startsWith('practice_log.json.corrupt-'),
      );
      expect(corrupt.length, 1);
      expect(
        await File('${tmp.path}/data/${corrupt.single}').readAsString(),
        broken,
      );
    });

    test('못 읽은 정본은 빈 목록으로 읽히지만, 합칠 게 없으면 파일을 건드리지 않는다', () async {
      const broken = '이건 JSON이 아니다';
      await seed(broken);
      final store = newStore();
      expect(await store.load(), isEmpty);
      expect(store.lastLoadState, AtomicLoadState.unreadable);
      await store.merge(const []);
      await store.merge([session('')]);
      expect(await logFile().readAsString(), broken);
      expect(await dataFiles(), ['practice_log.json']);
    });

    test('합칠 게 없으면 없는 파일을 만들지도 않는다', () async {
      expect(await newStore().merge(const []), isEmpty);
      expect(await logFile().exists(), isFalse);
    });

    test('🔴 상위 버전 파일(구버전 exe로 되돌아감)은 비어 있지 않은 병합으로도 덮지 않는다', () async {
      // 예전에는 상위 버전을 「깨짐」으로 봐서 첫 record()가 정본을 .corrupt-로 옮기고
      // 구버전 봉투(이번 세션 하나)로 갈아 끼웠다 — 새 빌드로 올라가면 기록이 빠져 있다.
      const newer = '{"schemaVersion":99,"sessions":[{"id":"future"}]}';
      await seed(newer);
      final store = newStore();
      expect(await store.load(), isEmpty);
      expect(store.lastLoadState, AtomicLoadState.unreadable);

      expect(await store.merge([session('a')]), isNull);
      expect(await logFile().readAsString(), newer);
      expect(await dataFiles(), ['practice_log.json']);
    });
  });

  group('지금 못 여는 정본 (Windows 잠금)', () {
    final skip = Platform.isWindows ? null : 'Windows 전용(강제 잠금)';

    test('🔴 잠긴 동안의 기록은 버리지 않고, 풀린 뒤 다음 기록 때 함께 싣는다', () async {
      await seed(encodePracticeLog([session('old1'), session('old2')]));
      final before = await logFile().readAsString();
      final lock = await logFile().open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);

      // 부팅 때 못 열어 빈 목록으로 시작했다.
      final service = PracticeLogService(store: newStore());
      await service.load();
      expect(service.sessions, isEmpty);
      expect(service.loadState, AtomicLoadState.unreadable);

      // 잠긴 동안의 연습 — 디스크에는 못 닿지만 화면에는 남는다.
      expect(
        await service.record(
          snapshot: PlaybackSnapshot(song: song('s1')),
          played: const Duration(minutes: 1),
          now: DateTime(2026, 9, 22, 10),
        ),
        isFalse,
      );
      expect(service.sessions.length, 1);
      await lock.unlock();
      await lock.close();
      expect(await logFile().readAsString(), before);

      // 풀린 뒤의 연습 — 옛 기록 2 + 못 썼던 1 + 이번 1.
      expect(
        await service.record(
          snapshot: PlaybackSnapshot(song: song('s2')),
          played: const Duration(minutes: 1),
          now: DateTime(2026, 9, 22, 11),
        ),
        isTrue,
      );
      final onDisk = await idsOnDisk();
      expect(onDisk.length, 4);
      expect(onDisk, containsAll(['old1', 'old2']));
      expect(service.sessions.length, 4);
    }, skip: skip);
  });
}
