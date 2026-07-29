// file: lib/services/youtube_data_client.dart
//
// YouTube Data API v3 — 앱 안 유튜브 검색과 인기 차트.
//
// API 키는 환경변수 YOUTUBE_API_KEY에서 읽는다(blogger와 공용 Google 키).
// 키가 없으면 요청을 보내지 않고 missingKey로 답한다 — UI가 안내 문구를
// 띄울 수 있도록, 빈 결과와 "키 없음"을 구분해서 돌려준다.
//
// package:http의 Client 인터페이스를 쓰는 이유는 테스트에서 가짜 클라이언트를
// 주입하기 위해서다(이 프로젝트는 모킹 패키지를 쓰지 않는다). environment
// 주입은 external_tool_locator와 같은 관례다.
//
// 할당량 주의: search.list는 1회 100유닛(일일 10,000). 그래서 검색은
// Enter/버튼에서만 부르고(증분 검색 금지), 차트는 호출부가 세션 캐시한다.
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;

import '../constants/app_version.dart';

/// 검색·차트 결과 한 건.
class YoutubeVideo {
  final String videoId;
  final String title;
  final String channelTitle;

  /// "3:45" 꼴. videos.list 2차 호출이 실패하면 null — 결과 자체는 살린다.
  final String? durationText;
  final String? thumbnailUrl;

  const YoutubeVideo({
    required this.videoId,
    required this.title,
    required this.channelTitle,
    this.durationText,
    this.thumbnailUrl,
  });

  String get url => 'https://www.youtube.com/watch?v=$videoId';

  YoutubeVideo withDuration(String? durationText) => YoutubeVideo(
    videoId: videoId,
    title: title,
    channelTitle: channelTitle,
    durationText: durationText ?? this.durationText,
    thumbnailUrl: thumbnailUrl,
  );
}

/// 요청이 왜 비었는지까지 구분한다 — ok의 빈 목록은 "결과 없음"이고,
/// missingKey는 검색 자체가 불가능한 상태다.
enum YoutubeFetchStatus { ok, missingKey, failed }

class YoutubeFetchResult {
  final YoutubeFetchStatus status;
  final List<YoutubeVideo> videos;

  /// failed일 때 사용자에게 보여 줄 사유.
  final String? message;

  const YoutubeFetchResult.ok(this.videos)
    : status = YoutubeFetchStatus.ok,
      message = null;

  const YoutubeFetchResult.missingKey()
    : status = YoutubeFetchStatus.missingKey,
      videos = const [],
      message = null;

  const YoutubeFetchResult.failed(this.message)
    : status = YoutubeFetchStatus.failed,
      videos = const [];
}

class YoutubeDataClient {
  static const String _host = 'www.googleapis.com';
  static const Duration _timeout = Duration(seconds: 10);

  /// TJ노래방 공식 유튜브 채널(@tj노래방tjkaraoke, 구독 181만).
  /// 2026-07-30 channels?q="TJ 노래방" 검색으로 확정 — 동명 채널이 여럿이라
  /// 런타임 해석 대신 고정한다. 틀어지면 차트가 failed로 떨어질 뿐이다.
  static const String karaokeChannelId = 'UCZUhx8ClCv6paFW7qi3qljg';

  /// 노래방 차트로 볼 "최근" 기간.
  static const Duration karaokeChartWindow = Duration(days: 56);

  final http.Client _client;
  final String? _apiKey;

  YoutubeDataClient({http.Client? client, Map<String, String>? environment})
    : _client = client ?? http.Client(),
      _apiKey = (environment ?? Platform.environment)['YOUTUBE_API_KEY'];

  bool get hasApiKey => (_apiKey ?? '').trim().isNotEmpty;

  Map<String, String> get _headers => {
    'User-Agent': 'SingPromfter/${AppVersion.current} (personal practice tool)',
  };

  /// 노래 검색. Enter/버튼에서만 부를 것(100유닛/회).
  Future<YoutubeFetchResult> search(String query, {int maxResults = 15}) {
    if (query.trim().isEmpty) return Future.value(const YoutubeFetchResult.ok([]));
    return _searchList({
      'q': query.trim(),
      'maxResults': '$maxResults',
    });
  }

  /// 한국 인기 음악 차트. videos.list 단일 호출(1유닛) — snippet과
  /// contentDetails를 한 번에 받아 2차 호출이 필요 없다.
  Future<YoutubeFetchResult> mostPopularMusic({int maxResults = 15}) async {
    final key = _apiKey;
    if (key == null || key.trim().isEmpty) {
      return const YoutubeFetchResult.missingKey();
    }
    final uri = Uri.https(_host, '/youtube/v3/videos', {
      'part': 'snippet,contentDetails',
      'chart': 'mostPopular',
      'regionCode': 'KR',
      'videoCategoryId': '10',
      'maxResults': '$maxResults',
      'key': key,
    });
    try {
      final response = await _client.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode != 200) return _httpFailure(response.statusCode);
      final items = _itemsOf(response);
      return YoutubeFetchResult.ok([
        for (final item in items) ?_videoFromVideosItem(item),
      ]);
    } catch (_) {
      return const YoutubeFetchResult.failed('네트워크 오류로 목록을 가져오지 못했습니다.');
    }
  }

  /// TJ노래방 공식 채널의 최근 8주 인기 영상 — "노래방 인기 리스트".
  ///
  /// 채널이 하루 40~50곡을 올려서(총 7.4만 편) 업로드 목록 순회로는 하루치밖에
  /// 못 본다. order=viewCount + publishedAfter 검색이 의미 있는 유일한 방법이다.
  Future<YoutubeFetchResult> karaokeChannelPopular({
    int maxResults = 15,
    DateTime? now,
  }) {
    final after = (now ?? DateTime.now().toUtc()).subtract(karaokeChartWindow);
    return _searchList({
      'channelId': karaokeChannelId,
      'order': 'viewCount',
      'publishedAfter': '${after.toIso8601String().split('.').first}Z',
      'maxResults': '$maxResults',
    });
  }

  /// search.list 공통 경로 — snippet만 오므로 videos.list(1유닛)로 길이를
  /// 병합한다. 2차 호출 실패는 무시한다(길이 없이라도 결과가 낫다).
  Future<YoutubeFetchResult> _searchList(Map<String, String> params) async {
    final key = _apiKey;
    if (key == null || key.trim().isEmpty) {
      return const YoutubeFetchResult.missingKey();
    }
    final uri = Uri.https(_host, '/youtube/v3/search', {
      'part': 'snippet',
      'type': 'video',
      ...params,
      'key': key,
    });
    try {
      final response = await _client.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode != 200) return _httpFailure(response.statusCode);
      final videos = [
        for (final item in _itemsOf(response)) ?_videoFromSearchItem(item),
      ];
      return YoutubeFetchResult.ok(await _mergeDurations(videos, key));
    } catch (_) {
      return const YoutubeFetchResult.failed('네트워크 오류로 검색하지 못했습니다.');
    }
  }

  Future<List<YoutubeVideo>> _mergeDurations(
    List<YoutubeVideo> videos,
    String key,
  ) async {
    if (videos.isEmpty) return videos;
    final uri = Uri.https(_host, '/youtube/v3/videos', {
      'part': 'contentDetails',
      'id': videos.map((v) => v.videoId).join(','),
      'key': key,
    });
    try {
      final response = await _client.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode != 200) return videos;
      final durations = <String, String?>{
        for (final item in _itemsOf(response))
          if (item['id'] is String)
            item['id'] as String: formatIso8601Duration(
              (item['contentDetails'] as Map?)?['duration'] as String?,
            ),
      };
      return [
        for (final v in videos) v.withDuration(durations[v.videoId]),
      ];
    } catch (_) {
      return videos;
    }
  }

  static YoutubeFetchResult _httpFailure(int statusCode) {
    if (statusCode == 403) {
      return const YoutubeFetchResult.failed(
        'API 사용량 한도를 넘었거나 키에 문제가 있습니다.',
      );
    }
    return YoutubeFetchResult.failed('유튜브 응답 오류($statusCode)');
  }

  static List<Map<String, dynamic>> _itemsOf(http.Response response) {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) return const [];
    final items = decoded['items'];
    if (items is! List) return const [];
    return [
      for (final item in items)
        if (item is Map) item.cast<String, dynamic>(),
    ];
  }

  /// search.list 항목 — id가 {videoId: ...} 꼴.
  static YoutubeVideo? _videoFromSearchItem(Map<String, dynamic> item) {
    final id = (item['id'] as Map?)?['videoId'] as String?;
    return _videoFrom(id, item['snippet']);
  }

  /// videos.list 항목 — id가 문자열이고 contentDetails가 함께 온다.
  static YoutubeVideo? _videoFromVideosItem(Map<String, dynamic> item) {
    final video = _videoFrom(item['id'] as String?, item['snippet']);
    if (video == null) return null;
    return video.withDuration(
      formatIso8601Duration((item['contentDetails'] as Map?)?['duration'] as String?),
    );
  }

  static YoutubeVideo? _videoFrom(String? id, Object? snippetRaw) {
    if (id == null || id.isEmpty) return null;
    if (snippetRaw is! Map) return null;
    final snippet = snippetRaw.cast<String, dynamic>();
    final thumbnails = (snippet['thumbnails'] as Map?)?.cast<String, dynamic>();
    final medium = (thumbnails?['medium'] as Map?)?.cast<String, dynamic>();
    return YoutubeVideo(
      videoId: id,
      // API가 제목의 특수문자를 HTML로 이스케이프해 준다(&#39; 등).
      title: _unescapeHtml((snippet['title'] as String? ?? '').trim()),
      channelTitle: (snippet['channelTitle'] as String? ?? '').trim(),
      thumbnailUrl: medium?['url'] as String?,
    );
  }

  /// search.list 제목에 섞여 오는 HTML 엔티티 몇 가지만 되돌린다.
  static String _unescapeHtml(String text) => text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");

  /// ISO-8601 길이(PT3M45S)를 "3:45"로. 못 읽으면 null.
  /// (순수 함수 — 테스트 대상)
  static String? formatIso8601Duration(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final match = RegExp(
      r'^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$',
    ).firstMatch(raw);
    if (match == null) return null;
    final hours = int.tryParse(match.group(1) ?? '') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '') ?? 0;
    final seconds = int.tryParse(match.group(3) ?? '') ?? 0;
    if (hours == 0 && minutes == 0 && seconds == 0) return null;
    String two(int v) => v.toString().padLeft(2, '0');
    if (hours > 0) return '$hours:${two(minutes)}:${two(seconds)}';
    return '$minutes:${two(seconds)}';
  }

  void close() => _client.close();
}
