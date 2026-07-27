import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/backing_track.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/services/song_sort_service.dart';

Song song({
  required String id,
  required String title,
  DateTime? createdAt,
  List<BackingTrack> tracks = const [],
  String? lrc,
}) {
  final now = createdAt ?? DateTime(2026, 1, 1);
  return Song(
    id: id,
    title: title,
    lyricsPath: '$id.txt',
    lyricsText: '',
    backingTracks: tracks,
    createdAt: now,
    updatedAt: now,
    lrcFileName: lrc,
  );
}

BackingTrack track(String fileName) =>
    BackingTrack(slot: 1, fileName: fileName, label: 'MR1');

void main() {
  group('SongSortService.sort', () {
    final songs = [
      song(id: 'b', title: '나비', createdAt: DateTime(2026, 3, 1)),
      song(id: 'a', title: '가을', createdAt: DateTime(2026, 5, 1)),
      song(id: 'c', title: '다리', createdAt: DateTime(2026, 1, 1)),
    ];

    test('제목순', () {
      final sorted = SongSortService.sort(songs, mode: SongSortMode.title);
      expect(sorted.map((s) => s.title), ['가을', '나비', '다리']);
    });

    test('최근 등록순', () {
      final sorted = SongSortService.sort(
        songs,
        mode: SongSortMode.recentlyAdded,
      );
      expect(sorted.map((s) => s.id), ['a', 'b', 'c']);
    });

    test('많이 부른 순', () {
      final sorted = SongSortService.sort(
        songs,
        mode: SongSortMode.mostPracticed,
        practiceCounts: {'a': 1, 'b': 9, 'c': 5},
      );
      expect(sorted.map((s) => s.id), ['b', 'c', 'a']);
    });

    test('덜 부른 순 — 기록 없는 곡이 먼저', () {
      final sorted = SongSortService.sort(
        songs,
        mode: SongSortMode.leastPracticed,
        practiceCounts: {'a': 3, 'b': 9},
      );
      expect(sorted.first.id, 'c'); // 기록 없음 = 0회
    });

    test('횟수가 같으면 제목순으로 안정 정렬', () {
      final sorted = SongSortService.sort(
        songs,
        mode: SongSortMode.mostPracticed,
        practiceCounts: {'a': 2, 'b': 2, 'c': 2},
      );
      expect(sorted.map((s) => s.title), ['가을', '나비', '다리']);
    });

    test('원본 목록을 바꾸지 않는다', () {
      final original = List<Song>.from(songs);
      SongSortService.sort(songs, mode: SongSortMode.recentlyAdded);
      expect(songs.map((s) => s.id), original.map((s) => s.id));
    });
  });

  group('findDuplicateTitles', () {
    test('대소문자·공백 무시하고 묶는다', () {
      final groups = SongSortService.findDuplicateTitles([
        song(id: '1', title: '봄날'),
        song(id: '2', title: ' 봄날 '),
        song(id: '3', title: '여름'),
      ]);
      expect(groups, hasLength(1));
      expect(groups.first.map((s) => s.id), ['1', '2']);
    });

    test('중복이 없으면 빈 목록', () {
      final groups = SongSortService.findDuplicateTitles([
        song(id: '1', title: 'A'),
        song(id: '2', title: 'B'),
      ]);
      expect(groups, isEmpty);
    });
  });

  group('LibraryAudit.compare', () {
    test('참조되지 않는 파일을 고아로 본다', () {
      final audit = LibraryAudit.compare(
        songs: [
          song(id: '1', title: 'A', tracks: [track('a_mr1.mp3')], lrc: '1.lrc'),
        ],
        trackFilesOnDisk: ['a_mr1.mp3', '버려진.mp3'],
        lrcFilesOnDisk: ['1.lrc', 'orphan.lrc'],
      );
      expect(audit.orphanTrackFiles, ['버려진.mp3']);
      expect(audit.orphanLrcFiles, ['orphan.lrc']);
      expect(audit.orphanCount, 2);
      expect(audit.isClean, isFalse);
    });

    test('파일이 사라진 곡을 찾는다', () {
      final audit = LibraryAudit.compare(
        songs: [
          song(id: '1', title: 'A', tracks: [track('없어진.mp3')]),
        ],
        trackFilesOnDisk: const [],
        lrcFilesOnDisk: const [],
      );
      expect(audit.songsWithMissingTracks, hasLength(1));
    });

    test('모두 맞으면 깨끗하다', () {
      final audit = LibraryAudit.compare(
        songs: [song(id: '1', title: 'A', tracks: [track('a.mp3')])],
        trackFilesOnDisk: ['a.mp3'],
        lrcFilesOnDisk: const [],
      );
      expect(audit.isClean, isTrue);
    });

    test('빈 라이브러리도 안전하다', () {
      final audit = LibraryAudit.compare(
        songs: const [],
        trackFilesOnDisk: const [],
        lrcFilesOnDisk: const [],
      );
      expect(audit.isClean, isTrue);
    });
  });

  group('SongSortMode 저장값', () {
    test('왕복, 알 수 없는 값은 제목순', () {
      for (final mode in SongSortMode.values) {
        expect(SongSortModeInfo.fromStorage(mode.storageValue), mode);
        expect(mode.label, isNotEmpty);
      }
      expect(SongSortModeInfo.fromStorage('bogus'), SongSortMode.title);
    });
  });
}
