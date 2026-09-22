// file: test/fakes/fake_mp3.dart
//
// 테스트용 합성 MP3 바이트 — 헤더만 진짜고 오디오 데이터는 0이다.
// 머리 바이트 판정기(audio_header_probe)와 위치 보정본 서비스 테스트가 같이 쓴다.
// 저장소에 실제 음원을 넣지 않으려고 만든다.
import 'dart:typed_data';

/// MPEG1 Layer III 44.1kHz 스테레오 프레임 하나. [bitrateIndex] 9=128k, 11=192k, 14=320k.
/// [tag]를 주면 사이드인포(32바이트) 바로 뒤에 넣는다.
Uint8List mp3Frame(
  int bitrateIndex, {
  String? tag,
  int tagAt = 4 + 32,
  bool mono = false,
}) {
  const rates = [
    0,
    32,
    40,
    48,
    56,
    64,
    80,
    96,
    112,
    128,
    160,
    192,
    224,
    256,
    320,
  ];
  final size = 144 * rates[bitrateIndex] * 1000 ~/ 44100;
  final bytes = Uint8List(size);
  bytes[0] = 0xff;
  bytes[1] = 0xfb; // MPEG1 · Layer III · CRC 없음
  bytes[2] = bitrateIndex << 4; // 44.1kHz · 패딩 없음
  bytes[3] = mono ? 0xc0 : 0x00;
  if (tag != null) {
    for (var i = 0; i < tag.length; i++) {
      bytes[tagAt + i] = tag.codeUnitAt(i);
    }
  }
  return bytes;
}

/// 바이트 조각들을 한 덩어리로 잇는다.
Uint8List joinBytes(List<List<int>> parts) =>
    Uint8List.fromList([for (final part in parts) ...part]);

/// 크기가 [payload]인 ID3v2.3 태그(헤더 10바이트 포함).
Uint8List id3Tag(int payload) {
  final bytes = Uint8List(10 + payload);
  bytes.setAll(0, 'ID3'.codeUnits);
  bytes[3] = 3;
  bytes[6] = (payload >> 21) & 0x7f;
  bytes[7] = (payload >> 14) & 0x7f;
  bytes[8] = (payload >> 7) & 0x7f;
  bytes[9] = payload & 0x7f;
  return bytes;
}

/// 유튜브에서 가져온 원본 같은 VBR MP3 — Xing 태그 프레임 + 비트레이트가 흔들리는 프레임들.
/// [seed]를 바꾸면 크기가 달라진다(「같은 이름, 다른 오디오」를 만들 때 쓴다).
Uint8List fakeVbrMp3({int seed = 0}) => joinBytes([
  id3Tag(35),
  mp3Frame(5, tag: 'Xing'),
  for (var i = 0; i < 12 + seed; i++) mp3Frame(const [11, 13, 14][i % 3]),
]);

/// 분리 서버가 만든 MR 같은 헤더 없는 CBR 320k MP3.
Uint8List fakeCbrMp3() =>
    joinBytes([for (var i = 0; i < 12; i++) mp3Frame(14)]);

/// 확장자만 .mp3인 m4a(AAC) — 구운 키조절 슬롯이 이렇다.
Uint8List fakeM4a() {
  final bytes = Uint8List(64);
  bytes.setAll(4, 'ftypM4A '.codeUnits);
  return bytes;
}
