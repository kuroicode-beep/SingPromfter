import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/backing_track.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/models/track_variant.dart';

void main() {
  group('Song serialization', () {
    test('toJson/fromJson preserves current fields including artist', () {
      final original = Song(
        id: 'song-1',
        title: '테스트 곡',
        artist: '테스트 가수',
        lyricsPath: 'C:/data/txt/test.txt',
        lyricsText: '가사 내용',
        backingTracks: const [
          BackingTrack(
            slot: 1,
            fileName: 'test_mr1.mp3',
            label: '원곡',
            startMs: 1000,
            endMs: 90000,
          ),
          BackingTrack(slot: 2, fileName: 'test_mr2.mp3', label: '낮은키'),
        ],
        createdAt: DateTime(2026, 7, 4),
        updatedAt: DateTime(2026, 7, 4, 1),
        isFavorite: true,
      );

      final restored = Song.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.artist, '테스트 가수');
      expect(restored.lyricsText, original.lyricsText);
      expect(restored.isFavorite, isTrue);
      expect(restored.backingTracks, hasLength(2));
      expect(restored.backingTracks.first.label, '원곡');
      expect(restored.backingTracks.first.startMs, 1000);
      expect(restored.backingTracks.first.endMs, 90000);
    });

    test('fromJson without artist defaults to empty string', () {
      final song = Song.fromJson({
        'id': 'legacy-artist',
        'title': '구버전 곡',
      });

      expect(song.artist, '');
    });

    test('폴더는 저장·복원되고 구버전 곡은 폴더 없음', () {
      final legacy = Song.fromJson({'id': 'a', 'title': '옛 곡'});
      expect(legacy.folder, '');

      final tagged = legacy.copyWith(folder: '유선');
      final restored = Song.fromJson(tagged.toJson());
      expect(restored.folder, '유선');
    });

    test('folderNames는 빈 폴더를 빼고 중복 없이 가나다순', () {
      Song make(String id, String folder) => Song.fromJson({
        'id': id,
        'title': id,
        'folder': folder,
      });
      final names = Song.folderNames([
        make('a', '트로트'),
        make('b', ''),
        make('c', '발라드'),
        make('d', '트로트'),
      ]);
      expect(names, ['발라드', '트로트']);
    });

    test('legacy mrFileName migrates to slot 1 backing track', () {
      final song = Song.fromJson({
        'id': 'legacy-1',
        'title': '구버전 곡',
        'mrFileName': 'old.mp3',
      });

      expect(song.backingTracks, hasLength(1));
      expect(song.backingTracks.first.slot, 1);
      expect(song.backingTracks.first.fileName, 'old.mp3');
      expect(song.backingTracks.first.label, 'MR1');
    });

    test('encodeList/decodeList round-trips songs', () {
      final songs = [
        Song(
          id: 'song-1',
          title: '노래',
          lyricsPath: '노래.txt',
          lyricsText: '가사',
          backingTracks: const [],
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ];

      final decoded = Song.decodeList(Song.encodeList(songs));

      expect(decoded, hasLength(1));
      expect(decoded.first.title, '노래');
      expect(decoded.first.lyricsText, '가사');
    });
  });

  // 사용자가 정한 규약: 1·2·3은 같은 녹음이라 싱크가 연동되고, 4번(노래방)은
  // 다른 링크로 가져온 다른 녹음이라 따로 저장된다.
  group('가사 싱크 슬롯 묶음', () {
    Song songWithSlots(List<int> slots) => Song(
      id: 'song-sync',
      title: '선물',
      lyricsPath: 'x.txt',
      lyricsText: '한 줄',
      backingTracks: [
        for (final slot in slots)
          BackingTrack(slot: slot, fileName: 'f$slot.mp3', label: '$slot'),
      ],
      createdAt: DateTime(2026, 7, 30),
      updatedAt: DateTime(2026, 7, 30),
    );

    test('묶음 규약 — 1·2·3은 한 덩어리, 4는 홀로', () {
      expect(lyricsSyncSlotGroup(1), [1, 2, 3]);
      expect(lyricsSyncSlotGroup(2), [1, 2, 3]);
      expect(lyricsSyncSlotGroup(3), [1, 2, 3]);
      expect(lyricsSyncSlotGroup(4), [4]);
    });

    test('1번에서 맞추면 2·3번도 같이 맞는다 — 슬롯을 바꿔도 유지', () {
      final updated = songWithSlots([1, 2, 3, 4]).withLyricsOffsetForSlot(
        1,
        -1500,
      );
      expect(updated.trackForSlot(1)!.lyricsOffsetMs, -1500);
      expect(updated.trackForSlot(2)!.lyricsOffsetMs, -1500);
      expect(updated.trackForSlot(3)!.lyricsOffsetMs, -1500);
    });

    test('1번에서 맞춰도 노래방(4번)은 건드리지 않는다', () {
      final updated = songWithSlots([1, 2, 3, 4]).withLyricsOffsetForSlot(
        1,
        -1500,
      );
      expect(updated.trackForSlot(4)!.lyricsOffsetMs, 0);
    });

    test('노래방에서 맞추면 1·2·3은 그대로 — 다른 녹음이니까', () {
      final base = songWithSlots([1, 2, 3, 4]).withLyricsOffsetForSlot(1, -800);
      final updated = base.withLyricsOffsetForSlot(4, 2200);
      expect(updated.trackForSlot(4)!.lyricsOffsetMs, 2200);
      expect(updated.trackForSlot(1)!.lyricsOffsetMs, -800);
      expect(updated.trackForSlot(2)!.lyricsOffsetMs, -800);
      expect(updated.trackForSlot(3)!.lyricsOffsetMs, -800);
    });

    test('없는 슬롯이면 아무것도 바뀌지 않는다', () {
      final song = songWithSlots([1, 2]);
      expect(song.withLyricsOffsetForSlot(4, 500), same(song));
    });

    test('아직 없는 슬롯은 만들지 않는다 — 1번만 있어도 안전하다', () {
      final updated = songWithSlots([1]).withLyricsOffsetForSlot(1, -300);
      expect(updated.backingTracks.length, 1);
      expect(updated.trackForSlot(1)!.lyricsOffsetMs, -300);
    });
  });
}
