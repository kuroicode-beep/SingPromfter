// file: lib/services/song_compose_client.dart
//
// SVIL 작곡 게이트웨이(127.0.0.1:8774) 클라이언트 — 보컬곡 생성.
// 게이트웨이는 ACE-Step 1.5 터보 엔진(:8001)에 위임하는 잡 기반 서버라
// 제출(job_id) → 상태 폴링(detail·경과) → 완료 시 파일 확보 순서로 쓴다.
// 산출물은 서버가 보존하지만, /output HTTP로 즉시 복사해 자립시킨다.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// 곡 생성 요청 body. (순수 함수 — 테스트 대상)
///
/// 게이트웨이 하드 제한: duration 180~600초. 범위 밖은 잘라 보낸다.
Map<String, dynamic> buildSongBody({
  required String prompt,
  String lyrics = '',
  required int durationSec,
  String vocalType = '',
  String genre = '',
  String chords = '',
  int? bpm,
  int seed = -1,
  String format = 'mp3',
  String lang = 'ko',
}) {
  return {
    'prompt': prompt,
    'lyrics': lyrics,
    'duration': durationSec.clamp(180, 600).toDouble(),
    'genre': genre,
    'vocal': vocalType,
    if (chords.isNotEmpty) 'chords': chords,
    if (bpm != null && bpm > 0) 'bpm': bpm,
    'seed': seed,
    'format': format,
    'lang': lang,
  };
}

class ComposeServerStatus {
  final bool online;

  const ComposeServerStatus({required this.online});

  /// 색이 아니라 글자로 상태를 전달하는 한국어 요약.
  String get label => online ? '작곡 서버: 온라인' : '작곡 서버: 꺼짐';
}

class ComposeEngineStatus {
  final bool alive;

  const ComposeEngineStatus({required this.alive});
}

/// 게이트웨이 잡 상태 스냅샷.
class SongJobStatus {
  final String status; // queued | running | done | error
  final String detail; // 한국어 진행 문구 (VRAM 순번 포함)
  final double elapsedSec;
  final String? resultPath;
  final int? resultSeed;
  final String? error;

  const SongJobStatus({
    required this.status,
    this.detail = '',
    this.elapsedSec = 0,
    this.resultPath,
    this.resultSeed,
    this.error,
  });

  bool get isDone => status == 'done';
  bool get isError => status == 'error';
}

class SongComposeClient {
  static const String baseUrl = 'http://127.0.0.1:8774';

  final http.Client _client;

  SongComposeClient({http.Client? client}) : _client = client ?? http.Client();

  Future<ComposeServerStatus> status() async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/status'))
          .timeout(const Duration(seconds: 3));
      return ComposeServerStatus(online: res.statusCode == 200);
    } catch (_) {
      return const ComposeServerStatus(online: false);
    }
  }

  /// ACE-Step 엔진(:8001) 헬스 — 생성 전 프리플라이트.
  Future<ComposeEngineStatus> engineStatus() async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/api/song/engine'))
          .timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return const ComposeEngineStatus(alive: false);
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      return ComposeEngineStatus(
        alive: decoded is Map<String, dynamic> && decoded['alive'] == true,
      );
    } catch (_) {
      return const ComposeEngineStatus(alive: false);
    }
  }

  /// 잡을 제출하고 job_id를 돌려준다. 실패하면 예외.
  Future<String> submit(Map<String, dynamic> body) async {
    final res = await _client
        .post(
          Uri.parse('$baseUrl/api/song/generate'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode != 200 ||
        decoded is! Map<String, dynamic> ||
        decoded['ok'] != true) {
      final detail = decoded is Map<String, dynamic>
          ? (decoded['detail'] ?? decoded['error'] ?? '')
          : '';
      throw Exception('작곡 잡 제출 실패: $detail');
    }
    final jobId = decoded['job_id'] as String? ?? '';
    if (jobId.isEmpty) throw Exception('작곡 잡 제출 실패: job_id가 없습니다.');
    return jobId;
  }

  /// 잡 상태 1회 조회. 404(서버 재시작으로 잡 소실)는 error로 돌려준다.
  Future<SongJobStatus> pollStatus(String jobId) async {
    final res = await _client
        .get(Uri.parse('$baseUrl/api/song/status/$jobId'))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 404) {
      return const SongJobStatus(
        status: 'error',
        error: '서버가 재시작되어 작업 기록이 사라졌어요. 다시 생성해 주세요.',
      );
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      return const SongJobStatus(status: 'error', error: '상태 응답을 해석할 수 없습니다.');
    }
    final result = decoded['result'];
    return SongJobStatus(
      status: decoded['status'] as String? ?? 'error',
      detail: decoded['detail'] as String? ?? '',
      elapsedSec: (decoded['elapsed_sec'] as num?)?.toDouble() ?? 0,
      resultPath: result is Map ? result['path'] as String? : null,
      resultSeed: result is Map ? (result['seed'] as num?)?.toInt() : null,
      error: decoded['error'] as String?,
    );
  }

  /// 완료된 곡을 /output HTTP로 내려받아 로컬에 저장한다.
  Future<void> downloadOutput(String remotePath, String localPath) async {
    final uri = Uri.parse(
      '$baseUrl/output',
    ).replace(queryParameters: {'path': remotePath});
    final res = await _client.get(uri).timeout(const Duration(minutes: 3));
    if (res.statusCode != 200) {
      throw Exception('생성된 곡 파일을 받아오지 못했습니다 (HTTP ${res.statusCode}).');
    }
    await File(localPath).writeAsBytes(res.bodyBytes);
  }

  void close() => _client.close();
}
