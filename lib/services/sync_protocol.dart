// file: lib/services/sync_protocol.dart
//
// PC ↔ 폰 곡 동기화의 순수 로직. PC의 로컬 데이터가 정본이고 폰이 받아간다.
//
// 여기에는 파일 시스템도 HTTP도 없다 — 매니페스트를 만들고, 받은 매니페스트와
// 로컬 상태를 비교해 "무엇을 받을지"만 계산한다. 그래야 pumpWidget이나 서버
// 없이 델타 규칙을 테스트할 수 있다.
import '../models/practice_session.dart';
import '../models/song.dart';

/// 매니페스트 포맷 버전. 폰이 모르는 상위 버전을 만나면 받지 않는다.
const int kSyncProtocolVersion = 1;

/// 반주 파일 하나의 크기·수정시각. 델타 판정의 근거다.
typedef TrackStat = ({int size, String mtime});

/// 받아야 할 파일 하나.
class SyncDownload {
  final String songId;
  final String fileName;
  final int size;

  /// 왜 받는지 — 사용자 보고용(신규/변경).
  final bool isNew;

  const SyncDownload({
    required this.songId,
    required this.fileName,
    required this.size,
    required this.isNew,
  });

  @override
  String toString() =>
      'SyncDownload($songId/$fileName, ${size}B, ${isNew ? "신규" : "변경"})';
}

class SyncManifest {
  final int version;
  final String appVersion;
  final List<Map<String, dynamic>> songs;

  const SyncManifest({
    required this.version,
    required this.appVersion,
    required this.songs,
  });

  /// PC 쪽에서 매니페스트를 만든다.
  ///
  /// 가사(txt)와 싱크 가사(lrc)는 본문을 그대로 실어 보낸다 — 수 KB라
  /// 따로 받으러 오가는 비용이 더 크다. 반주(mp3)만 파일로 받는다.
  static SyncManifest build({
    required List<Song> songs,
    required String appVersion,
    required Map<String, String> lrcBySongId,
    required Map<String, TrackStat> trackStats,
  }) {
    final items = <Map<String, dynamic>>[];
    for (final song in songs) {
      final tracks = <Map<String, dynamic>>[];
      for (final t in song.backingTracks) {
        final stat = trackStats[t.fileName];
        // 파일이 없는 반주는 매니페스트에 넣지 않는다 — 폰이 받으러 왔다가
        // 404를 맞고 실패로 끝나는 것보다, 아예 없는 편이 정직하다.
        if (stat == null) continue;
        tracks.add({
          'slot': t.slot,
          'label': t.label,
          'fileName': t.fileName,
          'size': stat.size,
          'mtime': stat.mtime,
        });
      }
      items.add({
        ...song.toMetaJson(),
        'lyricsText': song.lyricsText,
        'lrc': lrcBySongId[song.id],
        'tracks': tracks,
      });
    }
    return SyncManifest(
      version: kSyncProtocolVersion,
      appVersion: appVersion,
      songs: items,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'appVersion': appVersion,
    'songCount': songs.length,
    'songs': songs,
  };

  static SyncManifest fromJson(Map<String, dynamic> json) => SyncManifest(
    version: (json['version'] as num?)?.toInt() ?? 0,
    appVersion: (json['appVersion'] as String?) ?? '',
    songs: (json['songs'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false),
  );

  /// 폰이 이 매니페스트를 처리할 수 있나.
  bool get supported => version > 0 && version <= kSyncProtocolVersion;
}

class SyncPlanner {
  SyncPlanner._();

  /// 받아야 할 파일 목록을 고른다.
  ///
  /// [localStats]는 폰에 이미 있는 반주 파일의 크기·수정시각(파일명 기준).
  /// 크기가 같으면 받지 않는다 — 같은 파일을 매번 다시 받으면 동기화가
  /// 아니라 재다운로드다. mtime은 플랫폼마다 정밀도가 달라 판정에 쓰지 않고
  /// 표시용으로만 남긴다.
  static List<SyncDownload> plan({
    required SyncManifest manifest,
    required Map<String, TrackStat> localStats,
  }) {
    final out = <SyncDownload>[];
    for (final song in manifest.songs) {
      final id = (song['id'] as String?) ?? '';
      if (id.isEmpty) continue;
      for (final raw in (song['tracks'] as List<dynamic>? ?? const [])) {
        if (raw is! Map<String, dynamic>) continue;
        final name = (raw['fileName'] as String?) ?? '';
        if (name.isEmpty) continue;
        final size = (raw['size'] as num?)?.toInt() ?? 0;
        final local = localStats[name];
        if (local == null) {
          out.add(
            SyncDownload(songId: id, fileName: name, size: size, isNew: true),
          );
        } else if (local.size != size) {
          out.add(
            SyncDownload(songId: id, fileName: name, size: size, isNew: false),
          );
        }
      }
    }
    return out;
  }

  /// 받을 파일들의 총 바이트 — 진행률·안내에 쓴다.
  static int totalBytes(List<SyncDownload> downloads) =>
      downloads.fold(0, (sum, d) => sum + d.size);
}

/// 폰이 PC로 올려보내는 변경분(역방향).
///
/// 곡·가사·반주는 여전히 PC가 정본이다. 폰이 만드는 값만 올린다 —
/// 즐겨찾기 토글과 연습기록. 둘 다 폰에서만 생기는 정보라 PC를 덮어쓰는
/// 게 아니라 보태는 쪽이다.
class SyncPushPayload {
  /// 폰에서 바꾼 즐겨찾기만 담는다(songId → 켬/끔). 전체 목록을 보내면
  /// PC에서 끈 즐겨찾기를 폰이 되살려 버린다.
  final Map<String, bool> favorites;

  /// 폰에서 쌓인 연습기록 전부. 병합은 id 기준이라 중복은 무시된다.
  final List<PracticeSession> practiceSessions;

  const SyncPushPayload({
    this.favorites = const {},
    this.practiceSessions = const [],
  });

  bool get isEmpty => favorites.isEmpty && practiceSessions.isEmpty;

  Map<String, dynamic> toJson() => {
    'version': kSyncProtocolVersion,
    'favorites': favorites,
    'practiceSessions': [for (final s in practiceSessions) s.toJson()],
  };

  static SyncPushPayload fromJson(Map<String, dynamic> json) {
    final favs = <String, bool>{};
    final rawFavs = json['favorites'];
    if (rawFavs is Map) {
      rawFavs.forEach((k, v) {
        if (k is String && v is bool) favs[k] = v;
      });
    }
    final sessions = <PracticeSession>[];
    final rawSessions = json['practiceSessions'];
    if (rawSessions is List) {
      for (final raw in rawSessions) {
        if (raw is! Map) continue;
        try {
          sessions.add(
            PracticeSession.fromJson(raw.cast<String, dynamic>()),
          );
        } catch (_) {
          // 한 건이 깨져도 나머지는 살린다.
        }
      }
    }
    return SyncPushPayload(favorites: favs, practiceSessions: sessions);
  }
}

/// 역방향 병합 결과 — 무엇이 실제로 바뀌었는지.
class SyncMergeResult {
  final List<Song> songs;
  final List<PracticeSession> sessions;
  final int favoritesApplied;
  final int sessionsAdded;

  const SyncMergeResult({
    required this.songs,
    required this.sessions,
    required this.favoritesApplied,
    required this.sessionsAdded,
  });
}

class SyncMerger {
  SyncMerger._();

  /// 폰이 올린 변경분을 PC 상태에 얹는다.
  ///
  /// - 즐겨찾기: 값이 실제로 다를 때만 바꾼다(같은 값이면 저장도 하지 않는다).
  ///   모르는 곡 id는 조용히 무시한다 — PC에서 지운 곡일 수 있다.
  /// - 연습기록: id 기준 합집합. 같은 회차를 두 번 보내도 늘지 않는다.
  static SyncMergeResult merge({
    required List<Song> songs,
    required List<PracticeSession> sessions,
    required SyncPushPayload payload,
  }) {
    var applied = 0;
    final nextSongs = [
      for (final song in songs)
        if (payload.favorites.containsKey(song.id) &&
            payload.favorites[song.id] != song.isFavorite)
          () {
            applied++;
            return song.copyWith(isFavorite: payload.favorites[song.id]);
          }()
        else
          song,
    ];

    final known = {for (final s in sessions) s.id};
    final added = [
      for (final s in payload.practiceSessions)
        if (!known.contains(s.id)) s,
    ];

    return SyncMergeResult(
      songs: nextSongs,
      sessions: [...sessions, ...added],
      favoritesApplied: applied,
      sessionsAdded: added.length,
    );
  }
}
