// file: test/services/deepseek_lyrics_client_test.dart
//
// DeepSeek 가사 검증 클라이언트 — 파싱·키 부재 동작.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:singpromfter_app/services/deepseek_lyrics_client.dart';

http.Response _chatResponse(Map<String, dynamic> content) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': jsonEncode(content)},
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  test('키가 없으면 네트워크 없이 null', () async {
    final client = DeepSeekLyricsClient(
      apiKey: '',
      client: MockClient((_) async => throw StateError('호출되면 안 됨')),
    );
    expect(client.available, isFalse);
    expect(await client.flagSuspiciousLines(['가사']), isNull);
  });

  test('의심 줄 지목 응답을 index→사유로 파싱한다', () async {
    final client = DeepSeekLyricsClient(
      apiKey: 'k',
      client: MockClient((req) async {
        expect(req.url.path, '/chat/completions');
        return _chatResponse({
          'suspicious': [
            {'index': 1, 'reason': '비문'},
            {'index': 99, 'reason': '범위 밖 — 무시'},
          ],
        });
      }),
    );
    final flags = await client.flagSuspiciousLines(['정상', 'march이 옆에도']);
    expect(flags, {1: '비문'});
  });

  test('정답 가사 정렬 응답을 stt index→정답 텍스트로 파싱한다', () async {
    final client = DeepSeekLyricsClient(
      apiKey: 'k',
      client: MockClient(
        (_) async => _chatResponse({
          'matches': [
            {'stt': 0, 'ref_text': '못 한 몫 되어'},
            {'stt': 2, 'ref_text': ''},
          ],
        }),
      ),
    );
    final matches = await client.alignWithReference(
      ['몸 한 몸 들어', '환청', '빈 매칭'],
      '못 한 몫 되어\n...',
    );
    expect(matches, {0: '못 한 몫 되어'});
  });

  test('HTTP 오류는 null — 호출측이 LLM 근거 없이 진행한다', () async {
    final client = DeepSeekLyricsClient(
      apiKey: 'k',
      client: MockClient((_) async => http.Response('overloaded', 503)),
    );
    expect(await client.flagSuspiciousLines(['가사']), isNull);
  });
}
