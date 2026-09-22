// file: test/services/sync_client_test.dart
//
// 폰 쪽 동기화의 데이터 보호 — PC가 곡 목록을 못 읽은 채 떠 있을 때.
//
// 만든 계기: PC 부팅 때 songs.json이 잠겨 app.songs = []로 뜬 상태에서 폰이 동기화를
// 누르면 0곡 매니페스트가 왔고, 「곡 메타는 PC를 그대로 따른다」라서 폰의 songs.json이
// 빈 목록으로 덮였다(폰 파일은 멀쩡히 읽히므로 저장소의 빈 값 보호가 걸리지 않는다).
//
// http.Client 자리에 MockClient를 넣어 서버 없이 돈다. 파일 IO를 실제로 기다리므로
// plain test()다(testWidgets의 가짜 시계 금지).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/repository/practice_log_store.dart';
import 'package:singpromfter_app/repository/song_meta_store.dart';
import 'package:singpromfter_app/repository/song_repository.dart';
import 'package:singpromfter_app/services/sync_client.dart';
import 'package:singpromfter_app/services/sync_protocol.dart';
import 'package:singpromfter_app/services/sync_server_handler.dart';

/// 임시 폴더를 Documents로 쓰게 만드는 path_provider(반주 폴더 조회용).
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late SongRepository repo;

  setUp(() async {
    // songs.json이 아직 없는 폰은 옛 저장소(SharedPreferences) 이관 경로를 지난다.
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('sp_sync_client_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    repo = SongRepository.forTest(
      metaStore: SongMetaStore(
        baseDirBuilder: () async => tmp,
        ioRetryDelay: const Duration(milliseconds: 1),
      ),
    );
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Song song(String id) => Song(
    id: id,
    title: '곡 $id',
    artist: '가수',
    lyricsPath: '${tmp.path}/data/txt/$id.txt',
    lyricsText: '가사',
    backingTracks: const [],
    createdAt: DateTime(2026, 9, 1),
    updatedAt: DateTime(2026, 9, 1),
  );

  SyncClient client(http.Client mock) => SyncClient(
    client: mock,
    repo: repo,
    practiceStore: PracticeLogStore(baseDirBuilder: () async => tmp),
  );

  /// 매니페스트 응답 하나로 답하는 가짜 PC.
  MockClient pcAnswering(http.Response manifest) => MockClient((req) async {
    if (req.url.path == '/api/sync/manifest') return manifest;
    return http.Response('{"ok":false}', 404);
  });

  test('🔴 PC 매니페스트가 비어 있고 폰에 곡이 있으면 폰 목록을 지우지 않고 실패로 알린다', () async {
    await repo.saveSongs([song('a'), song('b')]);
    final before = await File('${tmp.path}/data/songs.json').readAsString();
    final empty = SyncManifest(
      version: kSyncProtocolVersion,
      appVersion: '5.17.0',
      songs: const [],
    );
    final outcome = await client(
      pcAnswering(
        http.Response(jsonEncode({'ok': true, ...empty.toJson()}), 200),
      ),
    ).pull(address: '127.0.0.1:8772', pairingCode: 'ABCDEF');

    expect(outcome.ok, isFalse);
    expect(outcome.message, contains('폰의 곡 목록을 지우지 않았습니다'));
    expect(await File('${tmp.path}/data/songs.json').readAsString(), before);
    expect((await repo.loadSongs()).map((s) => s.id), ['a', 'b']);
  });

  test('폰도 비어 있으면 빈 매니페스트는 그냥 「이미 최신」이다(첫 동기화·둘 다 0곡)', () async {
    final empty = SyncManifest(
      version: kSyncProtocolVersion,
      appVersion: '5.17.0',
      songs: const [],
    );
    final outcome = await client(
      pcAnswering(
        http.Response(jsonEncode({'ok': true, ...empty.toJson()}), 200),
      ),
    ).pull(address: '127.0.0.1:8772', pairingCode: 'ABCDEF');

    expect(outcome.ok, isTrue);
    expect(outcome.songCount, 0);
  });

  test('🔴 PC가 503 songs_unreadable로 답하면 그 사유를 그대로 보여 준다', () async {
    await repo.saveSongs([song('a')]);
    final outcome = await client(
      pcAnswering(
        http.Response(
          jsonEncode({
            'ok': false,
            'error': SyncServerHandler.songsUnavailableError,
          }),
          503,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    ).pull(address: '127.0.0.1:8772', pairingCode: 'ABCDEF');

    expect(outcome.ok, isFalse);
    expect(outcome.message, contains('PC가 곡 목록을 읽지 못한 상태'));
    expect((await repo.loadSongs()).map((s) => s.id), ['a']);
  });

  test('사유 없는 오류 응답은 예전 문구(HTTP 코드)다', () async {
    final outcome = await client(
      pcAnswering(http.Response('nope', 500)),
    ).pull(address: '127.0.0.1:8772', pairingCode: 'ABCDEF');

    expect(outcome.ok, isFalse);
    expect(outcome.message, contains('HTTP 500'));
  });
}
