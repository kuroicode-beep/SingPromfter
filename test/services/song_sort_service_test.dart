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

  // 드래그 재정렬(v2.14.0) — 화면 인덱스를 저장 순서에 반영하는 순수 로직.
  group('내 순서(manual)와 applyVisibleReorder', () {
    List<Song> five() => [
      for (final id in ['a', 'b', 'c', 'd', 'e']) song(id: id, title: id),
    ];

    List<String> ids(List<Song> list) =>
        list.map((s) => s.id).toList(growable: false);

    test('manual 정렬은 저장 순서를 그대로 둔다', () {
      final all = five();
      expect(
        ids(SongSortService.sort(all, mode: SongSortMode.manual)),
        ['a', 'b', 'c', 'd', 'e'],
      );
    });

    test('전체가 보일 때 앞으로 끌기', () {
      // d(3)를 b 자리(1)로 — 보정 인덱스 규약: 제거 후 목록 기준.
      final next = SongSortService.applyVisibleReorder(
        all: five(),
        visibleIds: ['a', 'b', 'c', 'd', 'e'],
        oldIndex: 3,
        newIndex: 1,
      );
      expect(ids(next), ['a', 'd', 'b', 'c', 'e']);
    });

    test('전체가 보일 때 맨 끝으로 끌기', () {
      final next = SongSortService.applyVisibleReorder(
        all: five(),
        visibleIds: ['a', 'b', 'c', 'd', 'e'],
        oldIndex: 0,
        newIndex: 4,
      );
      expect(ids(next), ['b', 'c', 'd', 'e', 'a']);
    });

    test('필터로 일부만 보일 때 — 안 보이는 곡의 상대 순서는 유지된다', () {
      // 전체 a b c d e, 보이는 것은 a c e. c를 a 앞으로 끌면
      // c는 전체에서 a 바로 앞으로 가고 b·d는 제자리 관계를 지킨다.
      final next = SongSortService.applyVisibleReorder(
        all: five(),
        visibleIds: ['a', 'c', 'e'],
        oldIndex: 1,
        newIndex: 0,
      );
      expect(ids(next), ['c', 'a', 'b', 'd', 'e']);
    });

    test('필터 중 맨 끝으로 — 마지막으로 보이던 곡 바로 뒤', () {
      // a를 보이는 목록(a c e)의 끝으로 → e 바로 뒤(= d와 e 사이가 아니라 e 다음).
      final next = SongSortService.applyVisibleReorder(
        all: five(),
        visibleIds: ['a', 'c', 'e'],
        oldIndex: 0,
        newIndex: 2,
      );
      expect(ids(next), ['b', 'c', 'd', 'e', 'a']);
    });

    test('깨진 입력(없는 id·범위 밖)은 원본을 그대로 돌려준다', () {
      final all = five();
      expect(
        SongSortService.applyVisibleReorder(
          all: all,
          visibleIds: ['x', 'y'],
          oldIndex: 0,
          newIndex: 1,
        ),
        same(all),
      );
      expect(
        SongSortService.applyVisibleReorder(
          all: all,
          visibleIds: ['a', 'b'],
          oldIndex: 9,
          newIndex: 0,
        ),
        same(all),
      );
    });

    test('제자리 드래그는 순서를 바꾸지 않는다', () {
      final next = SongSortService.applyVisibleReorder(
        all: five(),
        visibleIds: ['a', 'b', 'c', 'd', 'e'],
        oldIndex: 2,
        newIndex: 2,
      );
      expect(ids(next), ['a', 'b', 'c', 'd', 'e']);
    });
  });
}
