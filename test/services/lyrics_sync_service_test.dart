import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:singpromfter_app/services/lrclib_client.dart';
import 'package:singpromfter_app/services/lyrics_sync_service.dart';

/// 모킹 패키지 없이 쓰는 가짜 HTTP 클라이언트.
class _FakeClient extends http.BaseClient {
  final Map<String, (int status, String body)> responses;
  final List<Uri> requested = [];

  _FakeClient(this.responses);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requested.add(request.url);
    final key = request.url.path;
    final entry = responses[key] ?? (404, '');
    return http.StreamedResponse(
      Stream.value(utf8.encode(entry.$2)),
      entry.$1,
    );
  }
}

const _syncedBody = '[00:10.00]첫 줄\n[00:20.00]둘째 줄';

void main() {
  group('LrclibClient.get', () {
    test('정확 조회 성공 시 후보를 돌려준다', () async {
      final fake = _FakeClient({
        '/api/get': (
          200,
          jsonEncode({
            'id': 1,
            'trackName': '봄날',
            'artistName': '테스트',
            'duration': 213,
            'syncedLyrics': _syncedBody,
          }),
        ),
      });
      final client = LrclibClient(client: fake);

      final result = await client.get(
        title: '봄날',
        artist: '테스트',
        duration: const Duration(seconds: 213),
      );

      expect(result, isNotNull);
      expect(result!.trackName, '봄날');
      expect(result.hasSynced, isTrue);
      // 길이까지 질의에 포함했는지 확인
      expect(fake.requested.single.queryParameters['duration'], '213');
    });

    test('404면 null', () async {
      final client = LrclibClient(client: _FakeClient({}));
      expect(await client.get(title: 'x', artist: 'y'), isNull);
    });

    test('제목이 비면 요청하지 않는다', () async {
      final fake = _FakeClient({});
      final client = LrclibClient(client: fake);
      expect(await client.get(title: '   ', artist: 'y'), isNull);
      expect(fake.requested, isEmpty);
    });

    test('깨진 JSON이어도 예외를 던지지 않는다', () async {
      final client = LrclibClient(
        client: _FakeClient({'/api/get': (200, 'not json')}),
      );
      expect(await client.get(title: 'a', artist: 'b'), isNull);
    });
  });

  group('LrclibClient.search', () {
    test('목록을 파싱한다', () async {
      final client = LrclibClient(
        client: _FakeClient({
          '/api/search': (
            200,
            jsonEncode([
              {'id': 1, 'trackName': 'A', 'duration': 100, 'syncedLyrics': _syncedBody},
              {'id': 2, 'trackName': 'B', 'duration': 200},
            ]),
          ),
        }),
      );

      final results = await client.search(query: '봄날');
      expect(results, hasLength(2));
      expect(results.first.hasSynced, isTrue);
      expect(results.last.hasSynced, isFalse);
    });

    test('빈 질의는 요청하지 않는다', () async {
      final fake = _FakeClient({});
      expect(await LrclibClient(client: fake).search(query: '  '), isEmpty);
      expect(fake.requested, isEmpty);
    });
  });

  group('LyricsSyncService 후보 선택', () {
    LyricsCandidate c(int id, int seconds, {bool synced = true}) =>
        LyricsCandidate(
          id: id,
          trackName: 'T$id',
          artistName: 'A',
          duration: Duration(seconds: seconds),
          syncedLyrics: synced ? _syncedBody : null,
        );

    test('싱크 없는 결과는 제외한다', () {
      final best = LyricsSyncService.pickBestForTest([
        c(1, 200, synced: false),
        c(2, 500),
      ]);
      expect(best!.id, 2);
    });

    test('길이가 가장 가까운 것을 고른다', () {
      final best = LyricsSyncService.pickBestForTest(
        [c(1, 100), c(2, 210), c(3, 400)],
        duration: const Duration(seconds: 213),
      );
      expect(best!.id, 2);
    });

    test('싱크 결과가 없으면 null', () {
      final best = LyricsSyncService.pickBestForTest([
        c(1, 100, synced: false),
      ]);
      expect(best, isNull);
    });

    test('빈 목록은 null', () {
      expect(LyricsSyncService.pickBestForTest(const []), isNull);
    });
  });
}
