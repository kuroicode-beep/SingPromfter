// file: lib/services/vocal_separation_client.dart
//
// SVIL 보컬 분리 서버(demucs, 127.0.0.1:8771) 클라이언트.
// 서버는 SAW(svil-ai-work)의 separator_system이며, 같은 PC에서 돌므로
// 응답의 로컬 경로를 그대로 읽을 수 있다.
import 'dart:convert';

import 'package:http/http.dart' as http;

class SeparationServerStatus {
  final bool online;
  final bool busy;
  final String? device; // 'cuda' | 'cpu'
  final String? gpuName;

  const SeparationServerStatus({
    required this.online,
    this.busy = false,
    this.device,
    this.gpuName,
  });

  /// 색이 아니라 글자로 상태를 전달하기 위한 한국어 요약.
  String get label {
    if (!online) return '분리 서버: 꺼짐';
    final engine = device == 'cuda' ? 'GPU' : 'CPU';
    return busy ? '분리 서버: 작업 중 ($engine)' : '분리 서버: 온라인 ($engine)';
  }
}

class SeparationResult {
  final bool success;
  final String? instrumentalPath;
  final String? vocalsPath;
  final double? elapsedSec;
  final String? message;

  const SeparationResult._({
    required this.success,
    this.instrumentalPath,
    this.vocalsPath,
    this.elapsedSec,
    this.message,
  });

  const SeparationResult.failure(String message)
    : this._(success: false, message: message);
}

class VocalSeparationClient {
  static const String baseUrl = 'http://127.0.0.1:8771';

  /// 분리는 곡 하나에 수십 초 걸린다. 여유 있게 잡는다.
  static const Duration separateTimeout = Duration(minutes: 15);

  final http.Client _client;

  VocalSeparationClient({http.Client? client})
    : _client = client ?? http.Client();

  Future<SeparationServerStatus> status() async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/api/separator/status'))
          .timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) {
        return const SeparationServerStatus(online: false);
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        return const SeparationServerStatus(online: false);
      }
      final gpu = decoded['gpu'];
      return SeparationServerStatus(
        online: true,
        busy: decoded['busy'] == true,
        device: gpu is Map ? gpu['device'] as String? : null,
        gpuName: gpu is Map ? gpu['name'] as String? : null,
      );
    } catch (_) {
      return const SeparationServerStatus(online: false);
    }
  }

  /// 음원에서 보컬을 분리한다. 완료까지 기다렸다가 로컬 경로를 돌려준다.
  Future<SeparationResult> separate(String audioPath) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/separator/separate'),
      )..files.add(await http.MultipartFile.fromPath('file', audioPath));

      final streamed = await _client.send(request).timeout(separateTimeout);
      final res = await http.Response.fromStream(streamed);
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        return const SeparationResult.failure('분리 서버 응답을 해석할 수 없습니다.');
      }
      if (res.statusCode != 200 || decoded['ok'] != true) {
        return SeparationResult.failure(
          decoded['error'] as String? ?? '보컬 분리에 실패했습니다.',
        );
      }
      return SeparationResult._(
        success: true,
        instrumentalPath: decoded['instrumental_path'] as String?,
        vocalsPath: decoded['vocals_path'] as String?,
        elapsedSec: (decoded['elapsed_sec'] as num?)?.toDouble(),
      );
    } catch (e) {
      return SeparationResult.failure(
        '분리 서버에 연결하지 못했습니다. SAW에서 보컬 분리 서버를 켜 주세요. ($e)',
      );
    }
  }

  void close() => _client.close();
}
