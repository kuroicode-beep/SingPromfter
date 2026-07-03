import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/queue_item.dart';
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

    test('reorder ignores invalid target', () {
      final next = QueueLogic.reorder(queue, 0, 99);

      expect(identical(next, queue), isTrue);
    });
  });
}
