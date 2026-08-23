// file: lib/services/sync_discovery.dart
//
// 같은 와이파이의 PC를 폰이 스스로 찾는다 — IP를 손으로 적지 않게.
//
// mDNS를 쓰지 않는 이유: Dart의 multicast_dns는 조회 전용이라 PC가 자신을
// 알릴 수단이 없다. 알리려면 Windows 지원이 불확실한 별도 패키지가 필요하다.
// UDP 브로드캐스트는 dart:io만으로 양쪽이 다 되고 의존성이 늘지 않는다.
//
// 🔴 응답은 동기화 서버가 켜져 있을 때만 한다. 켜지 않은 PC가 "나 여기 있다"고
// 답하면 안 된다. 응답에는 페어링 코드를 담지 않는다 — 주소와 이름뿐이다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 탐색용 UDP 포트. 제어 API(8772) 바로 옆.
const int kSyncDiscoveryPort = 8773;

/// 폰이 쏘는 인사말. 버전을 붙여 두어 나중에 형식이 바뀌어도 구분된다.
const String kSyncDiscoveryProbe = 'SINGPROMFTER_DISCOVER_V1';

/// 찾아낸 PC 하나.
class DiscoveredPc {
  /// 폰이 그대로 입력란에 넣을 수 있는 형태(예: 192.168.0.5:8772).
  final String address;
  final String name;

  const DiscoveredPc({required this.address, required this.name});

  @override
  String toString() => '$name ($address)';

  @override
  bool operator ==(Object other) =>
      other is DiscoveredPc && other.address == address;

  @override
  int get hashCode => address.hashCode;
}

class SyncDiscovery {
  SyncDiscovery._();

  /// 받은 패킷이 우리 인사말인가. 다른 앱의 브로드캐스트에 답하지 않는다.
  static bool isProbe(List<int> data) {
    try {
      return utf8.decode(data).trim() == kSyncDiscoveryProbe;
    } catch (_) {
      return false;
    }
  }

  /// PC가 돌려줄 응답. 페어링 코드는 절대 담지 않는다.
  static List<int> encodeReply({
    required String name,
    required int apiPort,
    required String appVersion,
  }) => utf8.encode(
    jsonEncode({
      'app': 'singpromfter',
      'name': name,
      'port': apiPort,
      'appVersion': appVersion,
    }),
  );

  /// 폰이 응답을 해석한다. 우리 앱이 아니면 null.
  static DiscoveredPc? decodeReply(List<int> data, InternetAddress from) {
    try {
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['app'] != 'singpromfter') return null;
      final port = (decoded['port'] as num?)?.toInt() ?? 8772;
      final name = (decoded['name'] as String?)?.trim();
      return DiscoveredPc(
        address: '${from.address}:$port',
        name: name == null || name.isEmpty ? from.address : name,
      );
    } catch (_) {
      return null;
    }
  }
}

/// PC 쪽 — 폰의 인사말에 답한다.
class SyncDiscoveryResponder {
  final int port;
  final int apiPort;

  /// 지금 응답해도 되는지(동기화 서버가 켜져 있는지). 매 패킷마다 확인한다 —
  /// 설정을 끄자마자 조용해져야 한다.
  final bool Function() enabled;

  final String Function() appVersion;

  RawDatagramSocket? _socket;

  SyncDiscoveryResponder({
    required this.enabled,
    required this.appVersion,
    this.port = kSyncDiscoveryPort,
    this.apiPort = 8772,
  });

  bool get running => _socket != null;

  Future<void> start() async {
    if (_socket != null) return;
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
      );
      _socket = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final packet = socket.receive();
        if (packet == null) return;
        if (!enabled()) return;
        if (!SyncDiscovery.isProbe(packet.data)) return;
        socket.send(
          SyncDiscovery.encodeReply(
            name: Platform.localHostname,
            apiPort: apiPort,
            appVersion: appVersion(),
          ),
          packet.address,
          packet.port,
        );
      });
      debugPrint('동기화 탐색 응답 시작(UDP $port)');
    } catch (e) {
      // 포트 충돌 등 — 탐색만 안 되고 수동 입력은 그대로 된다.
      debugPrint('동기화 탐색 응답을 열지 못했습니다(UDP $port): $e');
    }
  }

  void stop() {
    _socket?.close();
    _socket = null;
  }
}

/// 폰 쪽 — 브로드캐스트를 쏘고 잠깐 기다린다.
class SyncDiscoveryScanner {
  final int port;

  const SyncDiscoveryScanner({this.port = kSyncDiscoveryPort});

  /// [timeout] 동안 응답을 모아 돌려준다. 같은 주소는 한 번만.
  Future<List<DiscoveredPc>> scan({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    RawDatagramSocket? socket;
    final found = <DiscoveredPc>{};
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final probe = utf8.encode(kSyncDiscoveryProbe);

      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final packet = socket?.receive();
        if (packet == null) return;
        final pc = SyncDiscovery.decodeReply(packet.data, packet.address);
        if (pc != null) found.add(pc);
      });

      // 브로드캐스트는 한 번이면 유실될 수 있어 짧게 세 번 쏜다.
      for (var i = 0; i < 3; i++) {
        socket.send(probe, InternetAddress('255.255.255.255'), port);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      await Future<void>.delayed(timeout);
    } catch (e) {
      debugPrint('동기화 탐색 실패: $e');
    } finally {
      socket?.close();
    }
    return found.toList(growable: false);
  }
}
