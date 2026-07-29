import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singpromfter_app/controllers/app_controller.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/services/control_server.dart';

// 제어 API 라우터 — HttpServer 없이 dispatch 계층만 검증한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppController app;
  late ControlRouter router;

  setUp(() {
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
    app = AppController();
    router = ControlRouter(app);
  });

  tearDown(() => app.dispose());

  Song song(String id, String title) => Song(
    id: id,
    title: title,
    artist: '가수',
    lyricsPath: '$title.txt',
    lyricsText: '가사',
    backingTracks: const [],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  test('없는 경로는 404', () async {
    final res = await router.dispatch('GET', '/api/nope');
    expect(res.status, 404);
    expect(res.body['ok'], isFalse);
  });

  test('GET /api/state — 버전·재생·도구 상태를 준다', () async {
    final res = await router.dispatch('GET', '/api/state');
    expect(res.status, 200);
    expect(res.body['ok'], isTrue);
    expect(res.body['version'], isNotEmpty);
    expect(res.body['playing'], isFalse);
    expect(res.body['tools'], isA<Map<String, dynamic>>());
  });

  test('GET /api/songs — 검색어 필터', () async {
    app.songs = [song('a', '밤편지'), song('b', '봄날')];
    final all = await router.dispatch('GET', '/api/songs');
    expect((all.body['songs'] as List).length, 2);

    final filtered = await router.dispatch(
      'GET',
      '/api/songs',
      query: {'query': '밤'},
    );
    expect((filtered.body['songs'] as List).length, 1);
  });

  test('POST /api/songs — ack 없으면 409 notice_not_acked', () async {
    final res = await router.dispatch(
      'POST',
      '/api/songs',
      body: {'url': 'https://youtu.be/abc'},
    );
    expect(res.status, 409);
    expect((res.body['error'] as Map)['code'], 'notice_not_acked');
  });

  test('POST /api/songs — 유튜브 주소가 아니면 422', () async {
    final res = await router.dispatch(
      'POST',
      '/api/songs',
      body: {'url': 'https://vimeo.com/1'},
    );
    expect(res.status, 422);
    expect((res.body['error'] as Map)['code'], 'not_youtube_url');
  });

  test('POST /api/songs/{id}/pitch — semitones 누락은 422', () async {
    app.songs = [song('a', '밤편지')];
    final res = await router.dispatch('POST', '/api/songs/a/pitch', body: {});
    expect(res.status, 422);
  });

  test('DELETE /api/queue/{index} — 잘못된 인덱스는 422', () async {
    final res = await router.dispatch('DELETE', '/api/queue/99');
    expect(res.status, 422);
  });

  test('POST /api/playback/volume — 범위 밖은 422, 정상은 설정 반영', () async {
    final bad = await router.dispatch(
      'POST',
      '/api/playback/volume',
      body: {'value': 1.5},
    );
    expect(bad.status, 422);

    final ok = await router.dispatch(
      'POST',
      '/api/playback/volume',
      body: {'value': 0.5},
    );
    expect(ok.status, 200);
    expect(app.settings.volume, 0.5);
  });

  test('GET /api/songs/{id} — 없는 곡은 404, 있는 곡은 가사 포함', () async {
    app.songs = [song('a', '밤편지')];
    final missing = await router.dispatch('GET', '/api/songs/x');
    expect(missing.status, 404);

    final found = await router.dispatch('GET', '/api/songs/a');
    expect(found.status, 200);
    final data = found.body['song'] as Map<String, dynamic>;
    expect(data['title'], '밤편지');
    expect(data['lyrics'], '가사');
  });

  test('GET /api/jobs — 빈 목록', () async {
    final res = await router.dispatch('GET', '/api/jobs');
    expect(res.status, 200);
    expect(res.body['jobs'], isEmpty);
  });

  group('반주 슬롯 라우트', () {
    test('POST tracks — 없는 곡은 404', () async {
      final res = await router.dispatch(
        'POST',
        '/api/songs/nope/tracks',
        body: {'url': 'https://youtu.be/abc'},
      );
      expect(res.status, 404);
      expect((res.body['error'] as Map)['code'], 'song_not_found');
    });

    test('POST tracks — ack 없으면 409', () async {
      app.songs = [song('a', '밤편지')];
      final res = await router.dispatch(
        'POST',
        '/api/songs/a/tracks',
        body: {'url': 'https://youtu.be/abc'},
      );
      expect(res.status, 409);
      expect((res.body['error'] as Map)['code'], 'notice_not_acked');
    });

    test('POST tracks — 유튜브 주소가 아니면 422', () async {
      app.songs = [song('a', '밤편지')];
      final res = await router.dispatch(
        'POST',
        '/api/songs/a/tracks',
        body: {'url': 'https://vimeo.com/1'},
      );
      expect(res.status, 422);
      expect((res.body['error'] as Map)['code'], 'not_youtube_url');
    });

    test('DELETE tracks — 슬롯 번호가 잘못되면 422', () async {
      app.songs = [song('a', '밤편지')];
      final res = await router.dispatch('DELETE', '/api/songs/a/tracks/xyz');
      expect(res.status, 422);
      expect((res.body['error'] as Map)['code'], 'bad_slot');
    });

    test('DELETE tracks — 비어 있는 슬롯은 404', () async {
      app.songs = [song('a', '밤편지')];
      final res = await router.dispatch('DELETE', '/api/songs/a/tracks/2');
      expect(res.status, 404);
      expect((res.body['error'] as Map)['code'], 'track_not_found');
    });
  });

  group('POST /songs/{id}/lyrics/lrc — LRC 직접 부착', () {
    test('content가 없으면 422', () async {
      app.songs = [song('a', '선물')];
      final res = await router.dispatch(
        'POST',
        '/api/songs/a/lyrics/lrc',
        body: {},
      );
      expect(res.status, 422);
      expect((res.body['error'] as Map)['code'], 'missing_content');
    });

    test('없는 곡이면 422 lrc_invalid', () async {
      final res = await router.dispatch(
        'POST',
        '/api/songs/none/lyrics/lrc',
        body: {'content': '[00:01.00]한 줄'},
      );
      expect(res.status, 422);
      expect((res.body['error'] as Map)['code'], 'lrc_invalid');
    });

    test('타임태그가 없는 원문은 422 — 조용히 빈 싱크를 만들지 않는다', () async {
      app.songs = [song('a', '선물')];
      final res = await router.dispatch(
        'POST',
        '/api/songs/a/lyrics/lrc',
        body: {'content': '그냥 텍스트'},
      );
      expect(res.status, 422);
      expect((res.body['error'] as Map)['code'], 'lrc_invalid');
    });
  });

  test('곡 응답에 반주 목록이 들어간다', () async {
    app.songs = [song('a', '밤편지')];
    final res = await router.dispatch('GET', '/api/songs/a');
    final data = res.body['song'] as Map<String, dynamic>;
    expect(data['tracks'], isA<List<dynamic>>());
  });
}
