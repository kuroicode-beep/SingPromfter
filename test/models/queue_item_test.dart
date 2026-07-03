import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/queue_item.dart';

void main() {
  group('QueueItem', () {
    test('encodeList/decodeList preserves queue items', () {
      final original = [
        QueueItem(
          songId: 'song-1',
          selectedTrackSlot: 2,
          queuedAt: DateTime(2026, 7, 4, 10),
        ),
      ];

      final decoded = QueueItem.decodeList(QueueItem.encodeList(original));

      expect(decoded, hasLength(1));
      expect(decoded.first.songId, 'song-1');
      expect(decoded.first.selectedTrackSlot, 2);
      expect(decoded.first.queuedAt, DateTime(2026, 7, 4, 10));
    });
  });
}
