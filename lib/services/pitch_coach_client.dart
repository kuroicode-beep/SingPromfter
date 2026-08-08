// file: lib/services/pitch_coach_client.dart
//
// 로컬 음정 코치 서버(SVIL Pitch Coach, 127.0.0.1:8773)와의 연결 —
// 녹음(보컬)을 원곡 보컬 스템과 비교해 음표 단위 음정(센트)·박자(ms)
// 편차를 받고, PSOLA 보정본을 받아 온다.
//
// f0 추출은 서버의 torchcrepe(신경망 피치 트래커, GPU)가 맡는다.
// package:http Client DI — 테스트에서 가짜 클라이언트 주입.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// 음표 하나의 채점 결과.
class PitchNote {
  final int startMs;
  final int endMs;

  /// 기준 음(전조 반영). 표시용.
  final double refMidi;

  /// 음정 편차(센트). 양수 = 높게 불렀다. 안 불렀으면 null.
  final double? centsOff;

  /// 박자 편차(ms). 양수 = 늦게 들어갔다. 못 찾으면 null.
  final int? timingOffMs;

  /// 이 음표를 불렀는지(유성 프레임이 충분한지).
  final bool sung;

  const PitchNote({
    required this.startMs,
    required this.endMs,
    required this.refMidi,
    this.centsOff,
    this.timingOffMs,
    this.sung = true,
  });

  factory PitchNote.fromJson(Map<String, dynamic> json) => PitchNote(
    startMs: (json['start_ms'] as num?)?.toInt() ?? 0,
    endMs: (json['end_ms'] as num?)?.toInt() ?? 0,
    refMidi: (json['ref_midi'] as num?)?.toDouble() ?? 0,
    centsOff: (json['cents_off'] as num?)?.toDouble(),
    timingOffMs: (json['timing_off_ms'] as num?)?.toInt(),
    sung: json['sung'] as bool? ?? true,
  );

  /// 문제로 표시할 문턱 — 35센트(반의 반음의 2/3)·150ms.
  /// 그 아래는 사람 귀에 "틀렸다"기보다 "개성"이다.
  bool get hasPitchProblem => sung && centsOff != null && centsOff!.abs() >= 35;
  bool get hasTimingProblem =>
      timingOffMs != null && timingOffMs!.abs() >= 150;
  bool get hasProblem => hasPitchProblem || hasTimingProblem || !sung;

  /// "01:23" 위치 표기.
  String get positionLabel {
    final total = startMs ~/ 1000;
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// 사람 말로 된 진단. (순수 — 테스트 대상)
  String describe() {
    if (!sung) return '안 부름(또는 너무 작음)';
    final parts = <String>[];
    final cents = centsOff;
    if (cents != null && cents.abs() >= 35) {
      final direction = cents > 0 ? '높게' : '낮게';
      final amount = cents.abs() >= 75 ? '반음쯤' : '살짝';
      parts.add('음정 $amount $direction (${cents.round()}센트)');
    }
    final timing = timingOffMs;
    if (timing != null && timing.abs() >= 150) {
      final direction = timing > 0 ? '늦게' : '빠르게';
      parts.add('박자 ${(timing.abs() / 1000).toStringAsFixed(1)}초 $direction');
    }
    if (parts.isEmpty) return '좋음';
    return parts.join(' · ');
  }
}

class PitchSummary {
  /// 0~100. 부른 음표가 없으면 null.
  final double? pitchScore;
  final double? timingScore;
  final int sungNotes;
  final int totalNotes;
  final int medianTimingMs;

  const PitchSummary({
    this.pitchScore,
    this.timingScore,
    this.sungNotes = 0,
    this.totalNotes = 0,
    this.medianTimingMs = 0,
  });

  factory PitchSummary.fromJson(Map<String, dynamic> json) => PitchSummary(
    pitchScore: (json['pitch_score'] as num?)?.toDouble(),
    timingScore: (json['timing_score'] as num?)?.toDouble(),
    sungNotes: (json['sung_notes'] as num?)?.toInt() ?? 0,
    totalNotes: (json['total_notes'] as num?)?.toInt() ?? 0,
    medianTimingMs: (json['median_timing_ms'] as num?)?.toInt() ?? 0,
  );
}

class PitchAnalysis {
  final PitchSummary summary;
  final List<PitchNote> notes;

  const PitchAnalysis({required this.summary, required this.notes});

  List<PitchNote> get problems =>
      notes.where((n) => n.hasProblem).toList(growable: false);
}

class PitchAnalyzeResult {
  final PitchAnalysis? analysis;
  final String? message;

  const PitchAnalyzeResult.ok(PitchAnalysis this.analysis) : message = null;
  const PitchAnalyzeResult.failed(this.message) : analysis = null;

  bool get success => analysis != null;
}

class PitchCorrectResult {
  final bool success;

  /// 박자 전체 보정으로 되돌린 양(ms). 양수였으면 그만큼 당겼다.
  final int timingFixedMs;
  final String? message;

  const PitchCorrectResult.ok(this.timingFixedMs)
    : success = true,
      message = null;

  const PitchCorrectResult.failed(this.message)
    : success = false,
      timingFixedMs = 0;
}

class PitchCoachClient {
  static const String baseUrl = 'http://127.0.0.1:8773';

  /// f0 추출 두 번 + 보정 합성 — 곡 길이에 따라 몇 분까지 간다.
  static const Duration requestTimeout = Duration(minutes: 10);

  final http.Client _client;

  PitchCoachClient({http.Client? client}) : _client = client ?? http.Client();

  Future<bool> isOnline() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/api/pitch/status'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  http.MultipartRequest _request(
    String path, {
    required String recordingPath,
    required String referencePath,
    required int alignMs,
    required int transpose,
  }) {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl$path'),
    );
    request.fields['align_ms'] = '$alignMs';
    request.fields['transpose'] = '$transpose';
    return request;
  }

  /// 녹음을 기준 보컬과 비교 채점한다.
  Future<PitchAnalyzeResult> analyze({
    required String recordingPath,
    required String referencePath,
    int alignMs = 0,
    int transpose = 0,
  }) async {
    try {
      final request = _request(
        '/api/pitch/analyze',
        recordingPath: recordingPath,
        referencePath: referencePath,
        alignMs: alignMs,
        transpose: transpose,
      );
      request.files.add(
        await http.MultipartFile.fromPath('recording', recordingPath),
      );
      request.files.add(
        await http.MultipartFile.fromPath('reference', referencePath),
      );
      final streamed = await _client.send(request).timeout(requestTimeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200) {
        return PitchAnalyzeResult.failed(_detail(response));
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
        return const PitchAnalyzeResult.failed('분석에 실패했습니다.');
      }
      final notes = [
        for (final row in decoded['notes'] as List? ?? const [])
          if (row is Map) PitchNote.fromJson(row.cast<String, dynamic>()),
      ];
      return PitchAnalyzeResult.ok(
        PitchAnalysis(
          summary: PitchSummary.fromJson(
            (decoded['summary'] as Map?)?.cast<String, dynamic>() ?? const {},
          ),
          notes: notes,
        ),
      );
    } catch (_) {
      return const PitchAnalyzeResult.failed(
        '분석 서버와 통신하지 못했습니다. 서버 상태를 확인해 주세요.',
      );
    }
  }

  /// 음정(과 전체 박자)을 보정한 wav를 [outputPath]에 저장한다.
  Future<PitchCorrectResult> correct({
    required String recordingPath,
    required String referencePath,
    required String outputPath,
    int alignMs = 0,
    int transpose = 0,
    double strength = 1.0,
    bool fixTiming = true,
  }) async {
    try {
      final request = _request(
        '/api/pitch/correct',
        recordingPath: recordingPath,
        referencePath: referencePath,
        alignMs: alignMs,
        transpose: transpose,
      );
      request.fields['strength'] = strength.toStringAsFixed(2);
      request.fields['fix_timing'] = fixTiming ? '1' : '0';
      request.files.add(
        await http.MultipartFile.fromPath('recording', recordingPath),
      );
      request.files.add(
        await http.MultipartFile.fromPath('reference', referencePath),
      );
      final streamed = await _client.send(request).timeout(requestTimeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200) {
        return PitchCorrectResult.failed(_detail(response));
      }
      await File(outputPath).writeAsBytes(response.bodyBytes);
      final timing =
          int.tryParse(response.headers['x-timing-fixed-ms'] ?? '') ?? 0;
      return PitchCorrectResult.ok(timing);
    } catch (_) {
      return const PitchCorrectResult.failed(
        '보정 서버와 통신하지 못했습니다. 서버 상태를 확인해 주세요.',
      );
    }
  }

  static String _detail(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map && decoded['detail'] is String) {
        return '서버 오류: ${decoded['detail']}';
      }
    } catch (_) {}
    return '서버 오류(${response.statusCode})';
  }

  void close() => _client.close();
}
