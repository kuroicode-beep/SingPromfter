// file: test/services/playback_copy_service_test.dart
//
// 위치 보정본 서비스 — VBR MP3 반주의 재생용 WAV 사본을 굽고, 찾고, 치운다.
//
// 가짜 ffmpeg 러너로 돈다(실물은 test/real/real_ffmpeg_playback_copy_test.dart).
// 🔴 testWidgets가 아니라 plain test()다 — 실제 파일 IO와 타이머를 기다린다.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singpromfter_app/services/playback_copy_service.dart';
import 'package:singpromfter_app/services/process/process_runner.dart';
import 'package:singpromfter_app/utils/playback_copy_plan.dart';

import '../fakes/fake_mp3.dart';

/// ffmpeg 흉내. `-i`가 있는 start()면 렌더로 치고 마지막 인자(출력)에 WAV 흉내를 쓴다.
/// run()은 도구 찾기(where·-version)에만 쓰인다.
class _FakeFfmpeg implements ProcessRunner {
  /// 렌더로 띄운 호출의 인자(띄운 순서대로).
  final List<List<String>> renders = [];

  /// 렌더의 종료 코드.
  int exitCode = 0;

  /// 종료 전에 출력 파일을 쓰는가(실패해도 반쪽 파일을 남기는 ffmpeg를 흉내낸다).
  bool writesOutput = true;

  /// ffmpeg를 못 찾는 PC를 흉내낸다.
  bool toolMissing = false;

  /// 주면 이 문이 열릴 때까지 렌더가 끝나지 않는다.
  Completer<void>? gate;

  int _running = 0;
  int maxConcurrent = 0;
  int cancelled = 0;

  @override
  JobHandle start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) {
    renders.add(arguments);
    _running += 1;
    if (_running > maxConcurrent) maxConcurrent = _running;
    final lines = StreamController<String>();
    final exit = Completer<int>();
    var wasCancelled = false;
    Future<void>(() async {
      await (gate?.future ?? Future<void>.value());
      if (!wasCancelled && writesOutput) {
        File(arguments.last).writeAsBytesSync(List.filled(200, 7));
      }
      lines.add('size=N/A time=00:00:01.00');
      _running -= 1;
      await lines.close();
      if (!exit.isCompleted) exit.complete(wasCancelled ? -1 : exitCode);
    });
    return JobHandle(
      lines: lines.stream,
      exitCode: exit.future,
      cancel: () {
        wasCancelled = true;
        cancelled += 1;
        final open = gate;
        if (open != null && !open.isCompleted) open.complete();
      },
    );
  }

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    if (toolMissing) {
      return const ProcessOutput(exitCode: 1, stdout: '', stderr: 'nope');
    }
    return const ProcessOutput(exitCode: 0, stdout: 'ffmpeg', stderr: '');
  }
}

/// Documents만(또는 캐시 폴더까지) 임시 폴더로 돌리는 path_provider.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider({required this.documents, this.cache});
  final String documents;
  final String? cache;

  @override
  Future<String?> getApplicationDocumentsPath() async => documents;

  @override
  Future<String?> getApplicationCachePath() async =>
      cache ?? (throw UnimplementedError('cache path'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory sources;
  late Directory cache;
  late _FakeFfmpeg ffmpeg;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('sp_playcopy_');
    sources = Directory('${root.path}/mp3')..createSync();
    cache = Directory('${root.path}/cache');
    ffmpeg = _FakeFfmpeg();
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  PlaybackCopyService build({
    int maxCacheBytes = kPlaybackCopyCacheMaxBytes,
    Duration busyMaxWait = const Duration(seconds: 2),
  }) => PlaybackCopyService(
    runner: ffmpeg,
    cacheDirBuilder: () async => cache,
    maxCacheBytes: maxCacheBytes,
    busyRetryDelay: const Duration(milliseconds: 10),
    busyMaxWait: busyMaxWait,
  );

  /// 원본 반주를 하나 만든다. 기본은 VBR MP3.
  File source(String name, {List<int>? bytes}) =>
      File('${sources.path}/$name')..writeAsBytesSync(bytes ?? fakeVbrMp3());

  List<String> cached() => cache.existsSync()
      ? (cache.listSync().whereType<File>().map(
          (f) => f.uri.pathSegments.last,
        )).toList()
      : <String>[];

  group('ensure — 굽기', () {
    test('VBR 원본이면 한 번 굽는다 — .part에 쓰고 rename으로 확정한다', () async {
      final service = build();
      final src = source('곡_mr1.mp3');

      final path = await service.ensure(
        sourcePath: src.path,
        sourceFileName: '곡_mr1.mp3',
      );

      expect(path, isNotNull);
      expect(path, endsWith('.wav'));
      expect(File(path!).existsSync(), isTrue);
      expect(ffmpeg.renders, hasLength(1));
      // 인자는 순수 함수가 만든 그대로고, 출력은 .part다.
      expect(
        ffmpeg.renders.single,
        buildPlaybackCopyArgs(
          input: src.path,
          output: '$path$kPlaybackCopyPartSuffix',
        ),
      );
      // 굽고 나면 .part는 남지 않는다.
      expect(cached().where((n) => n.endsWith('.part')), isEmpty);
      expect(cached(), hasLength(1));
    });

    test('이미 있으면 다시 굽지 않는다', () async {
      final service = build();
      final src = source('곡_mr1.mp3');
      final first = await service.ensure(
        sourcePath: src.path,
        sourceFileName: '곡_mr1.mp3',
      );
      final second = await service.ensure(
        sourcePath: src.path,
        sourceFileName: '곡_mr1.mp3',
      );
      // 앱을 다시 켠 것처럼 새 인스턴스로도 그대로 찾는다.
      final third = await build().ensure(
        sourcePath: src.path,
        sourceFileName: '곡_mr1.mp3',
      );

      expect(second, first);
      expect(third, first);
      expect(ffmpeg.renders, hasLength(1));
    });

    test('🔴 원본이 바뀌면(크기·수정시각) 다시 굽고, 옛 사본은 치운다', () async {
      final service = build();
      final src = source('곡_mr1.mp3');
      final old = await service.ensure(
        sourcePath: src.path,
        sourceFileName: '곡_mr1.mp3',
      );

      // 같은 슬롯에 다른 오디오가 들어왔다 — 파일명은 그대로다.
      src.writeAsBytesSync(fakeVbrMp3(seed: 5));
      final fresh = await service.ensure(
        sourcePath: src.path,
        sourceFileName: '곡_mr1.mp3',
      );

      expect(fresh, isNotNull);
      expect(fresh, isNot(old));
      expect(ffmpeg.renders, hasLength(2));
      expect(File(old!).existsSync(), isFalse);
      expect(cached(), hasLength(1));
    });

    test('수정시각만 바뀌어도 다른 원본으로 본다', () async {
      final service = build();
      final src = source('곡_mr1.mp3');
      final old = await service.ensure(
        sourcePath: src.path,
        sourceFileName: '곡_mr1.mp3',
      );
      src.setLastModifiedSync(DateTime(2020, 1, 2, 3, 4, 5));

      final fresh = await service.ensure(
        sourcePath: src.path,
        sourceFileName: '곡_mr1.mp3',
      );
      expect(fresh, isNot(old));
      expect(ffmpeg.renders, hasLength(2));
    });

    test('VBR이 아니면(CBR·m4a·모르는 형식) 굽지 않고 null', () async {
      final service = build();
      for (final entry in {
        'cbr_mr2.mp3': fakeCbrMp3(),
        'baked_mr3.mp3': fakeM4a(),
        'junk_mr4.mp3': List.filled(500, 0),
      }.entries) {
        final src = source(entry.key, bytes: entry.value);
        expect(
          await service.ensure(sourcePath: src.path, sourceFileName: entry.key),
          isNull,
          reason: entry.key,
        );
      }
      expect(ffmpeg.renders, isEmpty);
    });

    test('원본이 없으면 null — 던지지 않는다', () async {
      expect(
        await build().ensure(
          sourcePath: '${sources.path}/없는곡.mp3',
          sourceFileName: '없는곡.mp3',
        ),
        isNull,
      );
    });

    test('🔴 원본은 읽기만 한다 — 굽고 나도 바이트와 수정시각이 그대로다', () async {
      final service = build();
      final src = source('곡_mr1.mp3');
      final before = src.readAsBytesSync();
      final mtime = src.lastModifiedSync();

      await service.ensure(sourcePath: src.path, sourceFileName: '곡_mr1.mp3');

      expect(src.readAsBytesSync(), before);
      expect(src.lastModifiedSync(), mtime);
    });
  });

  group('ensure — 실패는 치명적이지 않다', () {
    test('ffmpeg가 실패하면 null, 반쪽 .part는 지운다', () async {
      ffmpeg.exitCode = 1; // 반쪽 파일을 남기고 죽는다.
      final service = build();
      final src = source('곡_mr1.mp3');

      final path = await service.ensure(
        sourcePath: src.path,
        sourceFileName: '곡_mr1.mp3',
      );

      expect(path, isNull);
      expect(cached(), isEmpty);
      expect(src.existsSync(), isTrue);
    });

    test('성공 코드인데 출력이 없으면 실패로 본다', () async {
      ffmpeg.writesOutput = false;
      final src = source('곡_mr1.mp3');
      expect(
        await build().ensure(sourcePath: src.path, sourceFileName: '곡_mr1.mp3'),
        isNull,
      );
      expect(cached(), isEmpty);
    });

    test('같은 실행에서는 같은 실패를 되풀이하지 않는다 — 다음 실행은 다시 시도한다', () async {
      ffmpeg.exitCode = 1;
      final service = build();
      final src = source('곡_mr1.mp3');
      await service.ensure(sourcePath: src.path, sourceFileName: '곡_mr1.mp3');
      await service.ensure(sourcePath: src.path, sourceFileName: '곡_mr1.mp3');
      expect(ffmpeg.renders, hasLength(1));

      ffmpeg.exitCode = 0;
      final next = await build().ensure(
        sourcePath: src.path,
        sourceFileName: '곡_mr1.mp3',
      );
      expect(next, isNotNull);
      expect(ffmpeg.renders, hasLength(2));
    });

    test('ffmpeg를 못 찾으면 null — 띄우지도 않는다', () async {
      ffmpeg.toolMissing = true;
      final src = source('곡_mr1.mp3');
      expect(
        await build().ensure(sourcePath: src.path, sourceFileName: '곡_mr1.mp3'),
        isNull,
      );
      expect(ffmpeg.renders, isEmpty);
    });

    test('지난 실행이 남긴 같은 이름의 .part는 덮어쓴다', () async {
      final service = build();
      final src = source('곡_mr1.mp3');
      final path = await service.ensure(
        sourcePath: src.path,
        sourceFileName: '곡_mr1.mp3',
      );
      // 앱이 굽다 죽은 상태를 만든다: 사본은 없고 .part만 있다.
      File(path!).renameSync('$path$kPlaybackCopyPartSuffix');

      final again = await build().ensure(
        sourcePath: src.path,
        sourceFileName: '곡_mr1.mp3',
      );
      // 🔴 .part는 사본으로 통과하지 못한다 — 다시 구웠다.
      expect(again, path);
      expect(ffmpeg.renders, hasLength(2));
      expect(cached(), [File(path).uri.pathSegments.last]);
    });

    test('dispose는 굽던 ffmpeg를 끊는다', () async {
      ffmpeg.gate = Completer<void>();
      final service = build();
      final src = source('곡_mr1.mp3');
      final pending = service.ensure(
        sourcePath: src.path,
        sourceFileName: '곡_mr1.mp3',
      );
      // 렌더가 뜰 때까지 기다린다.
      while (ffmpeg.renders.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      service.dispose();

      expect(await pending, isNull);
      expect(ffmpeg.cancelled, 1);
    });
  });

  group('ensure — 한 번에 하나', () {
    test('🔴 같은 원본을 동시에 불러도 렌더는 한 번만 돈다', () async {
      ffmpeg.gate = Completer<void>();
      final service = build();
      final src = source('곡_mr1.mp3');
      Future<String?> ask() =>
          service.ensure(sourcePath: src.path, sourceFileName: '곡_mr1.mp3');

      final all = [ask(), ask(), ask()];
      await Future<void>.delayed(const Duration(milliseconds: 50));
      ffmpeg.gate!.complete();
      final paths = await Future.wait(all);

      expect(ffmpeg.renders, hasLength(1));
      expect(paths.toSet(), hasLength(1));
      expect(paths.first, isNotNull);
    });

    test('서로 다른 원본은 한 줄로 선다 — 동시에 두 개를 굽지 않는다', () async {
      ffmpeg.gate = Completer<void>();
      final service = build();
      final a = source('가_mr1.mp3');
      final b = source('나_mr1.mp3', bytes: fakeVbrMp3(seed: 2));

      final first = service.ensure(
        sourcePath: a.path,
        sourceFileName: '가_mr1.mp3',
      );
      final second = service.ensure(
        sourcePath: b.path,
        sourceFileName: '나_mr1.mp3',
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      // 첫 렌더가 문에 막혀 있는 동안 둘째는 뜨지 않는다.
      expect(ffmpeg.renders, hasLength(1));

      ffmpeg.gate!.complete();
      expect(await first, isNotNull);
      expect(await second, isNotNull);
      expect(ffmpeg.renders, hasLength(2));
      expect(ffmpeg.maxConcurrent, 1);
    });

    test('앞 작업이 실패해도 줄은 이어진다', () async {
      final service = build();
      final a = source('가_mr1.mp3');
      final b = source('나_mr1.mp3', bytes: fakeVbrMp3(seed: 2));
      ffmpeg.exitCode = 1;
      expect(
        await service.ensure(sourcePath: a.path, sourceFileName: '가_mr1.mp3'),
        isNull,
      );
      ffmpeg.exitCode = 0;
      expect(
        await service.ensure(sourcePath: b.path, sourceFileName: '나_mr1.mp3'),
        isNotNull,
      );
    });
  });

  group('ensure — 받는 중에는 굽지 않는다', () {
    test('🔴 녹음·고정 조각이 열려 있는 동안 미루고, 닫히면 굽는다', () async {
      final service = build();
      final src = source('곡_mr1.mp3');
      var busy = true;
      var polls = 0;

      final pending = service.ensure(
        sourcePath: src.path,
        sourceFileName: '곡_mr1.mp3',
        isBusy: () {
          polls += 1;
          return busy;
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(ffmpeg.renders, isEmpty, reason: '받는 중에는 ffmpeg를 띄우지 않는다');
      expect(polls, greaterThan(1));

      busy = false;
      expect(await pending, isNotNull);
      expect(ffmpeg.renders, hasLength(1));
    });

    test('너무 오래 열려 있으면 포기한다 — 실패로 적지는 않아 다음에 다시 건다', () async {
      final service = build(busyMaxWait: const Duration(milliseconds: 40));
      final src = source('곡_mr1.mp3');

      expect(
        await service.ensure(
          sourcePath: src.path,
          sourceFileName: '곡_mr1.mp3',
          isBusy: () => true,
        ),
        isNull,
      );
      expect(ffmpeg.renders, isEmpty);

      expect(
        await service.ensure(sourcePath: src.path, sourceFileName: '곡_mr1.mp3'),
        isNotNull,
      );
    });

    test('기다리는 사이에 원본이 갈렸으면 그 렌더는 버린다', () async {
      final service = build();
      final src = source('곡_mr1.mp3');
      var busy = true;
      final pending = service.ensure(
        sourcePath: src.path,
        sourceFileName: '곡_mr1.mp3',
        isBusy: () => busy,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      src.writeAsBytesSync(fakeVbrMp3(seed: 7));
      busy = false;

      expect(await pending, isNull);
      expect(ffmpeg.renders, isEmpty);
    });
  });

  group('lookup · resolveForLoad — 곡을 물릴 때', () {
    test('lookup은 굽지 않는다 — VBR인데 사본이 없으면 needsCopy만 알린다', () async {
      final service = build();
      final src = source('곡_mr1.mp3');

      final found = await service.lookup(
        sourcePath: src.path,
        sourceFileName: '곡_mr1.mp3',
      );

      expect(found.copyPath, isNull);
      expect(found.needsCopy, isTrue);
      expect(ffmpeg.renders, isEmpty);
    });

    test('CBR·m4a는 needsCopy가 아니다', () async {
      final service = build();
      final src = source('cbr_mr2.mp3', bytes: fakeCbrMp3());
      final found = await service.lookup(
        sourcePath: src.path,
        sourceFileName: 'cbr_mr2.mp3',
      );
      expect(found.copyPath, isNull);
      expect(found.needsCopy, isFalse);
    });

    test('🔴 첫 물림은 원본(vbrOriginal) — 기다리지 않는다. 다음 물림부터 사본(seekCopy)', () async {
      ffmpeg.gate = Completer<void>(); // 렌더가 아직 안 끝난 상태를 붙잡아 둔다.
      final service = build();
      final src = source('곡_mr1.mp3');
      Future<PlaybackCopyResolution> load() => service.resolveForLoad(
        sourcePath: src.path,
        sourceFileName: '곡_mr1.mp3',
        startDelay: Duration.zero,
      );

      final first = await load();
      expect(first.path, isNull, reason: '굽기를 기다리지 않고 원본을 튼다');
      expect(first.kind, PlaybackSourceKind.vbrOriginal);

      // 굽는 중에 또 물려도 원본이고, 렌더가 겹쳐 뜨지 않는다.
      final during = await load();
      expect(during.path, isNull);
      expect(during.kind, PlaybackSourceKind.vbrOriginal);

      ffmpeg.gate!.complete();
      await service.settle();
      expect(ffmpeg.renders, hasLength(1));

      final next = await load();
      expect(next.kind, PlaybackSourceKind.seekCopy);
      expect(next.path, endsWith('.wav'));
      expect(File(next.path!).existsSync(), isTrue);
    });

    test('VBR이 아니면 plain — 뒤에서 굽지도 않는다', () async {
      final service = build();
      final src = source('cbr_mr2.mp3', bytes: fakeCbrMp3());
      final resolution = await service.resolveForLoad(
        sourcePath: src.path,
        sourceFileName: 'cbr_mr2.mp3',
        startDelay: Duration.zero,
      );
      await service.settle();

      expect(resolution, kPlainPlayback);
      expect(ffmpeg.renders, isEmpty);
    });

    test('굽다 실패해도 다음 물림은 원본으로 계속 재생된다', () async {
      ffmpeg.exitCode = 1;
      final service = build();
      final src = source('곡_mr1.mp3');
      Future<PlaybackCopyResolution> load() => service.resolveForLoad(
        sourcePath: src.path,
        sourceFileName: '곡_mr1.mp3',
        startDelay: Duration.zero,
      );

      await load();
      await service.settle();
      final next = await load();
      await service.settle();

      expect(next.path, isNull);
      expect(next.kind, PlaybackSourceKind.vbrOriginal);
      expect(ffmpeg.renders, hasLength(1));
    });

    test('쓴 사본은 수정시각이 갱신된다 — 용량 축출이 오래 안 쓴 순으로 버리게', () async {
      final service = build();
      final src = source('곡_mr1.mp3');
      final path = await service.ensure(
        sourcePath: src.path,
        sourceFileName: '곡_mr1.mp3',
      );
      File(path!).setLastModifiedSync(DateTime(2021, 5, 5));

      await service.lookup(sourcePath: src.path, sourceFileName: '곡_mr1.mp3');

      expect(File(path).lastModifiedSync().year, greaterThan(2021));
    });
  });

  group('정리 — 파생 데이터', () {
    /// 사본 폴더에 파일을 직접 놓는다(크기 [bytes]).
    File put(String name, {int bytes = 100}) {
      cache.createSync(recursive: true);
      return File('${cache.path}/$name')
        ..writeAsBytesSync(List.filled(bytes, 1));
    }

    test('clearFor는 그 원본의 사본만(지문 무관) 지운다', () async {
      final service = build();
      put(playbackCopyFileName('곡_mr1.mp3', sizeBytes: 1, modifiedMs: 1));
      put(playbackCopyFileName('곡_mr1.mp3', sizeBytes: 2, modifiedMs: 2));
      final other = put(
        playbackCopyFileName('곡_mr2.mp3', sizeBytes: 1, modifiedMs: 1),
      );

      expect(await service.clearFor('곡_mr1.mp3'), 2);
      expect(cached(), [other.uri.pathSegments.last]);
      expect(await service.clearFor('  '), 0);
    });

    test('🔴 sweep — 원본이 사라진 사본·지문이 갈린 사본·굽다 만 .part를 치운다', () async {
      final service = build();
      final live = source('산곡_mr1.mp3');
      final valid = await service.ensure(
        sourcePath: live.path,
        sourceFileName: '산곡_mr1.mp3',
      );
      final validName = File(valid!).uri.pathSegments.last;
      final stale = put(
        playbackCopyFileName('산곡_mr1.mp3', sizeBytes: 9, modifiedMs: 9),
      );
      final orphan = put(
        playbackCopyFileName('지운곡_mr1.mp3', sizeBytes: 1, modifiedMs: 1),
      );
      final gone = put(
        playbackCopyFileName('파일없는곡_mr1.mp3', sizeBytes: 1, modifiedMs: 1),
      );
      final part = put('$validName$kPlaybackCopyPartSuffix');
      final stranger = put('desktop.ini');

      final removed = await service.sweep(
        // 「파일없는곡」은 곡 목록에는 있지만 원본 파일이 없다.
        liveSourceFileNames: ['산곡_mr1.mp3', '파일없는곡_mr1.mp3'],
        sourcePathOf: (name) async => name == '산곡_mr1.mp3' ? live.path : null,
      );

      expect(removed, 4);
      expect(File(valid).existsSync(), isTrue, reason: '쓸 수 있는 사본은 남긴다');
      for (final file in [stale, orphan, gone, part]) {
        expect(file.existsSync(), isFalse, reason: file.path);
      }
      expect(stranger.existsSync(), isTrue, reason: '우리가 만든 파일만 지운다');
      expect(live.existsSync(), isTrue);
    });

    test('trimTo — 상한을 넘으면 오래 안 쓴 것부터 버리고, 재생 중인 사본은 지킨다', () async {
      final service = build();
      File aged(String source, int day) =>
          put(playbackCopyFileName(source, sizeBytes: 1, modifiedMs: 1))
            ..setLastModifiedSync(DateTime(2026, 1, day));
      final oldest = aged('가_mr1.mp3', 1);
      final playing = aged('나_mr1.mp3', 2);
      final middle = aged('다_mr1.mp3', 3);
      final newest = aged('라_mr1.mp3', 4);
      service.activePathProvider = () => playing.path;

      // 400바이트 → 상한 250: 둘을 버려야 한다. 재생 중인 「나」는 건너뛴다.
      expect(await service.trimTo(250), 2);

      expect(oldest.existsSync(), isFalse);
      expect(playing.existsSync(), isTrue);
      expect(middle.existsSync(), isFalse);
      expect(newest.existsSync(), isTrue);
    });

    test('굽고 나면 상한에 맞춘다 — 방금 구운 것은 남긴다', () async {
      final service = build(maxCacheBytes: 250);
      final old = put(
        playbackCopyFileName('옛곡_mr1.mp3', sizeBytes: 1, modifiedMs: 1),
      )..setLastModifiedSync(DateTime(2020));
      final src = source('새곡_mr1.mp3');

      final path = await service.ensure(
        sourcePath: src.path,
        sourceFileName: '새곡_mr1.mp3',
      );

      // 가짜 사본 200 + 옛 사본 100 = 300 > 250
      expect(File(path!).existsSync(), isTrue);
      expect(old.existsSync(), isFalse);
    });

    test('cacheSize는 우리 파일만(.part 포함) 센다, clearCache는 전부 지운다', () async {
      final service = build();
      put(
        playbackCopyFileName('가_mr1.mp3', sizeBytes: 1, modifiedMs: 1),
        bytes: 300,
      );
      put(
        '${playbackCopyFileName('나_mr1.mp3', sizeBytes: 1, modifiedMs: 1)}'
        '$kPlaybackCopyPartSuffix',
        bytes: 50,
      );
      final stranger = put('desktop.ini', bytes: 999);

      expect(await service.cacheSize(), 350);
      expect(await service.clearCache(), 2);
      expect(await service.cacheSize(), 0);
      expect(stranger.existsSync(), isTrue);
    });
  });

  group('사본 폴더 — OneDrive 밖', () {
    test('앱 캐시 폴더 아래 playback에 둔다', () async {
      final appCache = Directory('${root.path}/LocalAppData')..createSync();
      PathProviderPlatform.instance = _FakePathProvider(
        documents: '${root.path}/Documents',
        cache: appCache.path,
      );
      final dir = await PlaybackCopyService(runner: ffmpeg).cacheDir;

      expect(dir.path, '${appCache.path}${Platform.pathSeparator}playback');
      expect(dir.existsSync(), isTrue);
    });

    test('캐시 폴더를 못 얻으면 Documents/data/cache/playback으로 물러난다', () async {
      PathProviderPlatform.instance = _FakePathProvider(
        documents: '${root.path}/Documents',
      );
      final dir = await PlaybackCopyService(runner: ffmpeg).cacheDir;

      expect(dir.path, '${root.path}/Documents/data/cache/playback');
      // 🔴 반주 폴더(data/mp3)가 아니다 — 거기 두면 고아 점검이 지운다.
      expect(dir.path, isNot(contains('/mp3')));
    });
  });
}
