// file: test/services/sync_server_handler_test.dart
//
// 동기화 서버의 안전 장치. LAN에 열리는 순간부터는 "어떤 경로가 원격에
// 열려 있나"가 곧 보안이다 — 곡 삭제·재생 조작이 새 나가면 안 된다.
//
// 뒤쪽의 「데이터 보호」 그룹은 진짜 루프백 HttpServer 위에서 handle()을 돌린다 —
// 실제 파일 IO와 소켓을 기다리므로 plain test()다(testWidgets의 가짜 시계 금지).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singpromfter_app/controllers/app_controller.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/repository/practice_log_store.dart';
import 'package:singpromfter_app/repository/song_meta_store.dart';
import 'package:singpromfter_app/repository/song_repository.dart';
import 'package:singpromfter_app/services/atomic_json_file.dart';
import 'package:singpromfter_app/services/sync_protocol.dart';
import 'package:singpromfter_app/services/sync_server_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('원격 허용 경로', () {
    test('동기화 경로만 원격에서 쓸 수 있다', () {
      expect(
        SyncServerHandler.allowedFromRemote('/api/sync/manifest'),
        isTrue,
      );
      expect(SyncServerHandler.allowedFromRemote('/api/sync/file'), isTrue);
      // 역방향 올리기도 같은 관문을 쓴다 — 토큰 검사는 handle()이 한다.
      expect(SyncServerHandler.allowedFromRemote('/api/sync/push'), isTrue);
    });

    test('곡 조작·재생·상태 경로는 원격에서 막힌다', () {
      for (final path in [
        '/api/state',
        '/api/songs',
        '/api/songs/abc',
        '/api/compose',
        '/api/play',
        '/api/queue',
        // 접두사를 흉내낸 경로도 막힌다.
        '/api/syncx/manifest',
        '/api/../api/songs',
      ]) {
        expect(
          SyncServerHandler.allowedFromRemote(path),
          isFalse,
          reason: path,
        );
      }
    });
  });

  group('반주 파일명 안전성', () {
    test('경로 구분자와 상위 참조는 거부한다', () {
      for (final bad in [
        '',
        '   ',
        '.',
        '..',
        '../secret.txt',
        'sub/dir.mp3',
        r'C:\Windows\win.ini',
      ]) {
        expect(
          SyncServerHandler.isSafeTrackName(bad),
          isFalse,
          reason: bad,
        );
      }
    });

    test('제목에 말줄임표가 든 파일명은 통과한다 — 실측 오탐 3건', () {
      // '..'를 통째로 막았더니 이런 곡의 반주가 전부 404로 실패했다.
      for (final ok in [
        '아마도 그건.. - 최용준 - (가사有)_mr1.mp3',
        '그때 그날.._orig.mp3',
        'song.name.with.dots_mr2.mp3',
      ]) {
        expect(SyncServerHandler.isSafeTrackName(ok), isTrue, reason: ok);
      }
    });
  });

  group('페어링 코드', () {
    test('헷갈리는 글자(0·O·1·I·L)를 쓰지 않는다 — 손으로 옮겨 적는 값이다', () {
      for (final ch in ['0', 'O', '1', 'I', 'L']) {
        expect(
          SyncPairingCode.alphabet.contains(ch),
          isFalse,
          reason: '$ch 가 알파벳에 있으면 오타를 유발한다',
        );
      }
    });

    test('6자리를 만들고 스스로 검증을 통과한다', () {
      var seed = 7;
      int next(int max) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        return seed % max;
      }

      final code = SyncPairingCode.generate(next);
      expect(code.length, SyncPairingCode.length);
      expect(SyncPairingCode.isValid(code), isTrue);
    });

    test('길이·문자가 다르면 거부한다', () {
      expect(SyncPairingCode.isValid(''), isFalse);
      expect(SyncPairingCode.isValid('ABC'), isFalse);
      expect(SyncPairingCode.isValid('ABCDEFG'), isFalse);
      expect(SyncPairingCode.isValid('ABC0EF'), isFalse);
    });

    test('소문자 입력도 받아준다 — 폰 키보드가 소문자로 시작한다', () {
      expect(SyncPairingCode.isValid('abcdef'.toUpperCase()), isTrue);
    });
  });

  group('데이터 보호 — PC가 곡 목록을 못 읽은 채 떠 있을 때 (루프백 HttpServer)', () {
    const code = 'ABCDEF';
    late Directory tmp;
    late AppController app;
    late SongRepository repo;
    HttpServer? server;
    HttpOverrides? mockedHttp;

    setUp(() async {
      // flutter_test 바인딩은 HttpClient를 전부 400으로 막는 목을 심는다 — 이 그룹은
      // 진짜 루프백 소켓으로 handle()을 돌려야 하니 잠시 걷어내고 끝나면 되돌린다.
      mockedHttp = HttpOverrides.current;
      HttpOverrides.global = null;
      for (final name in [
        'xyz.luan/audioplayers',
        'xyz.luan/audioplayers.global',
      ]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              MethodChannel(name),
              (call) async => null,
            );
      }
      SharedPreferences.setMockInitialValues({});
      tmp = await Directory.systemTemp.createTemp('sp_sync_server_');
      app = AppController();
      app.settings = app.settings.copyWith(
        syncServerEnabled: true,
        syncPairingCode: code,
      );
      repo = SongRepository.forTest(
        metaStore: SongMetaStore(
          baseDirBuilder: () async => tmp,
          ioRetryDelay: const Duration(milliseconds: 1),
        ),
      );
    });

    tearDown(() async {
      await server?.close(force: true);
      server = null;
      HttpOverrides.global = mockedHttp;
      app.dispose();
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    File songsFile() => File('${tmp.path}/data/songs.json');

    Future<void> seed(String body) async {
      await Directory('${tmp.path}/data').create(recursive: true);
      await songsFile().writeAsString(body);
    }

    Song song(String id, {bool favorite = false}) => Song(
      id: id,
      title: '곡 $id',
      artist: '가수',
      lyricsPath: '',
      lyricsText: '가사',
      backingTracks: const [],
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
      isFavorite: favorite,
    );

    /// 진짜 루프백 서버에 handler.handle을 물리고 base 주소를 돌려준다.
    Future<Uri> serve(SyncServerHandler handler) async {
      final bound = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server = bound;
      bound.listen((request) async {
        if (!await handler.handle(request)) {
          request.response.statusCode = 404;
          await request.response.close();
        }
      });
      return Uri(scheme: 'http', host: '127.0.0.1', port: bound.port);
    }

    SyncServerHandler handler() => SyncServerHandler(
      app,
      repo: repo,
      practiceStore: PracticeLogStore(baseDirBuilder: () async => tmp),
    );

    test('🔴 곡 목록을 못 읽은 PC는 매니페스트 대신 503 songs_unreadable을 돌려준다', () async {
      // 부팅 때 songs.json이 잠겨(오프라인 자리표시자) app.songs = []로 뜬 상태.
      // 예전에는 0곡 매니페스트를 200으로 내줘 폰이 자기 목록을 통째로 비웠다.
      await seed('{"schemaVersion":2,"songs":[');
      expect(await repo.loadSongs(), isEmpty);
      expect(repo.songsLoadState, AtomicLoadState.unreadable);
      app.songs = [];
      final h = handler();
      expect(h.songsUnavailable, isTrue);

      final base = await serve(h);
      final res = await http.get(
        base.replace(path: '/api/sync/manifest'),
        headers: {'x-sync-token': code},
      );
      expect(res.statusCode, 503);
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      expect(body['ok'], isFalse);
      expect((body['error'] as Map)['code'], 'songs_unreadable');
      expect((body['error'] as Map)['message'], contains('곡 목록을 읽지 못한'));
      // 상위 버전 거부도 같은 관문이다.
      await seed('{"schemaVersion":99,"songs":[]}');
      final newer = SongRepository.forTest(
        metaStore: SongMetaStore(baseDirBuilder: () async => tmp),
      );
      await newer.loadSongs();
      expect(SyncServerHandler(app, repo: newer).songsUnavailable, isTrue);
    });

    test('정상으로 읽은 PC는 예전처럼 200 매니페스트다(.bak 복구도 실제 목록이라 막지 않는다)', () async {
      await repo.saveSongs([song('a')]);
      await repo.loadSongs();
      app.songs = [song('a')];
      final h = handler();
      expect(h.songsUnavailable, isFalse);

      final base = await serve(h);
      final res = await http.get(
        base.replace(path: '/api/sync/manifest'),
        headers: {'x-sync-token': code},
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      expect(body['songCount'], 1);

      // 정본이 깨지고 .bak만 읽히면 recoveredFromBackup — 실제 목록이니 내준다.
      await File('${songsFile().path}.bak').writeAsString(
        SongMetaStore.encodeEntries([song('a').toMetaJson()]),
      );
      await seed('{"schemaVersion":2,"songs":[');
      await repo.loadSongs();
      expect(repo.songsLoadState, AtomicLoadState.recoveredFromBackup);
      expect(h.songsUnavailable, isFalse);
    });

    test('🔴 push — 곡 목록을 저장하지 못하면 app.songs를 바꾸지 않고 507 save_failed', () async {
      // 200을 주면 폰이 pendingFavorites를 비운다. 먼저 app.songs를 바꿔 두면 같은
      // 값을 다시 받아도 「같은 값」(favoritesApplied=0)이라 저장을 다시 시도하지 않는다.
      app.songs = [song('a')];
      // 정본 자리에 폴더가 있으면 rename이 거절된다(권한·잠금 실패의 대역).
      final obstacle = Directory(songsFile().path);
      await obstacle.create(recursive: true);
      final h = handler();

      final first = await h.applyPush(
        const SyncPushPayload(favorites: {'a': true}),
      );
      expect(first.saved, isFalse);
      expect(first.result.favoritesApplied, 1);
      expect(app.songs.single.isFavorite, isFalse, reason: '저장 전에는 바꾸지 않는다');

      final base = await serve(h);
      final res = await http.post(
        base.replace(path: '/api/sync/push'),
        headers: {
          'x-sync-token': code,
          'content-type': 'application/json; charset=utf-8',
        },
        body: utf8.encode(
          jsonEncode(const SyncPushPayload(favorites: {'a': true}).toJson()),
        ),
      );
      expect(res.statusCode, 507);
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      expect((body['error'] as Map)['code'], 'save_failed');

      // 디스크가 고쳐지면 같은 payload가 다시 먹는다(재시도 가능).
      await obstacle.delete();
      final again = await h.applyPush(
        const SyncPushPayload(favorites: {'a': true}),
      );
      expect(again.saved, isTrue);
      expect(again.result.favoritesApplied, 1);
      expect(app.songs.single.isFavorite, isTrue);
      final onDisk = await repo.loadSongs();
      expect(onDisk.single.isFavorite, isTrue);
    });
  });
}
