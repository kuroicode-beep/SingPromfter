// file: test/services/stt_lyrics_client_test.dart
//
// STT 클라이언트 — 세그먼트 파싱, 낡은 서버(세그먼트 없음), 서버 오류.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:singpromfter_app/services/stt_lyrics_client.dart';

class _FakeClient extends http.BaseClient {
  final int status;
  final String body;
  final List<http.BaseRequest> requests = [];

  _FakeClient(this.status, this.body);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(Stream.value(utf8.encode(body)), status);
  }
}

void main() {
  late File audio;

  setUp(() async {
    audio = File(
      '${Directory.systemTemp.createTempSync('stt_test').path}/a.mp3',
    );
    await audio.writeAsBytes([1, 2, 3]);
  });

  test('세그먼트를 파싱하고 with_segments·vad 파라미터를 보낸다', () async {
    final fake = _FakeClient(
      200,
      jsonEncode({
        'success': true,
        'segments': [
          {'start': 13.6, 'end': 20.0, 'text': ' 첫 소절 '},
          {'start': 30.0, 'end': 38.0, 'text': '둘째 소절'},
        ],
      }),
    );
    final client = SttLyricsClient(client: fake);

    final result = await client.transcribe(audio.path);

    expect(result.success, isTrue);
    expect(result.segments, hasLength(2));
    expect(result.segments.first.text, '첫 소절');
    expect(result.segments.first.startSeconds, 13.6);

    final request = fake.requests.single as http.MultipartRequest;
    expect(request.fields['with_segments'], '1');
    expect(request.fields['vad'], '0', reason: '노래에서 VAD는 보컬을 잘라낸다');
    expect(request.fields['language'], 'ko');
  });

  test('세그먼트가 없으면(낡은 서버) 재시작 안내로 실패한다', () async {
    final fake = _FakeClient(
      200,
      jsonEncode({'success': true, 'output_text': '가사'}),
    );
    final client = SttLyricsClient(client: fake);
    final result = await client.transcribe(audio.path);
    expect(result.success, isFalse);
    expect(result.message, contains('재시작'));
  });

  test('서버 오류는 상태코드와 함께 실패한다', () async {
    final fake = _FakeClient(500, 'oops');
    final client = SttLyricsClient(client: fake);
    final result = await client.transcribe(audio.path);
    expect(result.success, isFalse);
    expect(result.message, contains('500'));
  });

  test('파일이 없으면 요청하지 않는다', () async {
    final fake = _FakeClient(200, '{}');
    final client = SttLyricsClient(client: fake);
    final result = await client.transcribe('C:/없는/파일.mp3');
    expect(result.success, isFalse);
    expect(fake.requests, isEmpty);
  });
}
