// file: test/services/sync_protocol_test.dart
//
// 동기화 델타 규칙. 같은 파일을 매번 다시 받으면 동기화가 아니라
// 재다운로드다 — 2회차에 받을 게 없어야 한다는 게 핵심 단언이다.
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/backing_track.dart';
import 'package:singpromfter_app/models/practice_session.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/services/sync_protocol.dart';

Song _song({
  String id = 's1',
  String title = '밤편지',
  List<BackingTrack> tracks = const [],
  String lyrics = '가사 한 줄',
}) => Song(
  id: id,
  title: title,
  artist: '아이유',
  lyricsPath: '$title.txt',
  lyricsText: lyrics,
  backingTracks: tracks,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  group('매니페스트 생성', () {
    test('가사·싱크가사는 본문을 싣고 반주는 크기만 싣는다', () {
      final manifest = SyncManifest.build(
        songs: [
          _song(
            tracks: const [
              BackingTrack(slot: 1, fileName: 'a.mp3', label: '원곡'),
            ],
          ),
        ],
        appVersion: '5.7.0',
        lrcBySongId: {'s1': '[00:01.00]가사 한 줄'},
        trackStats: {'a.mp3': (size: 4096, mtime: '2026-08-18T00:00:00.000Z')},
      );

      expect(manifest.version, kSyncProtocolVersion);
      expect(manifest.songs, hasLength(1));
      final song = manifest.songs.first;
      expect(song['lyricsText'], '가사 한 줄');
      expect(song['lrc'], '[00:01.00]가사 한 줄');
      final tracks = song['tracks'] as List<dynamic>;
      expect(tracks, hasLength(1));
      expect((tracks.first as Map)['size'], 4096);
    });

    test('파일이 없는 반주는 매니페스트에서 뺀다 — 받으러 왔다 404를 맞지 않게', () {
      final manifest = SyncManifest.build(
        songs: [
          _song(
            tracks: const [
              BackingTrack(slot: 1, fileName: 'a.mp3', label: '원곡'),
              BackingTrack(slot: 2, fileName: 'missing.mp3', label: 'MR'),
            ],
          ),
        ],
        appVersion: '5.7.0',
        lrcBySongId: const {},
        trackStats: {'a.mp3': (size: 10, mtime: 'x')},
      );

      final tracks = manifest.songs.first['tracks'] as List<dynamic>;
      expect(tracks, hasLength(1));
      expect((tracks.first as Map)['fileName'], 'a.mp3');
    });

    test('JSON 왕복이 보존된다', () {
      final manifest = SyncManifest.build(
        songs: [_song()],
        appVersion: '5.7.0',
        lrcBySongId: const {},
        trackStats: const {},
      );
      final restored = SyncManifest.fromJson(manifest.toJson());
      expect(restored.version, manifest.version);
      expect(restored.appVersion, '5.7.0');
      expect(restored.songs, hasLength(1));
      expect(restored.supported, isTrue);
    });

    test('폰이 모르는 상위 버전은 받지 않는다', () {
      final future = SyncManifest.fromJson({
        'version': kSyncProtocolVersion + 1,
        'appVersion': '9.0.0',
        'songs': const <Map<String, dynamic>>[],
      });
      expect(future.supported, isFalse);
    });
  });

  group('델타 계획', () {
    SyncManifest manifestWith(int size) => SyncManifest.build(
      songs: [
        _song(
          tracks: const [BackingTrack(slot: 1, fileName: 'a.mp3', label: '원곡')],
        ),
      ],
      appVersion: '5.7.0',
      lrcBySongId: const {},
      trackStats: {'a.mp3': (size: size, mtime: 'x')},
    );

    test('로컬에 없으면 신규로 받는다', () {
      final plan = SyncPlanner.plan(
        manifest: manifestWith(4096),
        localStats: const {},
      );
      expect(plan, hasLength(1));
      expect(plan.first.fileName, 'a.mp3');
      expect(plan.first.isNew, isTrue);
      expect(SyncPlanner.totalBytes(plan), 4096);
    });

    test('크기가 같으면 받지 않는다 — 2회차에 재다운로드가 없어야 한다', () {
      final plan = SyncPlanner.plan(
        manifest: manifestWith(4096),
        localStats: {'a.mp3': (size: 4096, mtime: '아무거나')},
      );
      expect(plan, isEmpty);
    });

    test('크기가 다르면 변경으로 받는다', () {
      final plan = SyncPlanner.plan(
        manifest: manifestWith(8192),
        localStats: {'a.mp3': (size: 4096, mtime: 'x')},
      );
      expect(plan, hasLength(1));
      expect(plan.first.isNew, isFalse);
    });

    test('mtime만 달라도 다시 받지 않는다 — 플랫폼마다 정밀도가 다르다', () {
      final plan = SyncPlanner.plan(
        manifest: manifestWith(4096),
        localStats: {'a.mp3': (size: 4096, mtime: '2000-01-01T00:00:00.000Z')},
      );
      expect(plan, isEmpty);
    });
  });

  group('역방향 병합 (폰 → PC)', () {
    PracticeSession session(String id) => PracticeSession(
      id: id,
      songId: 's1',
      songTitle: '밤편지',
      startedAt: DateTime(2026, 8, 18, 20),
      durationMs: 210000,
    );

    test('즐겨찾기는 값이 다를 때만 반영된다', () {
      final result = SyncMerger.merge(
        songs: [_song(id: 's1'), _song(id: 's2', title: '봄날')],
        sessions: const [],
        payload: const SyncPushPayload(favorites: {'s1': true, 's2': false}),
      );
      // s2는 원래 false라 바뀐 게 없다.
      expect(result.favoritesApplied, 1);
      expect(result.songs.firstWhere((s) => s.id == 's1').isFavorite, isTrue);
      expect(result.songs.firstWhere((s) => s.id == 's2').isFavorite, isFalse);
    });

    test('모르는 곡 id는 조용히 무시한다 — PC에서 지운 곡일 수 있다', () {
      final result = SyncMerger.merge(
        songs: [_song(id: 's1')],
        sessions: const [],
        payload: const SyncPushPayload(favorites: {'없는곡': true}),
      );
      expect(result.favoritesApplied, 0);
      expect(result.songs, hasLength(1));
    });

    test('연습기록은 id 합집합 — 같은 회차를 두 번 올려도 늘지 않는다', () {
      final payload = SyncPushPayload(
        practiceSessions: [session('a'), session('b')],
      );
      final first = SyncMerger.merge(
        songs: const [],
        sessions: [session('a')],
        payload: payload,
      );
      expect(first.sessionsAdded, 1);
      expect(first.sessions, hasLength(2));

      // 같은 payload를 다시 올린다 — 이번엔 늘지 않아야 한다.
      final second = SyncMerger.merge(
        songs: const [],
        sessions: first.sessions,
        payload: payload,
      );
      expect(second.sessionsAdded, 0);
      expect(second.sessions, hasLength(2));
    });

    test('올릴 게 없으면 isEmpty', () {
      expect(const SyncPushPayload().isEmpty, isTrue);
      expect(
        const SyncPushPayload(favorites: {'s1': true}).isEmpty,
        isFalse,
      );
    });

    test('JSON 왕복 — 깨진 세션 한 건이 나머지를 죽이지 않는다', () {
      final payload = SyncPushPayload(
        favorites: const {'s1': true},
        practiceSessions: [session('a')],
      );
      final json = payload.toJson();
      (json['practiceSessions'] as List).add({'broken': true});
      final restored = SyncPushPayload.fromJson(json);
      expect(restored.favorites, {'s1': true});
      expect(restored.practiceSessions.map((s) => s.id), contains('a'));
    });
  });
}
