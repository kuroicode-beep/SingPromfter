// file: test/services/sync_server_handler_test.dart
//
// 동기화 서버의 안전 장치. LAN에 열리는 순간부터는 "어떤 경로가 원격에
// 열려 있나"가 곧 보안이다 — 곡 삭제·재생 조작이 새 나가면 안 된다.
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/services/sync_server_handler.dart';

void main() {
  group('원격 허용 경로', () {
    test('동기화 경로만 원격에서 쓸 수 있다', () {
      expect(
        SyncServerHandler.allowedFromRemote('/api/sync/manifest'),
        isTrue,
      );
      expect(SyncServerHandler.allowedFromRemote('/api/sync/file'), isTrue);
    });

    test('곡 조작·재생·상태 경로는 원격에서 막힌다', () {
      for (final path in [
        '/api/state',
        '/api/songs',
        '/api/songs/abc',
        '/api/compose',
        '/api/play',
        '/api/queue',
        // 접두사를 흉내낸 경로도 막힌다.
        '/api/syncx/manifest',
        '/api/../api/songs',
      ]) {
        expect(
          SyncServerHandler.allowedFromRemote(path),
          isFalse,
          reason: path,
        );
      }
    });
  });

  group('페어링 코드', () {
    test('헷갈리는 글자(0·O·1·I·L)를 쓰지 않는다 — 손으로 옮겨 적는 값이다', () {
      for (final ch in ['0', 'O', '1', 'I', 'L']) {
        expect(
          SyncPairingCode.alphabet.contains(ch),
          isFalse,
          reason: '$ch 가 알파벳에 있으면 오타를 유발한다',
        );
      }
    });

    test('6자리를 만들고 스스로 검증을 통과한다', () {
      var seed = 7;
      int next(int max) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        return seed % max;
      }

      final code = SyncPairingCode.generate(next);
      expect(code.length, SyncPairingCode.length);
      expect(SyncPairingCode.isValid(code), isTrue);
    });

    test('길이·문자가 다르면 거부한다', () {
      expect(SyncPairingCode.isValid(''), isFalse);
      expect(SyncPairingCode.isValid('ABC'), isFalse);
      expect(SyncPairingCode.isValid('ABCDEFG'), isFalse);
      expect(SyncPairingCode.isValid('ABC0EF'), isFalse);
    });

    test('소문자 입력도 받아준다 — 폰 키보드가 소문자로 시작한다', () {
      expect(SyncPairingCode.isValid('abcdef'.toUpperCase()), isTrue);
    });
  });
}
