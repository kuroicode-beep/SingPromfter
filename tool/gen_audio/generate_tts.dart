// file: tool/gen_audio/generate_tts.dart
//
// 개발용 TTS 클립 생성기 — lib/constants/voice_clips.dart 의 전 클립을
// SVIL 로컬 TTS(8765, female_calm)로 구워 assets/audio/tts/<id>.wav 로 저장한다.
// 앱과 같은 정본(VoiceClips)을 import 하므로 문구·파일이 어긋날 수 없다.
//
// 실행: dart run tool/gen_audio/generate_tts.dart [--force]
//  - 기본은 기존 파일 스킵(멱등). --force 는 전부 재생성.
//  - 사전 조건: 8765 프록시 + 8770 Qwen3 백엔드 기동(svil-ai-work tts_system).
// 주의: GPU 직렬 처리라 병렬 요청 금지 — 한 번에 하나씩 보낸다.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:singpromfter_app/constants/voice_clips.dart';

const _baseUrl = 'http://127.0.0.1:8765';
const _voiceName = 'female_calm';

Future<void> main(List<String> args) async {
  final force = args.contains('--force');
  final outDir = Directory('assets/audio/tts');
  await outDir.create(recursive: true);

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);

  // 서버 상태부터 — qwen3 백엔드까지 살아 있어야 생성이 된다.
  try {
    final req = await client.getUrl(Uri.parse('$_baseUrl/api/tts/status'));
    final res = await req.close();
    final body = jsonDecode(await utf8.decodeStream(res)) as Map<String, dynamic>;
    if (body['qwen3'] != true) {
      stderr.writeln('Qwen3 백엔드(8770)가 꺼져 있습니다. C:\\ai-qwen3tts\\start.bat 을 먼저 켜 주세요.');
      exitCode = 1;
      return;
    }
  } catch (e) {
    stderr.writeln('TTS 프록시(8765)에 연결하지 못했습니다: $e');
    stderr.writeln('C:\\Projects\\svil-ai-work\\tts_system\\start.bat 을 먼저 켜 주세요.');
    exitCode = 1;
    return;
  }

  var made = 0, skipped = 0, failed = 0;
  for (final clip in VoiceClips.all) {
    final file = File('${outDir.path}${Platform.pathSeparator}${clip.id}.wav');
    // 44바이트(WAV 헤더)보다 커야 유효한 파일로 본다.
    if (!force && file.existsSync() && file.lengthSync() > 44) {
      skipped++;
      continue;
    }
    try {
      final req = await client.postUrl(Uri.parse('$_baseUrl/api/tts/generate'));
      req.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
      req.add(utf8.encode(jsonEncode({
        'text': clip.text,
        'voice_name': _voiceName,
        'language': 'ko',
        'speed_pct': 100,
      })));
      final res = await req.close().timeout(const Duration(seconds: 180));
      final bytes = await res.fold<BytesBuilder>(
        BytesBuilder(),
        (b, chunk) => b..add(chunk),
      );
      if (res.statusCode != 200) {
        failed++;
        stderr.writeln('FAIL ${clip.id}: HTTP ${res.statusCode} ${utf8.decode(bytes.takeBytes(), allowMalformed: true)}');
        continue;
      }
      await file.writeAsBytes(bytes.takeBytes());
      made++;
      stdout.writeln('OK   ${clip.id} (${(file.lengthSync() / 1024).round()}KB)');
    } catch (e) {
      failed++;
      stderr.writeln('FAIL ${clip.id}: $e');
    }
  }

  stdout.writeln('생성 $made · 스킵 $skipped · 실패 $failed / 전체 ${VoiceClips.all.length}');
  exitCode = failed > 0 ? 1 : 0;
}
