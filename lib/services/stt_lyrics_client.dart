// file: lib/services/stt_lyrics_client.dart
//
// 로컬 STT 서버(SVIL faster-whisper, 127.0.0.1:8769)로 노래를 받아써
// 타임스탬프 세그먼트를 얻는다 — LRCLIB에 없는 곡의 싱크 가사를 만드는 입구.
//
// 서버는 with_segments=1일 때만 타임스탬프를 담아 준다(2026-07-30 확장).
// 노래에서는 VAD가 보컬을 통째로 잘라내므로 vad=0으로 끈다.
//
// package:http의 Client 인터페이스 DI — 테스트에서 가짜 클라이언트 주입
// (이 프로젝트는 모킹 패키지를 쓰지 않는다).
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../utils/lrc_edit.dart';

class SttTranscribeResult {
  final bool success;
  final List<SttSegment> segments;

  /// 실패 시 사용자에게 보여 줄 사유.
  final String? message;

  const SttTranscribeResult.ok(this.segments)
    : success = true,
      message = null;

  const SttTranscribeResult.failed(this.message)
    : success = false,
      segments = const [];
}

class SttLyricsClient {
  static const String baseUrl = 'http://127.0.0.1:8769';

  /// 곡 하나에 수십 초 걸린다(모델 로드가 겹치면 더).
  static const Duration transcribeTimeout = Duration(minutes: 5);

  final http.Client _client;

  SttLyricsClient({http.Client? client}) : _client = client ?? http.Client();

  /// 서버가 떠 있는지. 받아쓰기 전에 확인해 명확한 안내를 준다.
  Future<bool> isOnline() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/api/stt/status'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// [audioPath]를 받아써 타임스탬프 세그먼트를 돌려준다.
  Future<SttTranscribeResult> transcribe(String audioPath) async {
    final file = File(audioPath);
    if (!await file.exists()) {
      return const SttTranscribeResult.failed('음원 파일을 찾을 수 없습니다.');
    }
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/stt/transcribe'),
      );
      request.fields['model'] = 'large-v3-turbo';
      request.fields['language'] = 'ko';
      request.fields['with_segments'] = '1';
      request.fields['vad'] = '0';
      // 단어 타임스탬프 + 신뢰도(no_speech_prob 등) — 정밀 보정의 근거.
      // 옛 서버는 이 필드를 몰라도 무시하므로 하위 호환이다.
      request.fields['word_timestamps'] = '1';
      request.files.add(
        await http.MultipartFile.fromPath('file', audioPath),
      );

      final streamed = await _client.send(request).timeout(transcribeTimeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200) {
        return SttTranscribeResult.failed('STT 서버 오류(${response.statusCode})');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
        return const SttTranscribeResult.failed('받아쓰기에 실패했습니다.');
      }
      final rows = decoded['segments'];
      if (rows is! List) {
        return const SttTranscribeResult.failed(
          'STT 서버가 타임스탬프를 주지 않습니다. 서버를 최신으로 재시작해 주세요.',
        );
      }
      final segments = <SttSegment>[
        for (final row in rows)
          if (row is Map)
            SttSegment(
              startSeconds: (row['start'] as num?)?.toDouble() ?? 0,
              endSeconds: (row['end'] as num?)?.toDouble() ?? 0,
              text: (row['text'] as String? ?? '').trim(),
              noSpeechProb: (row['no_speech_prob'] as num?)?.toDouble(),
              avgLogprob: (row['avg_logprob'] as num?)?.toDouble(),
              firstWordStartSeconds: _firstWordStart(row['words']),
            ),
      ];
      return SttTranscribeResult.ok(segments);
    } catch (_) {
      return const SttTranscribeResult.failed(
        '받아쓰기 중 통신이 끊겼습니다. STT 서버 상태를 확인해 주세요.',
      );
    }
  }

  void close() => _client.close();

  static double? _firstWordStart(dynamic words) {
    if (words is! List || words.isEmpty) return null;
    final first = words.first;
    if (first is! Map) return null;
    return (first['start'] as num?)?.toDouble();
  }
}
