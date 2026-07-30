// file: test/services/pitch_coach_client_test.dart
//
// 음정 코치 클라이언트 — 응답 파싱, 진단 문구, 보정 파일 저장.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:singpromfter_app/services/pitch_coach_client.dart';

class _FakeClient extends http.BaseClient {
  final int status;
  final List<int> body;
  final Map<String, String> headers;
  final List<http.BaseRequest> requests = [];

  _FakeClient(this.status, this.body, {this.headers = const {}});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(
      Stream.value(body),
      status,
      headers: headers,
    );
  }
}

void main() {
  late File audio;

  setUp(() async {
    audio = File(
      '${Directory.systemTemp.createTempSync('pitch_test').path}/a.wav',
    );
    await audio.writeAsBytes([1, 2, 3]);
  });

  test('분석 응답을 파싱하고 align·transpose를 보낸다', () async {
    final fake = _FakeClient(
      200,
      utf8.encode(jsonEncode({
        'success': true,
        'summary': {
          'pitch_score': 72.5,
          'timing_score': 90.0,
          'sung_notes': 10,
          'total_notes': 12,
          'median_timing_ms': 120,
        },
        'notes': [
          {
            'start_ms': 83000,
            'end_ms': 83500,
            'ref_midi': 62.0,
            'cents_off': -78.0,
            'timing_off_ms': 200,
            'sung': true,
          },
          {
            'start_ms': 90000,
            'end_ms': 90400,
            'ref_midi': 64.0,
            'cents_off': 5.0,
            'timing_off_ms': 20,
            'sung': true,
          },
        ],
      })),
    );
    final client = PitchCoachClient(client: fake);

    final result = await client.analyze(
      recordingPath: audio.path,
      referencePath: audio.path,
      alignMs: 350,
      transpose: -5,
    );

    expect(result.success, isTrue);
    final analysis = result.analysis!;
    expect(analysis.summary.pitchScore, 72.5);
    expect(analysis.notes, hasLength(2));
    // 문제로 표시되는 건 첫 음표뿐(−78센트·+200ms).
    expect(analysis.problems, hasLength(1));
    expect(analysis.problems.single.positionLabel, '01:23');

    final request = fake.requests.single as http.MultipartRequest;
    expect(request.fields['align_ms'], '350');
    expect(request.fields['transpose'], '-5');
  });

  test('진단 문구 — 사람 말로', () {
    const flat = PitchNote(
      startMs: 0,
      endMs: 500,
      refMidi: 60,
      centsOff: -78,
      timingOffMs: 300,
    );
    expect(flat.describe(), '음정 반음쯤 낮게 (-78센트) · 박자 0.3초 늦게');

    const slightlySharp = PitchNote(
      startMs: 0,
      endMs: 500,
      refMidi: 60,
      centsOff: 40,
      timingOffMs: -200,
    );
    expect(slightlySharp.describe(), '음정 살짝 높게 (40센트) · 박자 0.2초 빠르게');

    const good = PitchNote(
      startMs: 0,
      endMs: 500,
      refMidi: 60,
      centsOff: 10,
      timingOffMs: 50,
    );
    expect(good.describe(), '좋음');
    expect(good.hasProblem, isFalse);

    const missed = PitchNote(startMs: 0, endMs: 500, refMidi: 60, sung: false);
    expect(missed.describe(), '안 부름(또는 너무 작음)');
    expect(missed.hasProblem, isTrue);
  });

  test('보정은 wav를 저장하고 박자 보정량을 알려 준다', () async {
    final fake = _FakeClient(
      200,
      [82, 73, 70, 70], // 'RIFF'
      headers: {'x-timing-fixed-ms': '150'},
    );
    final client = PitchCoachClient(client: fake);
    final out =
        '${Directory.systemTemp.createTempSync('pitch_out').path}/c.wav';

    final result = await client.correct(
      recordingPath: audio.path,
      referencePath: audio.path,
      outputPath: out,
    );

    expect(result.success, isTrue);
    expect(result.timingFixedMs, 150);
    expect(await File(out).readAsBytes(), [82, 73, 70, 70]);
  });

  test('서버 오류는 detail을 사용자 문구로', () async {
    final fake = _FakeClient(
      500,
      utf8.encode(jsonEncode({'detail': 'ffmpeg not found'})),
    );
    final client = PitchCoachClient(client: fake);
    final result = await client.analyze(
      recordingPath: audio.path,
      referencePath: audio.path,
    );
    expect(result.success, isFalse);
    expect(result.message, contains('ffmpeg'));
  });
}
