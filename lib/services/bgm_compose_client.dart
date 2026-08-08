// file: lib/services/bgm_compose_client.dart
//
// SVIL BGM 서버(127.0.0.1:8766, MusicGen) 클라이언트 — 짧은 반주 BGM 생성.
// /generate는 블로킹(수 분)이고, 서버가 생성 직후 이전 산출물을 전부
// 지우므로 응답을 받으면 **즉시** /output으로 파일을 확보해야 한다.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// BGM 생성 요청 body. (순수 함수 — 테스트 대상)
///
/// 서버 제한: duration ≤ 300초. mp3 변환을 켜 파일 크기·호환을 챙긴다.
Map<String, dynamic> buildGenerateBody({
  required String prompt,
  String preset = '',
  required int durationSec,
  String modelSize = 'medium',
  int seed = -1,
  bool convertMp3 = true,
}) {
  return {
    'prompt': prompt,
    'preset': preset,
    'duration': durationSec.clamp(10, 300).toDouble(),
    'model_size': modelSize,
    'seed': seed,
    'convert_mp3': convertMp3,
    'backend': 'musicgen',
  };
}

class BgmServerStatus {
  final bool online;

  const BgmServerStatus({required this.online});

  String get label => online ? 'BGM 서버: 온라인' : 'BGM 서버: 꺼짐';
}

class BgmPreset {
  final String name;
  final String description;
  final double? recommendedDuration;

  const BgmPreset({
    required this.name,
    this.description = '',
    this.recommendedDuration,
  });
}

class BgmGenerateResult {
  final bool ok;
  final String? remotePath; // mp3_path 우선, 없으면 wav_path
  final String? fileName;
  final int? seed;
  final double genTimeSec;
  final String? message;

  const BgmGenerateResult({
    required this.ok,
    this.remotePath,
    this.fileName,
    this.seed,
    this.genTimeSec = 0,
    this.message,
  });
}

class BgmComposeClient {
  static const String baseUrl = 'http://127.0.0.1:8766';

  /// MusicGen medium이 5분짜리에 수 분 걸릴 수 있어 넉넉히 잡는다.
  static const Duration generateTimeout = Duration(minutes: 20);

  final http.Client _client;

  BgmComposeClient({http.Client? client}) : _client = client ?? http.Client();

  Future<BgmServerStatus> status() async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/status'))
          .timeout(const Duration(seconds: 3));
      return BgmServerStatus(online: res.statusCode == 200);
    } catch (_) {
      return const BgmServerStatus(online: false);
    }
  }

  Future<List<BgmPreset>> presets() async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/presets'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return const [];
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (e) => BgmPreset(
              name: e['name'] as String? ?? '',
              description: e['description'] as String? ?? '',
              recommendedDuration:
                  (e['recommended_duration'] as num?)?.toDouble(),
            ),
          )
          .where((p) => p.name.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// BGM을 생성한다 — 완료까지 블로킹. 취소 개념이 없으므로
  /// 호출 측이 응답을 무시하는 방식으로 취소를 처리한다.
  Future<BgmGenerateResult> generate(Map<String, dynamic> body) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$baseUrl/generate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(generateTimeout);
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        return const BgmGenerateResult(ok: false, message: '응답을 해석할 수 없습니다.');
      }
      if (res.statusCode != 200 || decoded['ok'] != true) {
        return BgmGenerateResult(
          ok: false,
          message: decoded['detail'] as String? ?? 'BGM 생성에 실패했습니다.',
        );
      }
      return BgmGenerateResult(
        ok: true,
        remotePath: (decoded['mp3_path'] ?? decoded['wav_path']) as String?,
        fileName: decoded['filename'] as String?,
        seed: (decoded['seed'] as num?)?.toInt(),
        genTimeSec: (decoded['gen_time'] as num?)?.toDouble() ?? 0,
      );
    } catch (e) {
      return BgmGenerateResult(
        ok: false,
        message: 'BGM 서버에 연결하지 못했습니다. SAW에서 bgm_system을 켜 주세요. ($e)',
      );
    }
  }

  /// 생성 직후 서버가 지우기 전에 /output HTTP로 파일을 확보한다.
  Future<void> downloadOutput(String remotePath, String localPath) async {
    final uri = Uri.parse(
      '$baseUrl/output',
    ).replace(queryParameters: {'path': remotePath});
    final res = await _client.get(uri).timeout(const Duration(minutes: 3));
    if (res.statusCode != 200) {
      throw Exception('생성된 BGM 파일을 받아오지 못했습니다 (HTTP ${res.statusCode}).');
    }
    await File(localPath).writeAsBytes(res.bodyBytes);
  }

  void close() => _client.close();
}
