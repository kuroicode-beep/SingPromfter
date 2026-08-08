// file: lib/services/deepseek_lyrics_client.dart
//
// DeepSeek로 가사 텍스트를 검증한다 — 받아쓰기 정밀 보정의 LLM 근거.
// ① 환청 의심 줄 지목(음향 필터와 교차 판정용)
// ② STT 줄 ↔ 사용자가 붙여넣은 정답 가사 정렬(타이밍은 STT, 텍스트는 정답)
//
// 키는 환경변수 DEEPSEEK_API_KEY. 없으면 available=false — 호출측은
// LLM 단계를 조용히 건너뛴다(필수 아님, 보조 근거).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class DeepSeekLyricsClient {
  static const String baseUrl = 'https://api.deepseek.com';

  /// 곡당 1콜이라 비용은 무시 가능한 수준 — 모델은 환경변수로 바꿀 수 있다.
  static final String model =
      Platform.environment['DEEPSEEK_MODEL'] ?? 'deepseek-v4-flash';

  final http.Client _client;
  final String? _apiKey;

  DeepSeekLyricsClient({http.Client? client, String? apiKey})
    : _client = client ?? http.Client(),
      _apiKey = apiKey ?? Platform.environment['DEEPSEEK_API_KEY'];

  bool get available => (_apiKey ?? '').trim().isNotEmpty;

  void close() => _client.close();

  /// 노래 가사로 성립하지 않는 줄을 지목한다. index → 사유.
  /// 실패(네트워크·파싱)는 null — 호출측이 이 근거 없이 진행한다.
  Future<Map<int, String>?> flagSuspiciousLines(List<String> lines) async {
    final numbered = [
      for (var i = 0; i < lines.length; i++) '$i: ${lines[i]}',
    ].join('\n');
    final result = await _chatJson(
      system: '너는 한국 노래 가사 검수자다. 음성 인식(STT)으로 받아쓴 가사에서 '
          '환청으로 의심되는 줄만 골라낸다. 판단 근거: 문장이 성립하지 않는 비문, '
          '맥락 없이 섞인 외국어·로마자, 무의미한 음절 나열, 직전 줄의 어색한 '
          '부분 반복. 실제 가사일 수 있는 줄은 절대 지목하지 않는다(보수적으로). '
          '반드시 JSON으로만 답한다: {"suspicious":[{"index":숫자,"reason":"짧은 사유"}]}',
      user: '번호가 붙은 가사 줄이다. 환청 의심 줄을 지목해라.\n\n$numbered',
    );
    final rows = result?['suspicious'];
    if (rows is! List) return result == null ? null : {};
    final out = <int, String>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final idx = (row['index'] as num?)?.toInt();
      if (idx == null || idx < 0 || idx >= lines.length) continue;
      out[idx] = (row['reason'] as String? ?? '').trim();
    }
    return out;
  }

  /// STT 줄들을 정답 가사에 정렬한다. STT index → 정답 줄 텍스트.
  /// 정답에 대응이 없는 STT 줄은 결과에서 빠진다(환청·중복으로 처리).
  Future<Map<int, String>?> alignWithReference(
    List<String> sttLines,
    String referenceText,
  ) async {
    final numbered = [
      for (var i = 0; i < sttLines.length; i++) '$i: ${sttLines[i]}',
    ].join('\n');
    final result = await _chatJson(
      system: '너는 노래 가사 정렬 도우미다. STT로 받아쓴 줄들을 공식 가사의 '
          '줄에 대응시킨다. 발음이 비슷하면 같은 줄이다(STT 오탈자 감안). '
          '규칙: ① 각 STT 줄에 가장 알맞은 공식 가사 줄 텍스트를 준다 '
          '② 공식 가사에 대응이 없는 STT 줄은 결과에서 뺀다 ③ 순서는 대체로 '
          '유지되지만 후렴 반복은 같은 가사 줄이 여러 STT 줄에 대응될 수 있다 '
          '④ ref_text는 공식 가사의 줄을 그대로(수정 없이) 쓴다. '
          '반드시 JSON으로만 답한다: {"matches":[{"stt":숫자,"ref_text":"공식 가사 줄"}]}',
      user: '## STT 받아쓰기 줄\n$numbered\n\n## 공식 가사\n$referenceText',
    );
    final rows = result?['matches'];
    if (rows is! List) return result == null ? null : {};
    final out = <int, String>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final idx = (row['stt'] as num?)?.toInt();
      final text = (row['ref_text'] as String? ?? '').trim();
      if (idx == null || idx < 0 || idx >= sttLines.length || text.isEmpty) {
        continue;
      }
      out[idx] = text;
    }
    return out;
  }

  Future<Map<String, dynamic>?> _chatJson({
    required String system,
    required String user,
  }) async {
    if (!available) return null;
    try {
      final res = await _client
          .post(
            Uri.parse('$baseUrl/chat/completions'),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'temperature': 0,
              'response_format': {'type': 'json_object'},
              'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': user},
              ],
            }),
          )
          .timeout(const Duration(seconds: 90));
      if (res.statusCode != 200) {
        debugPrint('DeepSeek HTTP ${res.statusCode}: '
            '${utf8.decode(res.bodyBytes, allowMalformed: true)}');
        return null;
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) return null;
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final first = choices.first;
      final message = first is Map ? first['message'] : null;
      final content = message is Map ? message['content'] : null;
      if (content is! String) return null;
      final parsed = jsonDecode(content);
      return parsed is Map<String, dynamic> ? parsed : null;
    } catch (e) {
      debugPrint('DeepSeek 호출 실패: $e');
      return null;
    }
  }
}
