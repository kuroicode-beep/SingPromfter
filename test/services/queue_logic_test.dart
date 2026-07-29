import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/prompter_settings.dart';
import 'package:singpromfter_app/models/queue_item.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/services/queue_logic.dart';

void main() {
  group('QueueLogic', () {
    final queue = [
      QueueItem(songId: 'a', queuedAt: DateTime(2026)),
      QueueItem(songId: 'b', queuedAt: DateTime(2026)),
      QueueItem(songId: 'c', queuedAt: DateTime(2026)),
    ];

    test('removeAt removes valid index', () {
      final next = QueueLogic.removeAt(queue, 1);

      expect(next.map((item) => item.songId), ['a', 'c']);
    });

    test('removeAt ignores invalid index', () {
      final next = QueueLogic.removeAt(queue, 99);

      expect(identical(next, queue), isTrue);
    });

    test('reorder moves item with ReorderableListView index semantics', () {
      final next = QueueLogic.reorder(queue, 0, 3);

      expect(next.map((item) => item.songId), ['b', 'c', 'a']);
    });

    test('rawIndexForAdjusted 왕복 — onReorderItem 보정 인덱스가 그 자리로 간다', () {
      // Flutter 3.41 onReorderItem은 보정된 newIndex를 준다. raw 변환을
      // 거쳐 reorder에 넣으면 항목이 정확히 그 보정 인덱스에 놓여야 한다.
      for (final (oldIndex, adjusted) in [(0, 2), (2, 0), (1, 1), (0, 1)]) {
        final raw = QueueLogic.rawIndexForAdjusted(oldIndex, adjusted);
        final next = QueueLogic.reorder(queue, oldIndex, raw);
        expect(
          next[adjusted].songId,
          queue[oldIndex].songId,
          reason: '이동 \$oldIndex→\$adjusted (raw \$raw)',
        );
      }
    });

    test('reorder ignores invalid target', () {
      final next = QueueLogic.reorder(queue, 0, 99);

      expect(identical(next, queue), isTrue);
    });

    test('appendSongs adds each song to queue', () {
      final songs = [
        Song(
          id: '1',
          title: 'A',
          lyricsPath: 'a.txt',
          lyricsText: '가사',
          backingTracks: const [],
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
        Song(
          id: '2',
          title: 'B',
          lyricsPath: 'b.txt',
          lyricsText: '가사',
          backingTracks: const [],
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ];

      final next = QueueLogic.appendSongs(
        queue: const [],
        songs: songs,
        settings: const PrompterSettings(),
      );

      expect(next, hasLength(2));
      expect(next.map((item) => item.songId), ['1', '2']);
    });
  });
}
