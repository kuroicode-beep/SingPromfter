// file: lib/services/lrclib_client.dart
//
// LRCLIB(lrclib.net)에서 싱크 가사를 가져온다. API 키가 필요 없다.
//
// package:http의 Client 인터페이스를 쓰는 이유는 테스트에서 가짜 클라이언트를
// 주입하기 위해서다(이 프로젝트는 모킹 패키지를 쓰지 않는다).
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/app_version.dart';

/// LRCLIB 검색 결과 한 건.
class LyricsCandidate {
  final int id;
  final String trackName;
  final String artistName;
  final Duration duration;
  final String? syncedLyrics;
  final String? plainLyrics;

  const LyricsCandidate({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.duration,
    this.syncedLyrics,
    this.plainLyrics,
  });

  bool get hasSynced => (syncedLyrics ?? '').trim().isNotEmpty;
  bool get hasPlain => (plainLyrics ?? '').trim().isNotEmpty;

  factory LyricsCandidate.fromJson(Map<String, dynamic> json) {
    final seconds = (json['duration'] as num?)?.round() ?? 0;
    return LyricsCandidate(
      id: (json['id'] as num?)?.toInt() ?? 0,
      trackName: (json['trackName'] as String? ?? '').trim(),
      artistName: (json['artistName'] as String? ?? '').trim(),
      duration: Duration(seconds: seconds),
      syncedLyrics: json['syncedLyrics'] as String?,
      plainLyrics: json['plainLyrics'] as String?,
    );
  }
}

class LrclibClient {
  static const String _host = 'lrclib.net';

  final http.Client _client;

  LrclibClient({http.Client? client}) : _client = client ?? http.Client();

  Map<String, String> get _headers => {
    // LRCLIB 권장: 사용 주체를 밝히는 User-Agent
    'User-Agent': 'SingPromfter/${AppVersion.current} (personal practice tool)',
  };

  /// 제목·가수·길이로 정확히 조회한다. 없으면 null.
  Future<LyricsCandidate?> get({
    required String title,
    required String artist,
    Duration? duration,
  }) async {
    if (title.trim().isEmpty) return null;

    final uri = Uri.https(_host, '/api/get', {
      'track_name': title.trim(),
      'artist_name': artist.trim(),
      if (duration != null && duration > Duration.zero)
        'duration': '${duration.inSeconds}',
    });

    try {
      final response = await _client.get(uri, headers: _headers);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      return LyricsCandidate.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// 정확 조회가 실패했을 때 쓰는 검색. 결과가 여러 개면 사용자가 고른다.
  Future<List<LyricsCandidate>> search({
    required String query,
    int limit = 10,
  }) async {
    if (query.trim().isEmpty) return const [];

    final uri = Uri.https(_host, '/api/search', {'q': query.trim()});
    try {
      final response = await _client.get(uri, headers: _headers);
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => LyricsCandidate.fromJson(e.cast<String, dynamic>()))
          .take(limit)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  void close() => _client.close();
}
