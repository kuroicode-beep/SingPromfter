// file: tool/gen_audio/generate_piano.dart
//
// 스케일 트레이닝용 피아노 런 합성기 — 배음 합성(기음+5배음, 지수 감쇠)으로
// 피아노풍 톤을 만들어 assets/audio/piano/run_<midi>.wav 로 저장한다.
// 런 하나 = 5음 스케일(도-레-미-파-솔-파-미-레-도, 120bpm 4분음표).
// 루트 MIDI 48(C3)~65(F4) 반음계 18개 — 남성은 48~60, 여성은 53~65를 쓴다.
//
// 실행: dart run tool/gen_audio/generate_piano.dart  (서버 불필요, 순수 Dart)
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _sampleRate = 32000; // TTS 클립과 동일 포맷(16bit mono 32kHz)
const _noteSeconds = 0.5; // 120bpm 4분음표
const _ringSeconds = 1.2; // 노트 여운(감쇠 꼬리)
const _runOffsets = [0, 2, 4, 5, 7, 5, 4, 2, 0]; // 도레미파솔파미레도
const _rootLow = 48; // C3
const _rootHigh = 65; // F4

/// 배음 진폭 — 피아노 근사(기음이 크고 위로 갈수록 급감).
const _harmonics = [1.0, 0.5, 0.33, 0.2, 0.12, 0.08];

double _midiToHz(int midi) => 440.0 * math.pow(2, (midi - 69) / 12).toDouble();

Future<void> main() async {
  final outDir = Directory('assets/audio/piano');
  await outDir.create(recursive: true);

  for (var root = _rootLow; root <= _rootHigh; root++) {
    final totalSeconds =
        _runOffsets.length * _noteSeconds + _ringSeconds;
    final samples = Float64List((totalSeconds * _sampleRate).round());

    for (var i = 0; i < _runOffsets.length; i++) {
      final hz = _midiToHz(root + _runOffsets[i]);
      final onset = (i * _noteSeconds * _sampleRate).round();
      final ringSamples =
          ((_noteSeconds + _ringSeconds) * _sampleRate).round();
      for (var n = 0; n < ringSamples && onset + n < samples.length; n++) {
        final t = n / _sampleRate;
        // 5ms 어택 + 지수 감쇠 — 피아노 타건 근사.
        final attack = t < 0.005 ? t / 0.005 : 1.0;
        final decay = math.exp(-t / 0.45);
        var v = 0.0;
        for (var h = 0; h < _harmonics.length; h++) {
          // 높은 배음일수록 빨리 죽는다.
          final hDecay = math.exp(-t * (h + 1) * 0.9);
          v += _harmonics[h] * hDecay * math.sin(2 * math.pi * hz * (h + 1) * t);
        }
        samples[onset + n] += v * attack * decay;
      }
    }

    // 정규화(피크 0.6) 후 16bit PCM으로.
    var peak = 0.0;
    for (final s in samples) {
      final a = s.abs();
      if (a > peak) peak = a;
    }
    final gain = peak > 0 ? 0.6 / peak : 0.0;
    final pcm = Int16List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      pcm[i] = (samples[i] * gain * 32767).round().clamp(-32768, 32767);
    }

    final file = File(
      '${outDir.path}${Platform.pathSeparator}run_$root.wav',
    );
    await file.writeAsBytes(_wavBytes(pcm));
    stdout.writeln('OK run_$root.wav (${(file.lengthSync() / 1024).round()}KB)');
  }
  stdout.writeln('피아노 런 ${_rootHigh - _rootLow + 1}개 생성 완료');
}

/// 16bit mono PCM → WAV 컨테이너.
List<int> _wavBytes(Int16List pcm) {
  final dataLen = pcm.length * 2;
  final header = ByteData(44);
  void writeAscii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  writeAscii(0, 'RIFF');
  header.setUint32(4, 36 + dataLen, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little); // fmt 청크 크기
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, 1, Endian.little); // mono
  header.setUint32(24, _sampleRate, Endian.little);
  header.setUint32(28, _sampleRate * 2, Endian.little); // byte rate
  header.setUint16(32, 2, Endian.little); // block align
  header.setUint16(34, 16, Endian.little); // bits
  writeAscii(36, 'data');
  header.setUint32(40, dataLen, Endian.little);

  return [
    ...header.buffer.asUint8List(),
    ...pcm.buffer.asUint8List(),
  ];
}
