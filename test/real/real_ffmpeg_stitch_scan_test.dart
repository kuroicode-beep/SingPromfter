// file: test/real/real_ffmpeg_stitch_scan_test.dart
//
// 실제 ffmpeg로 도는 **옵트인** 테스트 — 이어붙이기의 「내용 시작」 재기.
//
// 가짜 러너 테스트는 silencedetect가 이런 줄을 낸다고 **가정**한다. 그 가정 두 개는
// 실측으로만 확인된다(ffmpeg 8.1.1):
//   · 끝까지 조용한 파일에서도 EOF에 `silence_end`가 찍힌다 — 그래서 volumedetect의
//     최대 음량으로 무음을 가린다.
//   · 입력 쪽 `-ss`는 시각을 0부터 다시 매긴다 — 그래서 건너뛴 길이를 더해 되돌린다.
// ffmpeg가 바뀌어 둘 중 하나가 달라지면 여기서 먼저 깨진다.
//
// 마이크는 쓰지 않는다(합성 WAV). 평소 `flutter test`에서는 건너뛴다. 돌리려면:
//   SP_REAL_FFMPEG=1 flutter test test/real/real_ffmpeg_stitch_scan_test.dart
//
// 🔴 testWidgets로 짜면 안 된다 — 가짜 시계에서는 실제 프로세스 스트림이 안 흐른다.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singpromfter_app/controllers/capture_session.dart';
import 'package:singpromfter_app/services/take_stitch_service.dart';

/// (초, 진폭 0..1) 구간들을 이어 48kHz 모노 16비트 WAV로 쓴다.
Future<String> writeWav(
  Directory dir,
  String name,
  List<(double seconds, double amplitude)> parts,
) async {
  const rate = kSessionSampleRate;
  final total = parts.fold<int>(0, (n, p) => n + (p.$1 * rate).round());
  final samples = Int16List(total);
  var n = 0;
  for (final (seconds, amplitude) in parts) {
    final count = (seconds * rate).round();
    for (var i = 0; i < count; i++, n++) {
      samples[n] = (amplitude * 32767 * sin(2 * pi * 440 * n / rate)).round();
    }
  }
  final data = samples.buffer.asUint8List();
  final path = '${dir.path}/$name';
  await File(path).writeAsBytes([...buildWavHeader(data.length), ...data]);
  return path;
}

void main() {
  final enabled = Platform.environment['SP_REAL_FFMPEG'] == '1';
  final skip = enabled ? null : 'SP_REAL_FFMPEG=1 일 때만 돈다(실제 ffmpeg 사용)';

  late Directory tmp;
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('sp_real_stitch_');
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  StitchSegment seg(String path, int durMs, {int leadIn = 0}) => StitchSegment(
    vocalPath: path,
    songPositionMs: 100000,
    durationMs: durMs,
    leadInMs: leadIn,
  );

  test('끝까지 조용한 조각은 빠진다 — EOF의 silence_end에 속지 않는다', () async {
    final silent = await writeWav(tmp, 'silent.wav', [(2.0, 0.0)]);
    final out = await TakeStitchService().withDetectedOffsets([
      seg(silent, 2000),
      seg(silent, 2000, leadIn: 300),
    ]);
    expect(out, isEmpty);
  }, skip: skip);

  test('리드인 속 소음에 속지 않고 말이 시작하는 자리를 찾는다', () async {
    // 0.26초 소음(키·숨소리) + 1.74초 무음 + 1초 노래 — 노래는 파일 2.0초부터다.
    final path = await writeWav(tmp, 'leadin.wav', [
      (0.26, 0.3),
      (1.74, 0.0),
      (1.0, 0.5),
    ]);
    final service = TakeStitchService();

    final armed = await service.withDetectedOffsets([
      seg(path, 3000, leadIn: 300),
    ]);
    // ignore: avoid_print
    print('armed offset=${armed.single.contentOffsetMs}ms (expected ~2000)');
    expect(armed.single.contentOffsetMs, closeTo(2000, 30));

    // 같은 파일을 리드인 없이 재면 맨 앞 소음 탓에 내용 시작이 0이 된다 — 예전에는
    // 이 값으로 **앞 조각의 꼬리를 이 조각의 녹음 시작에서** 잘랐다.
    final legacy = await service.withDetectedOffsets([seg(path, 3000)]);
    expect(legacy.single.contentOffsetMs, 0);
  }, skip: skip);

  test('누르자마자 부른 조각은 키를 누른 자리가 내용 시작이다', () async {
    final path = await writeWav(tmp, 'loud.wav', [(1.5, 0.5)]);
    final out = await TakeStitchService().withDetectedOffsets([
      seg(path, 1500, leadIn: 300),
      seg(path, 1500),
    ]);
    expect(out.map((s) => s.contentOffsetMs), [300, 0]);
  }, skip: skip);

  test('리드인이 없는 조각(R 녹음)은 예전처럼 앞머리 무음 길이가 나온다', () async {
    final path = await writeWav(tmp, 'r.wav', [(1.0, 0.0), (1.0, 0.5)]);
    final out = await TakeStitchService().withDetectedOffsets([
      seg(path, 2000),
    ]);
    expect(out.single.contentOffsetMs, closeTo(1000, 30));
  }, skip: skip);
}
