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
    LyricsCandidate c(
      int id,
      int seconds, {
      bool synced = true,
      String artist = 'A',
    }) => LyricsCandidate(
      id: id,
      trackName: 'T$id',
      artistName: artist,
      duration: Duration(seconds: seconds),
      syncedLyrics: synced ? _syncedBody : null,
    );

    test('싱크 없는 결과는 제외한다', () {
      final best = LyricsSyncService.pickLyricsCandidate(
        [c(1, 200, synced: false), c(2, 500)],
        duration: const Duration(seconds: 500),
        artist: 'A',
      );
      expect(best!.id, 2);
    });

    test('길이가 가장 가까운 것을 고른다', () {
      final best = LyricsSyncService.pickLyricsCandidate(
        [c(1, 100), c(2, 210), c(3, 400)],
        duration: const Duration(seconds: 213),
      );
      expect(best!.id, 2);
    });

    test('싱크 결과가 없으면 null', () {
      expect(
        LyricsSyncService.pickLyricsCandidate([c(1, 100, synced: false)]),
        isNull,
      );
    });

    test('빈 목록은 null', () {
      expect(LyricsSyncService.pickLyricsCandidate(const []), isNull);
    });

    test('허용 오차(7초) 이내면 채택한다', () {
      final best = LyricsSyncService.pickLyricsCandidate(
        [c(1, 207)],
        duration: const Duration(seconds: 200),
      );
      expect(best!.id, 1);
    });

    test('허용 오차를 넘는 후보는 버린다 — 엉뚱한 가사보다 못 찾음이 낫다', () {
      final best = LyricsSyncService.pickLyricsCandidate(
        [c(1, 100), c(2, 300)],
        duration: const Duration(seconds: 200),
      );
      expect(best, isNull);
    });

    // 실제 사고의 회귀: 「선물」(윤후)에 동명의 다른 곡 가사가 붙었다.
    // 길이를 모르는 검색에서 첫 결과를 무조건 받았기 때문이다.
    test('길이를 모르고 가수도 다르면 버린다 — 「선물」 회귀', () {
      final best = LyricsSyncService.pickLyricsCandidate(
        [c(1, 999, artist: '다른가수')],
        artist: '윤후',
      );
      expect(best, isNull);
    });

    test('길이를 몰라도 가수가 겹치면 채택한다', () {
      final best = LyricsSyncService.pickLyricsCandidate(
        [c(1, 210, artist: '다른가수'), c(2, 220, artist: '윤후 (Yoon Hoo)')],
        artist: '윤후',
      );
      expect(best!.id, 2);
    });

    test('길이가 같으면 가수 겹치는 쪽을 우선한다', () {
      final best = LyricsSyncService.pickLyricsCandidate(
        [c(1, 213, artist: '다른가수'), c(2, 214, artist: '윤후')],
        duration: const Duration(seconds: 213),
        artist: '윤후',
      );
      expect(best!.id, 2);
    });

    test('길이도 가수도 근거가 없으면 null', () {
      expect(LyricsSyncService.pickLyricsCandidate([c(1, 999)]), isNull);
    });
  });

  group('artistLooksSame', () {
    test('장식을 걷어내고 포함 관계면 같다', () {
      expect(LyricsSyncService.artistLooksSame('윤후', '윤후 (Yoon Hoo)'), isTrue);
      expect(LyricsSyncService.artistLooksSame('IU', 'iu (아이유)'), isTrue);
    });

    test('다른 이름은 다르다', () {
      expect(LyricsSyncService.artistLooksSame('윤후', '김윤아'), isFalse);
    });

    test('빈 이름은 근거가 될 수 없다', () {
      expect(LyricsSyncService.artistLooksSame('', '윤후'), isFalse);
      expect(LyricsSyncService.artistLooksSame('윤후', '  '), isFalse);
    });
  });
}
