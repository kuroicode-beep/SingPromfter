// file: test/real/real_ffmpeg_head_trim_test.dart
//
// 실제 ffmpeg로 도는 **옵트인** 테스트 — 「녹음 지연 보정」의 R 녹음 머리 자르기.
//
// 가짜 러너 테스트는 `-i … -ss T`가 머리를 **표본 단위로 정확히** 버린다고 가정한다.
// 몇 ms만 어긋나도 보정의 뜻이 없어지므로(보정 단위가 5ms다) 실물로 고정한다:
// 길이가 정확히 T만큼 줄고, 남은 표본이 원본의 T 뒤와 바이트 단위로 같아야 한다.
// 2채널(반주 채널)도 같은 길이로 잘려야 보컬과 어긋나지 않는다.
//
// 마이크도 스피커도 쓰지 않는다(합성 WAV). 평소 `flutter test`에서는 건너뛴다. 돌리려면:
//   SP_REAL_FFMPEG=1 flutter test test/real/real_ffmpeg_head_trim_test.dart
//
// 🔴 testWidgets로 짜면 안 된다 — 가짜 시계에서는 실제 프로세스가 안 끝난다.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singpromfter_app/services/take_mix_service.dart';

const int _rate = 48000;

/// 위치마다 값이 다른 합성 표본 — 잘린 자리를 내용으로 확인할 수 있다.
int _sample(int i) => (i % 2000) - 1000;

/// 48kHz 16비트 PCM WAV를 쓴다(채널마다 같은 값).
String _writeWav(
  Directory dir,
  String name, {
  required int ms,
  int channels = 1,
}) {
  final frames = _rate * ms ~/ 1000;
  final pcm = Int16List(frames * channels);
  for (var i = 0; i < frames; i++) {
    for (var c = 0; c < channels; c++) {
      pcm[i * channels + c] = _sample(i);
    }
  }
  final data = pcm.buffer.asUint8List();
  final header = ByteData(44);
  void ascii(int at, String text) {
    for (var i = 0; i < text.length; i++) {
      header.setUint8(at + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + data.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, _rate, Endian.little);
  header.setUint32(28, _rate * channels * 2, Endian.little);
  header.setUint16(32, channels * 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, data.length, Endian.little);
  final path = '${dir.path}${Platform.pathSeparator}$name';
  File(path).writeAsBytesSync([...header.buffer.asUint8List(), ...data]);
  return path;
}

/// WAV의 data 청크를 찾아 (채널 수, 첫 채널의 표본들)을 읽는다.
({int channels, List<int> samples}) _readWav(String path) {
  final bytes = File(path).readAsBytesSync();
  final view = ByteData.sublistView(bytes);
  final channels = view.getUint16(22, Endian.little);
  // ffmpeg는 fmt 뒤에 LIST 청크를 끼워 넣는다 — 44바이트 고정으로 읽으면 안 된다.
  var at = 12;
  while (at + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(at, at + 4));
    final size = view.getUint32(at + 4, Endian.little);
    if (id == 'data') {
      final end = (at + 8 + size).clamp(0, bytes.length);
      final pcm = ByteData.sublistView(bytes, at + 8, end);
      return (
        channels: channels,
        samples: [
          for (var i = 0; i + 1 < pcm.lengthInBytes; i += 2 * channels)
            pcm.getInt16(i, Endian.little),
        ],
      );
    }
    at += 8 + size + (size.isOdd ? 1 : 0);
  }
  fail('data 청크를 찾지 못했다: $path');
}

void main() {
  final enabled = Platform.environment['SP_REAL_FFMPEG'] == '1';
  final skip = enabled ? null : 'SP_REAL_FFMPEG=1 일 때만 돈다(실제 ffmpeg 사용)';

  late Directory tmp;
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('sp_real_head_trim_');
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('머리를 표본 단위로 정확히 자른다 — 보컬(1ch)과 반주(2ch)가 같은 길이로', () async {
    for (final trimMs in [5, 40, 300]) {
      final vocal = _writeWav(tmp, 'v.wav', ms: 1000);
      final backing = _writeWav(tmp, 'v_acc.wav', ms: 1000, channels: 2);

      final result = await TakeMixService().trimHeads(
        paths: [vocal, backing],
        trimMs: trimMs,
      );
      expect(result.success, isTrue, reason: '${result.message}');

      final first = _rate * trimMs ~/ 1000;
      final want = _rate * (1000 - trimMs) ~/ 1000;
      for (final (path, channels) in [(vocal, 1), (backing, 2)]) {
        final wav = _readWav(path);
        final why = 'trim=$trimMs ${path.split(Platform.pathSeparator).last}';
        expect(wav.channels, channels, reason: why);
        expect(wav.samples.length, want, reason: why);
        for (var k = 0; k < wav.samples.length; k += 97) {
          expect(wav.samples[k], _sample(first + k), reason: '$why k=$k');
        }
      }
      // 임시·백업 파일이 남지 않는다.
      final left = tmp.listSync().map((e) => e.uri.pathSegments.last).toList()
        ..sort();
      expect(left, ['v.wav', 'v_acc.wav']);
    }
  }, skip: skip);
}
