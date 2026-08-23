// file: test/services/sync_discovery_test.dart
//
// UDP 탐색의 규칙. 남의 브로드캐스트에 답하지 않고, 응답에 비밀을 담지
// 않는 것 — 이 둘이 핵심이다. 소켓 없이 인코딩·디코딩만 검증한다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/services/sync_discovery.dart';

void main() {
  group('인사말 판별', () {
    test('우리 인사말만 통과한다', () {
      expect(SyncDiscovery.isProbe(utf8.encode(kSyncDiscoveryProbe)), isTrue);
      // 앞뒤 공백은 허용 — 보내는 쪽 구현이 개행을 붙여도 동작해야 한다.
      expect(
        SyncDiscovery.isProbe(utf8.encode('$kSyncDiscoveryProbe\n')),
        isTrue,
      );
    });

    test('남의 브로드캐스트에는 답하지 않는다', () {
      for (final other in [
        'M-SEARCH * HTTP/1.1',
        'SINGPROMFTER_DISCOVER',
        'SINGPROMFTER_DISCOVER_V2',
        '',
        'hello',
      ]) {
        expect(
          SyncDiscovery.isProbe(utf8.encode(other)),
          isFalse,
          reason: other,
        );
      }
    });

    test('UTF-8이 아닌 쓰레기 패킷에도 죽지 않는다', () {
      expect(SyncDiscovery.isProbe([0xC3, 0x28, 0xFF]), isFalse);
    });
  });

  group('응답', () {
    test('주소와 이름만 담는다 — 페어링 코드는 절대 안 나간다', () {
      final bytes = SyncDiscovery.encodeReply(
        name: 'KUROI-PC',
        apiPort: 8772,
        appVersion: '5.7.0',
      );
      final text = utf8.decode(bytes);
      expect(text, contains('singpromfter'));
      expect(text, contains('KUROI-PC'));
      expect(text.toLowerCase(), isNot(contains('pairing')));
      expect(text.toLowerCase(), isNot(contains('token')));
      expect(text.toLowerCase(), isNot(contains('code')));
    });

    test('폰이 그대로 입력란에 넣을 수 있는 주소로 해석된다', () {
      final bytes = SyncDiscovery.encodeReply(
        name: 'KUROI-PC',
        apiPort: 8772,
        appVersion: '5.7.0',
      );
      final pc = SyncDiscovery.decodeReply(
        bytes,
        InternetAddress('192.168.0.5'),
      );
      expect(pc, isNotNull);
      expect(pc!.address, '192.168.0.5:8772');
      expect(pc.name, 'KUROI-PC');
    });

    test('다른 앱의 응답은 무시한다', () {
      final foreign = utf8.encode(jsonEncode({'app': 'other', 'port': 1}));
      expect(
        SyncDiscovery.decodeReply(foreign, InternetAddress('192.168.0.9')),
        isNull,
      );
      expect(
        SyncDiscovery.decodeReply(
          utf8.encode('not json'),
          InternetAddress('192.168.0.9'),
        ),
        isNull,
      );
    });

    test('이름이 비면 IP를 이름으로 쓴다', () {
      final bytes = SyncDiscovery.encodeReply(
        name: '   ',
        apiPort: 9000,
        appVersion: '5.7.0',
      );
      final pc = SyncDiscovery.decodeReply(
        bytes,
        InternetAddress('10.0.0.7'),
      );
      expect(pc!.name, '10.0.0.7');
      expect(pc.address, '10.0.0.7:9000');
    });

    test('같은 주소는 한 번만 센다 — 브로드캐스트를 세 번 쏘기 때문', () {
      const a = DiscoveredPc(address: '192.168.0.5:8772', name: 'PC');
      const b = DiscoveredPc(address: '192.168.0.5:8772', name: '다른이름');
      expect({a, b}, hasLength(1));
    });
  });
}
