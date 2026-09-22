// file: lib/utils/audio_header_probe.dart
//
// 오디오 파일의 **머리 바이트만** 보고 「VBR MP3인가」를 판정한다. 프로세스를 띄우지
// 않는다(ffprobe 없음) — 곡을 물릴 때마다 도는 길이라 수 ms 안에 끝나야 한다.
//
// 왜 필요한가: Windows의 Media Foundation은 VBR MP3에서 seek 위치를 비트레이트로
// 어림한다. 실측(2026-09-22, 17개 지점)으로 −217~+742ms가 어긋났고, 그 오차가 녹음
// 조각의 곡 좌표에 그대로 실린다. CBR MP3·AAC(m4a)·WAV는 어긋나지 않는다. 그래서
// 「VBR MP3일 때만」 위치 보정본(WAV)을 만든다 — services/playback_copy_service.dart.
//
// 🔴 확장자를 믿지 않는다. 이 앱의 반주 파일명은 언제나 `<제목>_mr<슬롯>.mp3`인데
// 구운 키조절 슬롯은 내용이 m4a(AAC)다(실측: 140개 중 48개). 내용으로 판정한다.
//
// 판정 순서(파이썬 원형이 라이브러리 140개에서 ffprobe와 전부 일치):
//   1. `ID3`면 10 + synchsafe 크기(+푸터 10)만큼 건너뛴다.
//   2. `ftyp`(4..8)·`RIFF`·`fLaC`·`OggS`면 MP3가 아니다 — 보정본이 필요 없다.
//   3. 첫 유효 MPEG 프레임을 찾는다(같은 규격의 다음 프레임이 이어지는지로 확인).
//   4. 프레임 시작 + 4 + 사이드인포 자리의 4바이트: `Xing`=VBR, `Info`=CBR.
//   5. 프레임 시작 + 36의 `VBRI`=VBR(프라운호퍼 인코더).
//   6. 태그가 없으면 앞쪽 프레임들의 비트레이트가 서로 다른지 본다. 🔴 앞쪽만 보면
//      무음 전주가 긴 VBR을 CBR로 오판한다(전부 32kbps) — 파일 **가운데** 창도 본다.
import 'dart:io';
import 'dart:typed_data';

/// 파일 내용으로 가른 종류.
enum AudioFileKind {
  /// 가변 비트레이트 MP3 — Media Foundation의 seek가 어긋난다. 보정본 대상.
  mp3Vbr,

  /// 고정 비트레이트 MP3(`Info` 헤더 또는 헤더 없음). seek 오차 폭 12ms — 그대로 쓴다.
  mp3Cbr,

  /// MP4/M4A(AAC). 확장자가 `.mp3`여도 내용이 이것일 수 있다.
  mp4,
  wav,
  flac,
  ogg,

  /// 못 읽었거나 모르는 형식 — 보정본을 만들지 않는다(원본 그대로 재생).
  unknown,
}

/// 머리 바이트 판정 결과.
class AudioHeaderProbe {
  final AudioFileKind kind;

  /// 첫 프레임에서 찾은 태그: 'Xing' · 'Info' · 'VBRI' · 'none'. MP3가 아니면 'none'.
  final String tag;

  /// 훑어본 프레임들의 비트레이트(kbps, 오름차순·중복 없음). 태그 프레임은 뺀다.
  final List<int> bitratesKbps;

  const AudioHeaderProbe({
    required this.kind,
    this.tag = 'none',
    this.bitratesKbps = const [],
  });

  static const unknown = AudioHeaderProbe(kind: AudioFileKind.unknown);

  /// 위치 보정본(WAV)이 필요한 파일인가 — VBR MP3뿐이다.
  bool get needsSeekCopy => kind == AudioFileKind.mp3Vbr;

  @override
  String toString() => 'AudioHeaderProbe($kind, tag=$tag, kbps=$bitratesKbps)';
}

/// MPEG 오디오 프레임 헤더 4바이트를 푼 값.
class Mp3FrameHeader {
  /// 1 = MPEG1, 2 = MPEG2, 25 = MPEG2.5
  final int version;

  /// 1~3
  final int layer;
  final int bitrateKbps;
  final int sampleRate;

  /// 채널 모드 2비트. 3이면 모노.
  final int channelMode;

  /// CRC가 붙었는가(붙으면 헤더 뒤에 2바이트가 더 온다).
  final bool hasCrc;

  /// 이 프레임의 바이트 수(헤더 포함).
  final int frameBytes;

  const Mp3FrameHeader({
    required this.version,
    required this.layer,
    required this.bitrateKbps,
    required this.sampleRate,
    required this.channelMode,
    required this.hasCrc,
    required this.frameBytes,
  });

  bool get mono => channelMode == 3;

  /// 사이드인포 바이트 수 — Xing/Info 태그는 그 바로 뒤에 온다(Layer III 기준).
  int get sideInfoBytes => version == 1 ? (mono ? 17 : 32) : (mono ? 9 : 17);

  /// 같은 스트림의 프레임인가(규격·계층·샘플레이트가 같다). 가짜 동기 워드를 거른다.
  bool sameStreamAs(Mp3FrameHeader other) =>
      version == other.version &&
      layer == other.layer &&
      sampleRate == other.sampleRate;
}

// (MPEG1이면 1, 아니면 2) × 계층 → 비트레이트 표(kbps). 0과 15번은 못 쓰는 값이다.
const Map<int, List<int>> _kBitrates = {
  11: [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448, 0],
  12: [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 0],
  13: [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0],
  21: [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256, 0],
  22: [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0],
  23: [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0],
};

const Map<int, List<int>> _kSampleRates = {
  1: [44100, 48000, 32000],
  2: [22050, 24000, 16000],
  25: [11025, 12000, 8000],
};

/// 머리 창 크기. ID3v2 뒤부터 이만큼 읽는다 — 320kbps 프레임 60개 남짓.
const int kAudioProbeWindowBytes = 64 * 1024;

/// 가운데 창 크기. 동기 워드를 다시 잡을 여유를 두고 프레임 20~30개를 본다.
const int kAudioProbeMiddleBytes = 32 * 1024;

/// 한 창에서 훑는 프레임 수 상한.
const int kAudioProbeMaxFrames = 120;

/// 파일 맨 앞 10바이트로 ID3v2 태그 길이를 구한다. 태그가 없으면 0. (순수 함수)
///
/// 크기는 synchsafe 정수(바이트마다 7비트)다. 플래그의 0x10은 푸터(10바이트)다.
int id3v2SkipBytes(List<int> head) {
  if (head.length < 10) return 0;
  if (head[0] != 0x49 || head[1] != 0x44 || head[2] != 0x33) return 0; // 'ID3'
  final size =
      ((head[6] & 0x7f) << 21) |
      ((head[7] & 0x7f) << 14) |
      ((head[8] & 0x7f) << 7) |
      (head[9] & 0x7f);
  final footer = (head[5] & 0x10) != 0 ? 10 : 0;
  return 10 + size + footer;
}

/// [offset]의 4바이트를 MPEG 프레임 헤더로 푼다. 헤더가 아니면 null. (순수 함수)
Mp3FrameHeader? parseMp3FrameHeader(List<int> bytes, int offset) {
  if (offset < 0 || offset + 4 > bytes.length) return null;
  final b0 = bytes[offset];
  final b1 = bytes[offset + 1];
  final b2 = bytes[offset + 2];
  final b3 = bytes[offset + 3];
  if (b0 != 0xff || (b1 & 0xe0) != 0xe0) return null;
  final versionBits = (b1 >> 3) & 3;
  final layerBits = (b1 >> 1) & 3;
  if (versionBits == 1 || layerBits == 0) return null; // 예약값
  final version = switch (versionBits) {
    3 => 1,
    2 => 2,
    _ => 25,
  };
  final layer = 4 - layerBits; // 3→1, 2→2, 1→3
  final bitrateIndex = (b2 >> 4) & 15;
  final rateIndex = (b2 >> 2) & 3;
  if (bitrateIndex == 0 || bitrateIndex == 15 || rateIndex == 3) return null;
  final padding = (b2 >> 1) & 1;
  final bitrate = _kBitrates[(version == 1 ? 10 : 20) + layer]![bitrateIndex];
  final sampleRate = _kSampleRates[version]![rateIndex];
  final int frameBytes;
  if (layer == 1) {
    frameBytes = (12 * bitrate * 1000 ~/ sampleRate + padding) * 4;
  } else if (layer == 2 || version == 1) {
    frameBytes = 144 * bitrate * 1000 ~/ sampleRate + padding;
  } else {
    frameBytes = 72 * bitrate * 1000 ~/ sampleRate + padding;
  }
  if (frameBytes <= 4) return null;
  return Mp3FrameHeader(
    version: version,
    layer: layer,
    bitrateKbps: bitrate,
    sampleRate: sampleRate,
    channelMode: (b3 >> 6) & 3,
    hasCrc: (b1 & 1) == 0,
    frameBytes: frameBytes,
  );
}

/// [from]부터 훑어 첫 유효 프레임의 위치를 찾는다. 없으면 -1. (순수 함수)
///
/// 동기 워드(0xFFE)는 오디오 데이터 안에도 우연히 나온다. 같은 규격의 프레임이
/// [chain]개 연달아 이어져야 진짜로 본다 — 머리는 2개, 파일 가운데는 3개를 쓴다.
int findMp3Frame(List<int> bytes, {int from = 0, int chain = 2}) {
  for (var i = from; i + 4 <= bytes.length; i++) {
    if (bytes[i] != 0xff) continue;
    final first = parseMp3FrameHeader(bytes, i);
    if (first == null) continue;
    var at = i;
    var header = first;
    var linked = 1;
    while (linked < chain) {
      final next = parseMp3FrameHeader(bytes, at + header.frameBytes);
      if (next == null || !next.sameStreamAs(first)) break;
      at += header.frameBytes;
      header = next;
      linked += 1;
    }
    if (linked >= chain) return i;
  }
  return -1;
}

/// [start]의 프레임부터 이어지는 프레임들의 비트레이트를 모은다. (순수 함수)
/// [skipFirst]면 첫 프레임은 뺀다 — Xing/Info 태그 프레임은 비트레이트가 따로 논다.
Set<int> collectMp3Bitrates(
  List<int> bytes,
  int start, {
  bool skipFirst = false,
  int maxFrames = kAudioProbeMaxFrames,
}) {
  final seen = <int>{};
  final first = parseMp3FrameHeader(bytes, start);
  if (first == null) return seen;
  var at = start;
  for (var n = 0; n < maxFrames; n++) {
    final header = parseMp3FrameHeader(bytes, at);
    if (header == null || !header.sameStreamAs(first)) break;
    if (!(skipFirst && n == 0)) seen.add(header.bitrateKbps);
    at += header.frameBytes;
  }
  return seen;
}

bool _matches(List<int> bytes, int offset, String ascii) {
  if (offset < 0 || offset + ascii.length > bytes.length) return false;
  for (var i = 0; i < ascii.length; i++) {
    if (bytes[offset + i] != ascii.codeUnitAt(i)) return false;
  }
  return true;
}

/// 머리 바이트로 종류를 판정한다. (순수 함수 — 파일도 프로세스도 건드리지 않는다)
///
/// [body]는 **ID3v2 태그 바로 뒤**(태그가 없으면 파일 맨 앞)부터의 바이트다.
/// [middle]은 파일 가운데쯤의 창(선택)이다 — 태그 없는 파일에서만 쓰인다.
AudioHeaderProbe probeAudioHeader(List<int> body, {List<int>? middle}) {
  if (body.length < 12) return AudioHeaderProbe.unknown;
  if (_matches(body, 4, 'ftyp')) {
    return const AudioHeaderProbe(kind: AudioFileKind.mp4);
  }
  if (_matches(body, 0, 'RIFF')) {
    return const AudioHeaderProbe(kind: AudioFileKind.wav);
  }
  if (_matches(body, 0, 'fLaC')) {
    return const AudioHeaderProbe(kind: AudioFileKind.flac);
  }
  if (_matches(body, 0, 'OggS')) {
    return const AudioHeaderProbe(kind: AudioFileKind.ogg);
  }

  final start = findMp3Frame(body);
  if (start < 0) return AudioHeaderProbe.unknown;
  final first = parseMp3FrameHeader(body, start)!;

  // 1차 신호는 태그다. CRC가 붙은 프레임이면 태그가 2바이트 뒤로 밀린다.
  final tagAt = start + 4 + first.sideInfoBytes;
  var tag = 'none';
  for (final at in [tagAt, tagAt + 2]) {
    if (_matches(body, at, 'Xing')) tag = 'Xing';
    if (_matches(body, at, 'Info')) tag = 'Info';
    if (tag != 'none') break;
  }
  if (tag == 'none' && _matches(body, start + 36, 'VBRI')) tag = 'VBRI';

  final rates = collectMp3Bitrates(body, start, skipFirst: tag != 'none');
  if (tag == 'none' && rates.length <= 1 && middle != null) {
    final mid = findMp3Frame(middle, chain: 3);
    if (mid >= 0) {
      final header = parseMp3FrameHeader(middle, mid)!;
      if (header.sameStreamAs(first)) {
        rates.addAll(collectMp3Bitrates(middle, mid));
      }
    }
  }
  final sorted = rates.toList()..sort();

  final vbr = switch (tag) {
    'Xing' || 'VBRI' => true,
    'Info' => false,
    _ => rates.length > 1,
  };
  return AudioHeaderProbe(
    kind: vbr ? AudioFileKind.mp3Vbr : AudioFileKind.mp3Cbr,
    tag: tag,
    bitratesKbps: sorted,
  );
}

/// 파일 하나를 판정한다. 못 읽으면 [AudioHeaderProbe.unknown] — 던지지 않는다.
///
/// 읽는 양은 머리 64KB(+태그 없는 MP3만 가운데 32KB)뿐이다. ID3v2 태그는 **건너뛴다**
/// (앨범 표지가 박힌 태그는 수백 KB라, 앞에서부터 읽으면 첫 프레임에 못 닿는다).
Future<AudioHeaderProbe> probeAudioFile(String path) async {
  RandomAccessFile? raf;
  try {
    raf = await File(path).open();
    final length = await raf.length();
    final head = await raf.read(10);
    final skip = id3v2SkipBytes(head);
    if (skip >= length) return AudioHeaderProbe.unknown;
    await raf.setPosition(skip);
    final Uint8List body = await raf.read(kAudioProbeWindowBytes);
    final probe = probeAudioHeader(body);
    final undecided =
        probe.kind == AudioFileKind.mp3Cbr &&
        probe.tag == 'none' &&
        probe.bitratesKbps.length <= 1;
    if (!undecided) return probe;
    // 태그 없는 MP3인데 앞쪽이 한 비트레이트다 — 가운데를 한 번 더 본다.
    final middleAt = skip + (length - skip) ~/ 2;
    if (middleAt <= skip + body.length) return probe;
    await raf.setPosition(middleAt);
    final middle = await raf.read(kAudioProbeMiddleBytes);
    return probeAudioHeader(body, middle: middle);
  } catch (_) {
    return AudioHeaderProbe.unknown;
  } finally {
    try {
      await raf?.close();
    } catch (_) {}
  }
}
