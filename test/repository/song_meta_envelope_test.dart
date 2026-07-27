import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/repository/song_meta_store.dart';

// v1.3.0에서 도입한 songs.json 봉투 형식의 디코드 규칙을 고정한다.
// v1(맨 배열) 호환, v2 봉투, 상위 버전 거부가 핵심이다.
void main() {
  Map<String, dynamic> entry(String id) => {'id': id, 'title': '곡$id'};

  group('SongMetaStore.decodeEntries', () {
    test('v1 맨 배열을 그대로 읽는다 (구버전 데이터 호환)', () {
      final raw = jsonEncode([entry('a'), entry('b')]);
      final entries = SongMetaStore.decodeEntries(raw);
      expect(entries, hasLength(2));
      expect(entries.first['id'], 'a');
    });

    test('v2 봉투를 읽는다', () {
      final raw = jsonEncode({
        'schemaVersion': 2,
        'songs': [entry('a')],
      });
      final entries = SongMetaStore.decodeEntries(raw);
      expect(entries, hasLength(1));
      expect(entries.single['id'], 'a');
    });

    test('상위 버전(v99)은 예외로 거부한다 — 덮어쓰기 방지의 근거', () {
      final raw = jsonEncode({
        'schemaVersion': 99,
        'songs': [entry('a')],
      });
      expect(
        () => SongMetaStore.decodeEntries(raw),
        throwsA(isA<SongMetaSchemaException>()),
      );
    });

    test('버전 필드가 없는 봉투는 현재 버전으로 간주한다', () {
      final raw = jsonEncode({
        'songs': [entry('a')],
      });
      expect(SongMetaStore.decodeEntries(raw), hasLength(1));
    });

    test('songs가 없거나 형식이 이상하면 빈 목록', () {
      expect(SongMetaStore.decodeEntries(jsonEncode({'schemaVersion': 2})), isEmpty);
      expect(SongMetaStore.decodeEntries(jsonEncode('문자열')), isEmpty);
      expect(
        SongMetaStore.decodeEntries(jsonEncode({'songs': '배열 아님'})),
        isEmpty,
      );
    });

    test('배열 안의 비객체 항목은 걸러낸다', () {
      final raw = jsonEncode([entry('a'), 'noise', 42]);
      final entries = SongMetaStore.decodeEntries(raw);
      expect(entries, hasLength(1));
    });

    test('예외 메시지는 사용자 안내에 쓸 한국어 문장이다', () {
      final raw = jsonEncode({'schemaVersion': 3, 'songs': <Object>[]});
      try {
        SongMetaStore.decodeEntries(raw);
        fail('예외가 나야 한다');
      } on SongMetaSchemaException catch (e) {
        expect(e.message, contains('업데이트'));
        expect(e.toString(), e.message);
      }
    });
  });
}
