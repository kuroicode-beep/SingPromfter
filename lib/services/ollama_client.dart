// file: lib/services/ollama_client.dart
//
// 로컬 Ollama(127.0.0.1:11434) 클라이언트 — 한국어 곡 설명을 음악 생성
// 모델용 영어 스타일 태그로 다듬고, 가사에 [verse]/[chorus] 구조 태그를
// 붙인다. 다듬기는 편의 기능이지 게이트가 아니다 — 실패해도 원문으로
// 생성을 계속할 수 있어야 한다.
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 다듬기 실패 분류 — 안내 문구를 상황에 맞게 내보내기 위해 나눈다.
enum OllamaFailure { none, offline, modelMissing, error }

class OllamaPolishResult {
  final bool ok;
  final String text;
  final OllamaFailure failure;
  final String? message;

  const OllamaPolishResult.success(this.text)
    : ok = true,
      failure = OllamaFailure.none,
      message = null;

  const OllamaPolishResult.failure(this.failure, this.message)
    : ok = false,
      text = '';
}

/// 스타일 다듬기 채팅 요청 body. (순수 함수 — 테스트 대상)
Map<String, dynamic> buildPolishBody({
  required String model,
  required String koreanPrompt,
}) {
  return {
    'model': model,
    'stream': false,
    'messages': [
      {
        'role': 'system',
        'content':
            '너는 음악 생성 모델용 프롬프트 변환기다. 사용자가 준 한국어 곡 설명을 '
            '영어 스타일 태그로 변환한다. 장르, 분위기, 악기, 템포, 보컬 타입을 '
            '쉼표로 나열한다. 설명이나 인사 없이 변환된 프롬프트 한 줄만 출력한다.',
      },
      {'role': 'user', 'content': koreanPrompt},
    ],
  };
}

/// 가사 구조 태그 요청 body. 가사 내용은 한국어 그대로 두고
/// [verse]/[chorus]/[bridge] 태그만 삽입하게 한다. (순수 함수)
Map<String, dynamic> buildLyricsTagBody({
  required String model,
  required String lyrics,
}) {
  return {
    'model': model,
    'stream': false,
    'messages': [
      {
        'role': 'system',
        'content':
            '너는 노래 가사 구조 태거다. 사용자가 준 가사의 내용과 언어를 절대 '
            '바꾸지 말고, 구조에 맞게 [verse], [chorus], [bridge] 태그 줄만 '
            '삽입해서 그대로 출력한다. 다른 설명은 붙이지 않는다.',
      },
      {'role': 'user', 'content': lyrics},
    ],
  };
}

/// /api/chat 응답에서 본문을 뽑는다. (순수 함수)
String? parseChatContent(Object? decoded) {
  if (decoded is! Map<String, dynamic>) return null;
  final message = decoded['message'];
  if (message is! Map) return null;
  final content = message['content'];
  if (content is! String) return null;
  final trimmed = content.trim();
  return trimmed.isEmpty ? null : trimmed;
}

class OllamaClient {
  static const String baseUrl = 'http://127.0.0.1:11434';

  /// 12B 모델의 첫 로드가 느릴 수 있어 넉넉히 잡는다.
  static const Duration chatTimeout = Duration(seconds: 120);

  final http.Client _client;

  OllamaClient({http.Client? client}) : _client = client ?? http.Client();

  /// 설치된 모델 이름 목록. 서버가 꺼져 있으면 null.
  Future<List<String>?> listModels() async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/api/tags'))
          .timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      final models = decoded['models'];
      if (models is! List) return const [];
      return models
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => e['name'] as String? ?? '')
          .where((name) => name.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  /// 모델 존재 확인 — `gemma4:12b`와 `gemma4:12b-instruct-...`처럼
  /// 접두 일치도 허용한다(오타가 아니라 태그 생략인 경우가 많다).
  static bool hasModel(List<String> models, String wanted) {
    final w = wanted.trim();
    if (w.isEmpty) return false;
    return models.any((m) => m == w || m.startsWith('$w-') || m.split(':').first == w);
  }

  /// 한국어 스타일 설명 → 영어 태그 다듬기.
  Future<OllamaPolishResult> polishStylePrompt(
    String koreanPrompt, {
    required String model,
  }) {
    return _chat(buildPolishBody(model: model, koreanPrompt: koreanPrompt));
  }

  /// 가사에 [verse]/[chorus] 구조 태그 삽입 (내용·언어 유지).
  Future<OllamaPolishResult> tagLyrics(
    String lyrics, {
    required String model,
  }) {
    return _chat(buildLyricsTagBody(model: model, lyrics: lyrics));
  }

  Future<OllamaPolishResult> _chat(Map<String, dynamic> body) async {
    final model = body['model'] as String? ?? '';
    // 먼저 모델 존재를 확인해 404를 기다리지 않고 안내한다.
    final models = await listModels();
    if (models == null) {
      return const OllamaPolishResult.failure(
        OllamaFailure.offline,
        'Ollama(11434)에 연결할 수 없습니다. Ollama가 실행 중인지 확인해 주세요.',
      );
    }
    if (!hasModel(models, model)) {
      return OllamaPolishResult.failure(
        OllamaFailure.modelMissing,
        "Ollama에 '$model' 모델이 없습니다. 터미널에서 'ollama pull $model'을 "
        '실행하거나, 설정에서 모델명을 바꿔 주세요.',
      );
    }

    try {
      final res = await _client
          .post(
            Uri.parse('$baseUrl/api/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(chatTimeout);
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode != 200) {
        final err = decoded is Map<String, dynamic>
            ? decoded['error'] as String? ?? ''
            : '';
        return OllamaPolishResult.failure(
          OllamaFailure.error,
          '다듬기에 실패했습니다: $err',
        );
      }
      final content = parseChatContent(decoded);
      if (content == null) {
        return const OllamaPolishResult.failure(
          OllamaFailure.error,
          '모델이 빈 응답을 돌려줬습니다.',
        );
      }
      return OllamaPolishResult.success(content);
    } catch (e) {
      return OllamaPolishResult.failure(
        OllamaFailure.error,
        '다듬기 중 오류가 났습니다: $e',
      );
    }
  }

  void close() => _client.close();
}
