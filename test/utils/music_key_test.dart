import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/utils/music_key.dart';

void main() {
  group('label', () {
    test('장조는 음 이름 그대로', () {
      expect(const MusicKey(0, KeyMode.major).label, 'C');
      expect(const MusicKey(7, KeyMode.major).label, 'G');
    });

    test('단조는 m을 붙인다', () {
      expect(const MusicKey(9, KeyMode.minor).label, 'Am');
      expect(const MusicKey(3, KeyMode.minor).label, 'E♭m');
    });
  });

  group('transposed', () {
    test('반음 위·아래로 옮긴다', () {
      expect(const MusicKey(0, KeyMode.major).transposed(2).label, 'D');
      expect(const MusicKey(0, KeyMode.major).transposed(-2).label, 'B♭');
    });

    test('한 바퀴 돌면 제자리', () {
      const key = MusicKey(5, KeyMode.minor);
      expect(key.transposed(12), key);
      expect(key.transposed(-12), key);
    });

    test('장·단은 바뀌지 않는다', () {
      expect(const MusicKey(9, KeyMode.minor).transposed(3).mode, KeyMode.minor);
    });
  });

  group('저장·복원', () {
    test('왕복해도 같다', () {
      for (var pc = 0; pc < 12; pc++) {
        for (final mode in KeyMode.values) {
          final key = MusicKey(pc, mode);
          expect(MusicKey.fromStorage(key.storageValue), key);
        }
      }
    });

    test('망가진 값은 null', () {
      expect(MusicKey.fromStorage(null), isNull);
      expect(MusicKey.fromStorage(''), isNull);
      expect(MusicKey.fromStorage('12:major'), isNull);
      expect(MusicKey.fromStorage('3:dorian'), isNull);
      expect(MusicKey.fromStorage('C'), isNull);
    });
  });

  group('parse', () {
    test('사람이 쓰는 표기를 읽는다', () {
      expect(MusicKey.parse('C'), const MusicKey(0, KeyMode.major));
      expect(MusicKey.parse('Am'), const MusicKey(9, KeyMode.minor));
      expect(MusicKey.parse(' G '), const MusicKey(7, KeyMode.major));
      expect(MusicKey.parse('F#m'), const MusicKey(6, KeyMode.minor));
      expect(MusicKey.parse('Bb'), const MusicKey(10, KeyMode.major));
    });

    test('이명동음도 받는다', () {
      expect(MusicKey.parse('D#'), const MusicKey(3, KeyMode.major));
      expect(MusicKey.parse('Gb'), const MusicKey(6, KeyMode.major));
      expect(MusicKey.parse('A#m'), const MusicKey(10, KeyMode.minor));
    });

    test('읽을 수 없으면 null', () {
      expect(MusicKey.parse(null), isNull);
      expect(MusicKey.parse(''), isNull);
      expect(MusicKey.parse('   '), isNull);
      expect(MusicKey.parse('H'), isNull);
      expect(MusicKey.parse('m'), isNull);
    });

    test('label을 다시 읽으면 같은 조성', () {
      for (var pc = 0; pc < 12; pc++) {
        for (final mode in KeyMode.values) {
          final key = MusicKey(pc, mode);
          expect(MusicKey.parse(key.label), key, reason: key.label);
        }
      }
    });
  });
}
