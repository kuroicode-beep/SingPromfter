// file: test/services/youtube_data_client_test.dart
//
// 유튜브 검색·차트 클라이언트 — 키 없음/할당량/파라미터/길이 병합.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:singpromfter_app/services/youtube_data_client.dart';

/// 모킹 패키지 없이 쓰는 가짜 HTTP 클라이언트(lyrics_sync_service_test와 동일).
/// 경로별 (status, body)를 등록하고, 실제 요청 URL을 기록한다.
class _FakeClient extends http.BaseClient {
  final Map<String, (int, String)> responses;
  final List<Uri> requested = [];

  _FakeClient(this.responses);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requested.add(request.url);
    final (status, body) = responses[request.url.path] ?? (404, '');
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
    );
  }
}

String _searchBody(List<(String, String)> items) => jsonEncode({
  'items': [
    for (final (id, title) in items)
      {
        'id': {'videoId': id},
        'snippet': {
          'title': title,
          'channelTitle': '채널',
          'thumbnails': {
            'medium': {'url': 'https://img/$id.jpg'},
          },
        },
      },
  ],
});

String _videosBody(List<(String, String)> items, {bool withSnippet = false}) =>
    jsonEncode({
      'items': [
        for (final (id, duration) in items)
          {
            'id': id,
            'contentDetails': {'duration': duration},
            if (withSnippet)
              'snippet': {'title': '제목 $id', 'channelTitle': '채널'},
          },
      ],
    });

void main() {
  group('API 키', () {
    test('키가 없으면 요청 자체를 보내지 않고 missingKey', () async {
      final fake = _FakeClient({});
      final client = YoutubeDataClient(client: fake, environment: {});

      expect(client.hasApiKey, isFalse);
      final search = await client.search('선물');
      final chart = await client.mostPopularMusic();
      final karaoke = await client.karaokeChannelPopular();

      expect(search.status, YoutubeFetchStatus.missingKey);
      expect(chart.status, YoutubeFetchStatus.missingKey);
      expect(karaoke.status, YoutubeFetchStatus.missingKey);
      expect(fake.requested, isEmpty);
    });

    test('빈 검색어는 키가 있어도 요청하지 않는다', () async {
      final fake = _FakeClient({});
      final client = YoutubeDataClient(
        client: fake,
        environment: {'YOUTUBE_API_KEY': 'k'},
      );
      final result = await client.search('   ');
      expect(result.status, YoutubeFetchStatus.ok);
      expect(result.videos, isEmpty);
      expect(fake.requested, isEmpty);
    });
  });

  group('search', () {
    test('쿼리 파라미터와 2차 길이 병합', () async {
      final fake = _FakeClient({
        '/youtube/v3/search': (200, _searchBody([('a1', '선물 &#39;라이브&#39;')])),
        '/youtube/v3/videos': (200, _videosBody([('a1', 'PT3M44S')])),
      });
      final client = YoutubeDataClient(
        client: fake,
        environment: {'YOUTUBE_API_KEY': 'test-key'},
      );

      final result = await client.search('선물 윤후', maxResults: 5);

      expect(result.status, YoutubeFetchStatus.ok);
      expect(result.videos, hasLength(1));
      final video = result.videos.single;
      expect(video.videoId, 'a1');
      // HTML 엔티티는 되돌린다.
      expect(video.title, "선물 '라이브'");
      expect(video.durationText, '3:44');
      expect(video.url, 'https://www.youtube.com/watch?v=a1');
      expect(video.thumbnailUrl, 'https://img/a1.jpg');

      final searchUri = fake.requested.first;
      expect(searchUri.queryParameters['q'], '선물 윤후');
      expect(searchUri.queryParameters['type'], 'video');
      expect(searchUri.queryParameters['maxResults'], '5');
      expect(searchUri.queryParameters['key'], 'test-key');

      final videosUri = fake.requested[1];
      expect(videosUri.queryParameters['id'], 'a1');
    });

    test('길이 조회가 실패해도 결과는 살린다', () async {
      final fake = _FakeClient({
        '/youtube/v3/search': (200, _searchBody([('a1', '곡')])),
        // videos.list는 404 — 등록 안 함
      });
      final client = YoutubeDataClient(
        client: fake,
        environment: {'YOUTUBE_API_KEY': 'k'},
      );
      final result = await client.search('곡');
      expect(result.status, YoutubeFetchStatus.ok);
      expect(result.videos.single.durationText, isNull);
    });

    test('403은 할당량 안내로 failed', () async {
      final fake = _FakeClient({'/youtube/v3/search': (403, '{}')});
      final client = YoutubeDataClient(
        client: fake,
        environment: {'YOUTUBE_API_KEY': 'k'},
      );
      final result = await client.search('곡');
      expect(result.status, YoutubeFetchStatus.failed);
      expect(result.message, contains('한도'));
    });

    test('그 외 비200도 failed — 예외는 던지지 않는다', () async {
      final fake = _FakeClient({'/youtube/v3/search': (500, 'oops')});
      final client = YoutubeDataClient(
        client: fake,
        environment: {'YOUTUBE_API_KEY': 'k'},
      );
      final result = await client.search('곡');
      expect(result.status, YoutubeFetchStatus.failed);
    });
  });

  group('mostPopularMusic', () {
    test('KR 음악 차트 파라미터 — videos.list 단일 호출', () async {
      final fake = _FakeClient({
        '/youtube/v3/videos': (
          200,
          _videosBody([('p1', 'PT4M2S')], withSnippet: true),
        ),
      });
      final client = YoutubeDataClient(
        client: fake,
        environment: {'YOUTUBE_API_KEY': 'k'},
      );

      final result = await client.mostPopularMusic();

      expect(result.status, YoutubeFetchStatus.ok);
      expect(result.videos.single.durationText, '4:02');
      expect(fake.requested, hasLength(1), reason: '2차 호출이 없어야 한다');
      final params = fake.requested.single.queryParameters;
      expect(params['chart'], 'mostPopular');
      expect(params['regionCode'], 'KR');
      expect(params['videoCategoryId'], '10');
    });
  });

  group('karaokeChannelPopular', () {
    test('TJ 채널 + 조회수순 + 최근 8주', () async {
      final fake = _FakeClient({
        '/youtube/v3/search': (200, _searchBody([('k1', '[TJ노래방] 곡')])),
        '/youtube/v3/videos': (200, _videosBody([('k1', 'PT3M0S')])),
      });
      final client = YoutubeDataClient(
        client: fake,
        environment: {'YOUTUBE_API_KEY': 'k'},
      );

      final now = DateTime.utc(2026, 7, 30);
      final result = await client.karaokeChannelPopular(now: now);

      expect(result.status, YoutubeFetchStatus.ok);
      final params = fake.requested.first.queryParameters;
      expect(params['channelId'], YoutubeDataClient.karaokeChannelId);
      expect(params['order'], 'viewCount');
      expect(params['publishedAfter'], '2026-06-04T00:00:00Z');
    });
  });

  group('formatIso8601Duration', () {
    test('분:초와 시:분:초', () {
      expect(YoutubeDataClient.formatIso8601Duration('PT3M45S'), '3:45');
      expect(YoutubeDataClient.formatIso8601Duration('PT1H2M3S'), '1:02:03');
      expect(YoutubeDataClient.formatIso8601Duration('PT45S'), '0:45');
      expect(YoutubeDataClient.formatIso8601Duration('PT2M'), '2:00');
    });

    test('못 읽는 값은 null', () {
      expect(YoutubeDataClient.formatIso8601Duration(null), isNull);
      expect(YoutubeDataClient.formatIso8601Duration(''), isNull);
      expect(YoutubeDataClient.formatIso8601Duration('P1D'), isNull);
      expect(YoutubeDataClient.formatIso8601Duration('PT'), isNull);
    });
  });
}
