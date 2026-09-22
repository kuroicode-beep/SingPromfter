// file: test/real/real_ffmpeg_playback_copy_test.dart
//
// 실제 ffmpeg로 도는 **옵트인** 테스트 — VBR MP3의 「위치 보정본」(재생용 WAV 사본).
//
// 가짜 러너 테스트는 「이 인자로 ffmpeg를 띄우면 seek가 안전한 WAV가 나오고 길이가
// 원본과 같다」고 가정한다. 그 가정은 실물로만 확인된다:
//   · 출력 이름이 `.part`라 `-f wav`가 없으면 ffmpeg가 형식을 못 고른다.
//   · 사본의 길이가 원본과 다르면(인코더 딜레이·패딩을 다르게 다루면) 곡 끝으로 갈수록
//     가사와 어긋난다 — 60ms 안이어야 한다.
//   · 사본은 머리 바이트 판정에서 WAV(보정 불필요)로 읽혀야 한다 — 아니면 사본의 사본을 굽는다.
//
// 소리를 내지 않고 마이크도 쓰지 않는다(디코드·인코드만). 평소 `flutter test`에서는
// 건너뛴다. 돌리려면:
//   SP_REAL_FFMPEG=1 flutter test test/real/real_ffmpeg_playback_copy_test.dart
// 실제 곡으로도 보려면 SP_VBR_SAMPLE=<VBR mp3 경로>를 함께 준다(임시 폴더로 **복사해서** 쓴다).
//
// 🔴 testWidgets로 짜면 안 된다 — 가짜 시계에서는 실제 프로세스가 안 끝난다.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singpromfter_app/services/playback_copy_service.dart';
import 'package:singpromfter_app/services/process/external_tool_locator.dart';
import 'package:singpromfter_app/utils/audio_header_probe.dart';
import 'package:singpromfter_app/utils/playback_copy_plan.dart';

/// WAV 헤더에서 길이(ms)를 읽는다 — data 청크 바이트 ÷ 초당 바이트.
/// ffmpeg는 fmt 뒤에 LIST 청크를 끼워 넣으므로 44바이트 고정으로 읽으면 안 된다.
double _wavDurationMs(String path) {
  final bytes = File(path).readAsBytesSync();
  final view = ByteData.sublistView(bytes);
  final byteRate = view.getUint32(28, Endian.little);
  var at = 12;
  while (at + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(at, at + 4));
    final size = view.getUint32(at + 4, Endian.little);
    if (id == 'data') return size * 1000 / byteRate;
    at += 8 + size + (size.isOdd ? 1 : 0);
  }
  fail('data 청크를 찾지 못했다: $path');
}

void main() {
  final enabled = Platform.environment['SP_REAL_FFMPEG'] == '1';
  final skip = enabled ? null : 'SP_REAL_FFMPEG=1 일 때만 돈다(실제 ffmpeg 사용)';
  final samplePath = Platform.environment['SP_VBR_SAMPLE'];
  final sampleSkip =
      skip ??
      (samplePath == null || !File(samplePath).existsSync()
          ? 'SP_VBR_SAMPLE=<VBR mp3 경로>를 줄 때만 돈다'
          : null);

  late Directory tmp;
  late String ffmpeg;
  late String ffprobe;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('sp_real_playcopy_');
    if (!enabled) return;
    final located = await ExternalToolLocator().locate(ExternalTool.ffmpeg);
    expect(located.found, isTrue, reason: 'ffmpeg를 찾지 못했다');
    ffmpeg = located.path!;
    // ffprobe는 ffmpeg와 같은 폴더에 같이 깔린다. 이름뿐인 경로면 PATH에 맡긴다.
    final cut = ffmpeg.lastIndexOf(RegExp(r'[\\/]'));
    ffprobe = cut < 0
        ? 'ffprobe'
        : '${ffmpeg.substring(0, cut + 1)}'
              'ffprobe${ffmpeg.toLowerCase().endsWith('.exe') ? '.exe' : ''}';
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// ffprobe가 보는 길이(ms).
  double probeDurationMs(String path) {
    final result = Process.runSync(ffprobe, [
      '-v',
      'error',
      '-show_entries',
      'format=duration',
      '-of',
      'csv=p=0',
      path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return double.parse('${result.stdout}'.trim()) * 1000;
  }

  /// 구워 보고 약속을 확인한다 — 원본은 그대로, 사본은 WAV, 길이는 60ms 안.
  Future<void> renderAndCheck(File source, String sourceFileName) async {
    final sourceProbe = await probeAudioFile(source.path);
    expect(sourceProbe.kind, AudioFileKind.mp3Vbr, reason: '$sourceProbe');
    final before = source.readAsBytesSync();
    final modified = source.lastModifiedSync();

    final service = PlaybackCopyService(
      cacheDirBuilder: () async => Directory('${tmp.path}/cache'),
    );
    addTearDown(service.dispose);
    final watch = Stopwatch()..start();
    final copy = await service.ensure(
      sourcePath: source.path,
      sourceFileName: sourceFileName,
    );
    watch.stop();

    expect(copy, isNotNull, reason: '렌더가 실패했다');
    expect(copy, endsWith('.wav'));
    // 굽고 나면 .part가 남지 않는다.
    final leftovers = Directory('${tmp.path}/cache')
        .listSync()
        .map((e) => e.path)
        .where((p) => p.endsWith(kPlaybackCopyPartSuffix));
    expect(leftovers, isEmpty);

    // 사본은 seek가 안전한 형식(WAV)으로 읽힌다 — 사본의 사본을 굽지 않는다.
    final copyProbe = await probeAudioFile(copy!);
    expect(copyProbe.kind, AudioFileKind.wav);
    expect(copyProbe.needsSeekCopy, isFalse);

    // 길이가 원본과 같다(60ms 안) — 헤더로 잰 값과 ffprobe로 잰 값 둘 다.
    final sourceMs = probeDurationMs(source.path);
    final headerMs = _wavDurationMs(copy);
    final copyMs = probeDurationMs(copy);
    // ignore: avoid_print
    print(
      '원본 ${sourceMs.toStringAsFixed(1)}ms · 사본 ${copyMs.toStringAsFixed(1)}ms'
      '(헤더 ${headerMs.toStringAsFixed(1)}ms) · 렌더 ${watch.elapsedMilliseconds}ms · '
      '${File(copy).lengthSync() ~/ 1024}KB',
    );
    expect((copyMs - sourceMs).abs(), lessThan(60));
    expect((headerMs - sourceMs).abs(), lessThan(60));

    // 원본은 읽기만 했다.
    expect(source.readAsBytesSync(), before);
    expect(source.lastModifiedSync(), modified);

    // 다음 물림은 사본으로 풀린다.
    final next = await service.resolveForLoad(
      sourcePath: source.path,
      sourceFileName: sourceFileName,
    );
    expect(next.kind, PlaybackSourceKind.seekCopy);
    expect(next.path, copy);
  }

  test(
    '합성 VBR MP3(V0)를 굽는다 — WAV로 읽히고 길이가 60ms 안에서 같다',
    () async {
      // 톤 스윕 → 무음 → 잡음: 비트레이트가 크게 흔들리는 V0 파일이 된다.
      final source = File('${tmp.path}/합성 곡_mr1.mp3');
      final made = Process.runSync(ffmpeg, [
        '-hide_banner',
        '-nostdin',
        '-y',
        '-f',
        'lavfi',
        '-i',
        "aevalsrc='0.5*sin(2*PI*t*(200+400*t))*lt(t,3)+0.4*(random(0)*2-1)*gte(t,5)'"
            ':d=8:s=48000',
        '-c:a',
        'libmp3lame',
        '-q:a',
        '0',
        source.path,
      ]);
      expect(made.exitCode, 0, reason: '${made.stderr}');

      await renderAndCheck(source, '합성 곡_mr1.mp3');
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    '실제 VBR 곡(임시 폴더로 복사한 사본)을 굽는다',
    () async {
      final source = File(samplePath!).copySync('${tmp.path}/실제 곡_mr1.mp3');
      await renderAndCheck(source, '실제 곡_mr1.mp3');
    },
    skip: sampleSkip,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
