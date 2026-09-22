// file: test/services/daily_goal_store_test.dart
//
// 일일 목표 기록(daily_goals.json) 저장의 데이터 안전.
//
// 만든 계기: 연습이 끝날 때 기다리지 않고 도는 자동 체크와 손으로 누른 체크가 겹칠 수
// 있는데, 정본을 곧바로 덮어썼고 못 읽은 파일을 빈 기록으로 읽었다 — 그 다음 체크가
// 연속일 기록을 통째로 지운다.
//
// 실제 파일 IO를 기다리므로 전부 plain test()다(testWidgets의 가짜 시계 금지).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/vocal_routine.dart';
import 'package:singpromfter_app/services/atomic_json_file.dart';
import 'package:singpromfter_app/services/daily_goal_service.dart';

DailyGoalLog log(int day, {Set<String> done = const {}}) => DailyGoalLog(
  date: dateKey(DateTime(2026, 9, day)),
  routineId: VocalRoutines.short.id,
  completedStepIds: done,
);

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sp_daily_goals_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  DailyGoalStore newStore() => DailyGoalStore(
    baseDirBuilder: () async => tmp,
    ioRetryDelay: const Duration(milliseconds: 1),
  );

  File goalsFile() => File('${tmp.path}/data/daily_goals.json');
  File backupFile() => File('${goalsFile().path}.bak');

  /// 디스크의 정본을 직접 읽어 날짜 목록으로 돌려준다(JSON이 깨졌으면 여기서 실패).
  Future<List<String>> datesOnDisk() async {
    final decoded =
        jsonDecode(await goalsFile().readAsString()) as Map<String, dynamic>;
    return [
      for (final l in decoded['logs'] as List)
        (l as Map<String, dynamic>)['date'] as String,
    ];
  }

  Future<List<String>> dataFiles() async => [
    await for (final e in Directory('${tmp.path}/data').list())
      if (e is File) e.uri.pathSegments.last,
  ]..sort();

  Future<void> seed(String body) async {
    await Directory('${tmp.path}/data').create(recursive: true);
    await goalsFile().writeAsString(body);
  }

  group('decodeDailyGoals — 「못 읽음」과 「빈 기록」을 가른다', () {
    test('정상 본문·빈 logs는 맵으로, 나머지는 null', () {
      final body = encodeDailyGoals({
        log(1).date: log(1, done: {'warmup'}),
      });
      expect(decodeDailyGoals(body)!.values.single.completedStepIds, {
        'warmup',
      });
      expect(decodeDailyGoals(encodeDailyGoals(const {})), isEmpty);
      expect(decodeDailyGoals(''), isNull);
      expect(decodeDailyGoals(body.substring(0, body.length ~/ 2)), isNull);
      expect(decodeDailyGoals('[]'), isNull);
    });

    test('상위 버전은 null(깨짐)이 아니라 예외다 — 헬퍼가 「읽기 거부」로 분류한다', () {
      // null이면 헬퍼가 첫 체크에서 .corrupt-로 옮기고 구버전 봉투로 갈아 끼운다.
      expect(
        () => decodeDailyGoals('{"schemaVersion":99,"logs":[]}'),
        throwsA(isA<AtomicSchemaException>()),
      );
    });

    test('파일 형식은 그대로다 — 봉투, 들여쓰기 2칸', () {
      expect(
        encodeDailyGoals({log(1).date: log(1)}),
        startsWith('{\n  "schemaVersion": 1,\n  "logs": [\n'),
      );
    });
  });

  group('겹쳐 불린 체크가 섞이지 않는다', () {
    test('put 40회를 기다리지 않고 불러도 JSON 유효, 날짜·내용 일치', () async {
      final service = DailyGoalService(store: newStore());
      await service.load();

      // 자동 체크(unawaited)와 손으로 누른 체크가 겹치는 모양.
      final results = <Future<bool>>[];
      for (var day = 1; day <= 20; day++) {
        results.add(service.put(log(day)));
        results.add(service.put(log(day, done: {'step$day'})));
      }
      expect(await Future.wait(results), everyElement(isTrue));

      expect((await datesOnDisk()).length, 20);
      expect((await dataFiles()).where((f) => f.endsWith('.tmp')), isEmpty);

      final reopened = DailyGoalService(store: newStore());
      await reopened.load();
      expect(reopened.loadState, AtomicLoadState.ok);
      expect(reopened.logs.length, 20);
      for (var day = 1; day <= 20; day++) {
        expect(reopened.logs[log(day).date]!.completedStepIds, {'step$day'});
      }
    });
  });

  group('정본을 못 읽어도 기록이 증발하지 않는다', () {
    test('깨진 정본 + 멀쩡한 .bak → .bak을 읽는다', () async {
      final store = newStore();
      await store.save({log(1).date: log(1)});
      await store.save({
        log(1).date: log(1),
        log(2).date: log(2),
      }); // .bak = [1일]
      await goalsFile().writeAsString('{"schemaVersion":1,"logs":[{"date":"20');

      final fresh = newStore();
      expect((await fresh.load()).keys, [log(1).date]);
      expect(fresh.lastLoadState, AtomicLoadState.recoveredFromBackup);
    });

    test('🔴 못 읽은 정본을 빈 기록으로는 덮지 않는다', () async {
      const broken = '{"schemaVersion":1,"logs":[{"date":"2026-09-0';
      await seed(broken);
      final store = newStore();
      expect(await store.load(), isEmpty);
      expect(store.lastLoadState, AtomicLoadState.unreadable);
      expect(await store.save(const {}), isFalse);
      expect(await goalsFile().readAsString(), broken);
      expect(await dataFiles(), ['daily_goals.json']);
    });

    test('못 읽은 정본에 체크하면 깨진 원본이 .corrupt로 옆에 남는다', () async {
      const broken = '{"schemaVersion":1,"logs":[{"date":"2026-09-0';
      await seed(broken);
      final service = DailyGoalService(store: newStore());
      await service.load();
      expect(await service.put(log(22)), isTrue);

      expect(await datesOnDisk(), [log(22).date]);
      final corrupt = (await dataFiles()).where(
        (f) => f.startsWith('daily_goals.json.corrupt-'),
      );
      expect(corrupt.length, 1);
      expect(
        await File('${tmp.path}/data/${corrupt.single}').readAsString(),
        broken,
      );
      expect(await backupFile().exists(), isFalse);
    });

    test('🔴 상위 버전 파일(구버전 exe로 되돌아감)은 비어 있지 않은 체크로도 덮지 않는다', () async {
      // 예전에는 「깨짐」으로 봐서 첫 체크가 정본을 .corrupt-로 옮기고 구버전 봉투로
      // 갈아 끼웠다 — 새 빌드로 올라가면 연속일 기록이 빠져 있다.
      const newer = '{"schemaVersion":99,"logs":[{"date":"2099-01-01"}]}';
      await seed(newer);
      final service = DailyGoalService(store: newStore());
      await service.load();
      expect(service.loadState, AtomicLoadState.unreadable);

      expect(await service.put(log(22)), isFalse);
      expect(await goalsFile().readAsString(), newer);
      expect(await dataFiles(), ['daily_goals.json']);
    });
  });

  group('못 열고 시작한 기록 (Windows 잠금)', () {
    final skip = Platform.isWindows ? null : 'Windows 전용(강제 잠금)';

    test('🔴 부팅 때 정본이 안 열렸어도, 이후 체크 두 번에 지난 날짜가 사라지지 않는다', () async {
      await seed(
        encodeDailyGoals({for (var d = 1; d <= 15; d++) log(d).date: log(d)}),
      );
      final lock = await goalsFile().open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);

      final service = DailyGoalService(store: newStore());
      await service.load();
      expect(service.logs, isEmpty);
      await lock.unlock();
      await lock.close();

      expect(await service.put(log(22)), isTrue);
      expect(await service.put(log(22, done: {'warmup'})), isTrue);

      final dates = await datesOnDisk();
      expect(dates.length, 16);
      expect(dates, containsAll([log(1).date, log(15).date, log(22).date]));
    }, skip: skip);
  });
}
