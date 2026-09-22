// file: test/utils/audio_header_probe_test.dart
//
// 머리 바이트만으로 「VBR MP3인가」를 가르는 판정기. 프로세스를 띄우지 않는다.
//
// 합성 헤더로 규칙을 고정하고, 실제 파일 4종(VBR·헤더 없는 CBR·Info CBR·내용이
// m4a인 .mp3)은 SP_AUDIO_SAMPLES 폴더가 있을 때만 확인한다(저장소에 음원을 넣지 않는다).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/utils/audio_header_probe.dart';

import '../fakes/fake_mp3.dart';

void main() {
  group('id3v2SkipBytes', () {
    test('태그가 없으면 0', () {
      expect(id3v2SkipBytes(mp3Frame(9)), 0);
      expect(id3v2SkipBytes(const [1, 2, 3]), 0);
    });

    test('synchsafe 크기 + 헤더 10바이트를 건너뛴다', () {
      expect(id3v2SkipBytes(id3Tag(35)), 45);
      // 7비트씩이다 — 0x80 이상이 8비트로 읽히면 앨범 표지 태그에서 첫 프레임을 놓친다.
      expect(id3v2SkipBytes(id3Tag(300000)), 300010);
    });

    test('푸터 플래그가 있으면 10바이트를 더 건너뛴다', () {
      final tag = id3Tag(100)..[5] = 0x10;
      expect(id3v2SkipBytes(tag), 120);
    });
  });

  group('parseMp3FrameHeader', () {
    test('MPEG1 Layer III 128kbps 44.1kHz — 프레임 417바이트, 사이드인포 32', () {
      final header = parseMp3FrameHeader(mp3Frame(9), 0)!;
      expect(header.version, 1);
      expect(header.layer, 3);
      expect(header.bitrateKbps, 128);
      expect(header.sampleRate, 44100);
      expect(header.frameBytes, 417);
      expect(header.sideInfoBytes, 32);
      expect(header.hasCrc, isFalse);
    });

    test('모노면 사이드인포가 17바이트다', () {
      expect(
        parseMp3FrameHeader(mp3Frame(9, mono: true), 0)!.sideInfoBytes,
        17,
      );
    });

    test('MPEG2 Layer III 64kbps 22.05kHz — 프레임이 절반 식(72×)이다', () {
      // 0xF3 = MPEG2 · Layer III · CRC 없음, 0x80 = 64kbps(8번) · 22.05kHz
      final header = parseMp3FrameHeader(const [0xff, 0xf3, 0x80, 0x00], 0)!;
      expect(header.version, 2);
      expect(header.bitrateKbps, 64);
      expect(header.sampleRate, 22050);
      expect(header.frameBytes, 72 * 64000 ~/ 22050);
      expect(header.sideInfoBytes, 17);
    });

    test('동기 워드가 아니거나 못 쓰는 값이면 null', () {
      expect(parseMp3FrameHeader(const [0x00, 0xfb, 0x90, 0x00], 0), isNull);
      // 비트레이트 0번(free)·15번(bad), 샘플레이트 3번(reserved)
      expect(parseMp3FrameHeader(const [0xff, 0xfb, 0x00, 0x00], 0), isNull);
      expect(parseMp3FrameHeader(const [0xff, 0xfb, 0xf0, 0x00], 0), isNull);
      expect(parseMp3FrameHeader(const [0xff, 0xfb, 0x9c, 0x00], 0), isNull);
      // 버전 예약값(01)·계층 예약값(00)
      expect(parseMp3FrameHeader(const [0xff, 0xeb, 0x90, 0x00], 0), isNull);
      expect(parseMp3FrameHeader(const [0xff, 0xf9, 0x90, 0x00], 0), isNull);
      // 범위를 벗어난 위치
      expect(parseMp3FrameHeader(const [0xff, 0xfb, 0x90], 0), isNull);
    });
  });

  group('probeAudioHeader — 태그가 1차 신호', () {
    test('Xing → VBR', () {
      final probe = probeAudioHeader(
        joinBytes([
          mp3Frame(5, tag: 'Xing'),
          mp3Frame(11),
          mp3Frame(14),
          mp3Frame(13),
        ]),
      );
      expect(probe.kind, AudioFileKind.mp3Vbr);
      expect(probe.tag, 'Xing');
      expect(probe.needsSeekCopy, isTrue);
      // 태그 프레임(64k)은 비트레이트 집계에서 빠진다.
      expect(probe.bitratesKbps, [192, 256, 320]);
    });

    test('🔴 Xing인데 앞쪽 프레임이 전부 같은 비트레이트여도 VBR이다(무음 전주)', () {
      final probe = probeAudioHeader(
        joinBytes([
          mp3Frame(5, tag: 'Xing'),
          for (var i = 0; i < 20; i++) mp3Frame(1),
        ]),
      );
      expect(probe.kind, AudioFileKind.mp3Vbr);
      expect(probe.bitratesKbps, [32]);
    });

    test('Info → CBR(보정본 불필요)', () {
      final probe = probeAudioHeader(
        joinBytes([mp3Frame(11, tag: 'Info'), mp3Frame(11), mp3Frame(11)]),
      );
      expect(probe.kind, AudioFileKind.mp3Cbr);
      expect(probe.tag, 'Info');
      expect(probe.needsSeekCopy, isFalse);
    });

    test('VBRI(프레임 시작 + 36) → VBR', () {
      final probe = probeAudioHeader(
        joinBytes([
          mp3Frame(9, tag: 'VBRI', tagAt: 36),
          mp3Frame(9),
          mp3Frame(9),
        ]),
      );
      expect(probe.kind, AudioFileKind.mp3Vbr);
      expect(probe.tag, 'VBRI');
    });

    test('모노 프레임의 Xing은 사이드인포 17바이트 뒤에 있다', () {
      final probe = probeAudioHeader(
        joinBytes([
          mp3Frame(9, tag: 'Xing', tagAt: 4 + 17, mono: true),
          mp3Frame(9, mono: true),
          mp3Frame(9, mono: true),
        ]),
      );
      expect(probe.tag, 'Xing');
      expect(probe.kind, AudioFileKind.mp3Vbr);
    });
  });

  group('probeAudioHeader — 태그 없는 MP3', () {
    test('비트레이트가 한 가지면 CBR', () {
      final probe = probeAudioHeader(
        joinBytes([for (var i = 0; i < 10; i++) mp3Frame(14)]),
      );
      expect(probe.kind, AudioFileKind.mp3Cbr);
      expect(probe.tag, 'none');
      expect(probe.bitratesKbps, [320]);
    });

    test('비트레이트가 흔들리면 VBR', () {
      final probe = probeAudioHeader(
        joinBytes([mp3Frame(9), mp3Frame(11), mp3Frame(9), mp3Frame(14)]),
      );
      expect(probe.kind, AudioFileKind.mp3Vbr);
      expect(probe.bitratesKbps, [128, 192, 320]);
    });

    test('🔴 앞쪽은 한 가지인데 파일 가운데가 다르면 VBR — 무음 전주가 긴 헤더 없는 VBR', () {
      final front = joinBytes([for (var i = 0; i < 10; i++) mp3Frame(1)]);
      // 가운데 창은 프레임 중간에서 시작한다 — 동기 워드를 다시 잡아야 한다.
      final middle = joinBytes([
        Uint8List(137),
        mp3Frame(11),
        mp3Frame(13),
        mp3Frame(11),
        mp3Frame(14),
      ]);
      expect(probeAudioHeader(front).kind, AudioFileKind.mp3Cbr);
      final probe = probeAudioHeader(front, middle: middle);
      expect(probe.kind, AudioFileKind.mp3Vbr);
      expect(probe.bitratesKbps, [32, 192, 256, 320]);
    });

    test('가운데도 같은 비트레이트면 CBR 그대로', () {
      final front = joinBytes([for (var i = 0; i < 10; i++) mp3Frame(14)]);
      final middle = joinBytes([
        Uint8List(55),
        for (var i = 0; i < 6; i++) mp3Frame(14),
      ]);
      expect(
        probeAudioHeader(front, middle: middle).kind,
        AudioFileKind.mp3Cbr,
      );
    });

    test('앞에 쓰레기 바이트가 있어도 첫 유효 프레임을 찾는다', () {
      final probe = probeAudioHeader(
        joinBytes([
          [0x00, 0xff, 0x00, 0x13, 0x37],
          mp3Frame(11, tag: 'Xing'),
          mp3Frame(11),
          mp3Frame(13),
        ]),
      );
      expect(probe.kind, AudioFileKind.mp3Vbr);
    });

    test('동기 워드가 우연히 하나 있어도 다음 프레임이 안 이어지면 MP3로 보지 않는다', () {
      final bytes = Uint8List(4096);
      bytes.setAll(100, const [0xff, 0xfb, 0x90, 0x00]);
      expect(probeAudioHeader(bytes).kind, AudioFileKind.unknown);
    });
  });

  group('probeAudioHeader — MP3가 아닌 내용', () {
    Uint8List magic(String text, {int at = 0}) {
      final bytes = Uint8List(64);
      bytes.setAll(at, text.codeUnits);
      return bytes;
    }

    test('🔴 확장자가 .mp3여도 내용이 m4a(ftyp)면 mp4다 — 구운 키조절 슬롯', () {
      final probe = probeAudioHeader(magic('ftypM4A ', at: 4));
      expect(probe.kind, AudioFileKind.mp4);
      expect(probe.needsSeekCopy, isFalse);
    });

    test('RIFF·fLaC·OggS', () {
      expect(probeAudioHeader(magic('RIFF')).kind, AudioFileKind.wav);
      expect(probeAudioHeader(magic('fLaC')).kind, AudioFileKind.flac);
      expect(probeAudioHeader(magic('OggS')).kind, AudioFileKind.ogg);
    });

    test('너무 짧거나 모르는 내용이면 unknown — 보정본을 만들지 않는다', () {
      expect(probeAudioHeader(const [1, 2, 3]).kind, AudioFileKind.unknown);
      expect(probeAudioHeader(Uint8List(2048)).needsSeekCopy, isFalse);
    });
  });

  group('probeAudioFile — 파일에서 읽기', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('sp_probe_'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    File write(String name, List<int> bytes) =>
        File('${tmp.path}${Platform.pathSeparator}$name')
          ..writeAsBytesSync(bytes);

    test('🔴 머리 창(64KB)보다 큰 ID3v2 태그를 건너뛰고 첫 프레임에 닿는다', () async {
      final file = write(
        '표지 있는 곡_mr1.mp3',
        joinBytes([
          id3Tag(300000),
          mp3Frame(5, tag: 'Xing'),
          mp3Frame(11),
          mp3Frame(14),
        ]),
      );
      final probe = await probeAudioFile(file.path);
      expect(probe.kind, AudioFileKind.mp3Vbr);
    });

    test('태그 없는 파일은 가운데 창까지 읽어 판정한다', () async {
      // 앞 700프레임(약 73KB)은 32kbps, 뒤는 256/320kbps — 머리 창(64KB)만 보면 CBR이다.
      final file = write(
        'headerless_vbr.mp3',
        joinBytes([
          for (var i = 0; i < 700; i++) mp3Frame(1),
          for (var i = 0; i < 200; i++) mp3Frame(i.isEven ? 14 : 13),
        ]),
      );
      final probe = await probeAudioFile(file.path);
      expect(probe.tag, 'none');
      expect(probe.kind, AudioFileKind.mp3Vbr);
    });

    test('헤더 없는 CBR은 가운데를 봐도 CBR이다', () async {
      final file = write(
        'cbr.mp3',
        joinBytes([for (var i = 0; i < 300; i++) mp3Frame(14)]),
      );
      expect((await probeAudioFile(file.path)).kind, AudioFileKind.mp3Cbr);
    });

    test('없는 파일·빈 파일은 던지지 않고 unknown', () async {
      expect(
        (await probeAudioFile('${tmp.path}/nope.mp3')).kind,
        AudioFileKind.unknown,
      );
      expect(
        (await probeAudioFile(write('empty.mp3', const []).path)).kind,
        AudioFileKind.unknown,
      );
    });
  });

  group('실제 파일(SP_AUDIO_SAMPLES 폴더가 있을 때만)', () {
    final dir = Platform.environment['SP_AUDIO_SAMPLES'];
    final skip = dir == null || !Directory(dir).existsSync()
        ? 'SP_AUDIO_SAMPLES=<폴더>일 때만 돈다(vbr_mr1·cbr_mr2·info_mr3·m4a_mr3.mp3)'
        : null;

    Future<AudioHeaderProbe> probe(String name) =>
        probeAudioFile('$dir${Platform.pathSeparator}$name');

    test('유튜브에서 가져온 원본(Xing) → VBR', () async {
      final result = await probe('vbr_mr1.mp3');
      expect(result.kind, AudioFileKind.mp3Vbr);
      expect(result.tag, 'Xing');
      expect(result.bitratesKbps.length, greaterThan(1));
    }, skip: skip);

    test('분리 서버가 만든 MR(헤더 없는 320k) → CBR', () async {
      final result = await probe('cbr_mr2.mp3');
      expect(result.kind, AudioFileKind.mp3Cbr);
      expect(result.tag, 'none');
      expect(result.bitratesKbps, [320]);
    }, skip: skip);

    test('Info 헤더 → CBR', () async {
      final result = await probe('info_mr3.mp3');
      expect(result.kind, AudioFileKind.mp3Cbr);
      expect(result.tag, 'Info');
    }, skip: skip);

    test('확장자만 .mp3인 m4a → mp4', () async {
      expect((await probe('m4a_mr3.mp3')).kind, AudioFileKind.mp4);
    }, skip: skip);
  });
}
