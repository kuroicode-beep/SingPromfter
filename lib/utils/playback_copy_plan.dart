// file: lib/utils/playback_copy_plan.dart
//
// 「위치 보정본」(재생용 WAV 사본)의 이름·ffmpeg 인자·축출 계획·안내 문구.
// 전부 순수 함수다 — 파일도 프로세스도 건드리지 않는다(테스트 대상).
// 실제로 굽고 지우는 일은 services/playback_copy_service.dart가 한다.
//
// 형식을 WAV(pcm_s16le)로 고른 이유(2026-09-22 실측, Media Foundation seek 17개 지점,
// 값 = MF가 보고한 시각 − 원본의 참 시각):
//   원본 VBR MP3      −217 ~ +742ms (폭 959ms)   ← 고치려는 문제
//   CBR 320k MP3      +12/+24ms, 시작점이 프레임 경계로 ±20ms 물림
//   AAC m4a 256k      +21ms 고정, −20~0ms 물림
//   WAV pcm_s16le     전 지점 0.00ms, 물림 없음. 렌더 0.2~0.34초(MP3의 1/10)
//   FLAC              seek가 무시됨 — 탈락
// WAV는 ffmpeg 디코드와 표본 단위로 같아서, 믹스·반주 자르기·이어붙이기가 원본을
// 쓰든 사본을 쓰든 같은 결과를 낸다. 단점은 크기(곡당 40~70MB)뿐이라 OneDrive 밖의
// 캐시 폴더에 두고 용량 상한으로 오래 안 쓴 것부터 버린다(다시 굽는 데 0.3초).
//
// 🔴 위 표의 CBR +12·AAC +21은 seek 오차가 아니라 **플레이어 축의 머리 상수**다
// (2026-09-22 srdump 실측, 처음부터 디코드해 5·10·30·60초에서 교차상관): MF는 LAME
// encoder_delay(576샘플=12.0ms)·AAC 프라이밍(1024샘플=21.3ms)을 걷어내지 않고, ffmpeg는
// 걷어낸다. 그래서 「MF축 − ffmpeg축」이 VBR·CBR(LAME 태그) 원본 +12.0ms, Info 태그 CBR
// +36.0ms, m4a +21.3ms, WAV 사본 0이다. 원본 위에서 받은 조각의 songPositionMs는 그만큼
// **늦게** 놓이고 사본 위 조각은 0이다 — 한 곡 안에서 두 축의 조각이 섞이면 이음새에
// 12ms 계단이 생긴다. 상수 표로 보정하지 않는 이유: 값이 태그 종류(LAME/Info/없음)에
// 달려 파일마다 태그를 읽어야 하고, 그러면 디코더 내부를 흉내 내는 셈이다. 대신
// 같은 곡이 두 축을 타는 길을 좁힌다(고정 켤 때·R 직전·고정 중 스페이스 직전에
// adoptPlaybackCopyIfIdle로 사본으로 갈아탄다). 「녹음 지연 보정」은 보정본·WAV 반주로
// 받은 조각을 기준으로 맞추는 것이 맞다(설정 도움말).

/// 사본 파일명에서 원본 줄기와 지문을 가르는 표식.
/// 키 변형본의 `__p`와 같은 자리지만 폴더가 달라 서로 섞이지 않는다.
const String kPlaybackCopyMarker = '__play_';

/// 굽는 동안 붙는 꼬리. 끝나면 rename으로 떼어 확정한다 — 앱이 도중에 죽어도
/// 반쪽 WAV가 「완성된 사본」으로 통과하지 못한다(키 변형본 캐시에는 없던 방어).
const String kPlaybackCopyPartSuffix = '.part';

/// 줄기 길이 상한(코드포인트). 제목에는 길이 상한이 없어 100자가 넘는 곡이 실제로
/// 있다 — 캐시 경로(약 63자) + 줄기 + 지문이 Windows의 260자에 닿지 않게 줄인다.
const int kPlaybackCopyStemMax = 48;
const int _kStemKeep = 40;

/// 사본 캐시 용량 상한(바이트). 라이브러리의 VBR 48곡을 전부 구우면 2.33GB라
/// 다 담지는 않는다 — 자주 부르는 곡이 남고, 밀려난 곡은 다음에 물릴 때 다시 굽는다.
const int kPlaybackCopyCacheMaxBytes = 1536 * 1024 * 1024;

/// 곡을 물릴 때 보정본 조회를 기다려 주는 상한. 조회는 stat 두 번이라 보통 수 ms지만,
/// OneDrive 자리표시자처럼 파일 시스템이 멎으면 기다리지 않고 원본을 튼다.
const Duration kPlaybackCopyLookupTimeout = Duration(milliseconds: 700);

/// 곡을 물린 뒤 뒤에서 굽기 시작할 때까지의 여유. 플레이어가 파일을 열고 EQ 분석이
/// 먼저 돌게 비켜 선다 — 이 일은 앱에서 우선순위가 가장 낮다.
const Duration kPlaybackCopyStartDelay = Duration(seconds: 2);

/// WAV 헤더(44바이트)보다 작은 파일은 사본으로 치지 않는다.
const int kPlaybackCopyMinBytes = 45;

/// 지금 물린 재생 파일의 성격. 화면 글자와 녹음 안내가 이 값을 본다.
enum PlaybackSourceKind {
  /// 보정이 필요 없는 파일 — CBR MP3·m4a·WAV, 그리고 키·템포 변형본(m4a).
  plain,

  /// VBR MP3 **원본**을 그대로 재생 중 — seek 뒤 위치가 어긋날 수 있다.
  /// 보정본은 뒤에서 굽고 있고(또는 못 구웠고), 다음에 이 곡을 물릴 때부터 쓰인다.
  vbrOriginal,

  /// 위치 보정본(WAV)을 재생 중 — seek가 정확하다.
  seekCopy,
}

/// 재생 경로 결정 결과. [path]가 null이면 원본을 그대로 재생한다.
typedef PlaybackCopyResolution = ({String? path, PlaybackSourceKind kind});

/// 보정본과 무관한 재생(원본 그대로).
const PlaybackCopyResolution kPlainPlayback = (
  path: null,
  kind: PlaybackSourceKind.plain,
);

/// 고정·녹음 중 VBR 원본을 쓰고 있을 때 곡마다 한 번 띄우는 안내.
const String kVbrOriginalNotice =
    '이 반주는 이동 후 위치가 어긋날 수 있는 형식(VBR)입니다 — '
    '보정본을 준비하는 중이에요. 다음에 이 곡을 열면 적용돼요.';

/// 재생으로 도달한 자리에서 위치 보정본으로 갈아탔을 때 같은 토스트에 얹는 안내.
///
/// VBR 원본을 듣다 멈춘 자리의 보고 위치는 실제 들린 내용과 최대 ±0.7초 어긋나 있다.
/// 사본으로 갈아타면 좌표는 정확해지지만, 소리로 들어갈 자리를 잡는 사용자에게는
/// 「방금 멈춘 자리」가 예고 없이 옮겨진다 — 그 점을 글자로 알린다.
const String kPlaybackCopyAdoptedNotice =
    '위치 보정본으로 갈아탔어요 — 방금 멈춘 자리와 반주가 1초 안쪽으로 어긋날 수 '
    '있으니 화살표로 자리를 다시 잡아 주세요.';

/// 곡·반주 정보 줄에 붙는 글자. 보정본을 쓸 때만 나오고, 아니면 null(아무것도 안 붙음).
String? playbackSourceNote(PlaybackSourceKind kind) =>
    kind == PlaybackSourceKind.seekCopy ? '재생: 위치 보정본' : null;

/// 기존 토스트 문구 **뒤에** VBR 안내를 얹는다. 안내가 없으면 그대로. (순수 함수)
/// 토스트는 한 장뿐이라 「녹음을 시작했습니다」 같은 본문과 같이 실어야 한다.
String withPlaybackCopyNotice(String message, String? notice) =>
    notice == null ? message : '$message\n$notice';

/// VBR 원본 안내를 **곡마다 한 번만** 내보내는 문지기.
class VbrNoticeGate {
  final Set<String> _announced = {};

  /// 이번에 알려야 하면 안내 문구, 아니면 null.
  /// VBR 원본이 아니거나(보정본 사용 중 포함) 이미 알린 곡이면 null이다.
  String? take({required String? songId, required PlaybackSourceKind kind}) {
    if (songId == null || kind != PlaybackSourceKind.vbrOriginal) return null;
    return _announced.add(songId) ? kVbrOriginalNotice : null;
  }
}

/// FNV-1a 32비트를 16진 8자리로. 잘린 줄기끼리 이름이 겹치지 않게 붙인다.
String _fnv1aHex(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash ^= unit & 0xff;
    hash = (hash * 0x01000193) & 0xffffffff;
    hash ^= unit >> 8;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// 원본 파일명에서 사본 이름의 줄기를 만든다. (순수 함수)
///
/// 짧으면 확장자만 뗀 그대로, 길면 앞 40자 + `~` + 전체 줄기의 해시다.
/// 🔴 코드포인트 단위로 자른다 — 코드유닛으로 자르면 이모지가 반쪽이 돼 ffmpeg로
/// 넘기는 경로(UTF-8)와 실제 파일명이 달라진다.
String playbackCopyStem(String sourceFileName) {
  final dot = sourceFileName.lastIndexOf('.');
  final stem = dot > 0 ? sourceFileName.substring(0, dot) : sourceFileName;
  final runes = stem.runes.toList();
  if (runes.length <= kPlaybackCopyStemMax) return stem;
  return '${String.fromCharCodes(runes.take(_kStemKeep))}~${_fnv1aHex(stem)}';
}

/// 이 원본에서 나온 사본이 공유하는 이름 머리. 지문이 달라도 머리는 같다.
String playbackCopyPrefix(String sourceFileName) =>
    '${playbackCopyStem(sourceFileName)}$kPlaybackCopyMarker';

/// 사본 파일명 `<줄기>__play_<크기16진>_<수정시각ms16진>.wav`. (순수 함수)
///
/// 🔴 원본의 **크기+수정시각 지문**을 이름에 넣는다. 반주 파일명은 슬롯마다 고정이라
/// 같은 이름으로 다른 오디오가 들어오는데, 파일명 기준 무효화는 곡 삭제·백업 복원·폰
/// 동기화 수신에서 불리지 않는다. 지문이 다르면 이름이 달라 낡은 사본이 서빙될 길이
/// 구조적으로 없다(File.copy는 mtime을 보존하므로 크기와 mtime이 모두 같은 다른
/// 오디오만 못 거른다 — 현실적으로 없다).
String playbackCopyFileName(
  String sourceFileName, {
  required int sizeBytes,
  required int modifiedMs,
}) =>
    '${playbackCopyPrefix(sourceFileName)}'
    '${sizeBytes.toRadixString(16)}_${modifiedMs.toRadixString(16)}.wav';

/// 이 이름이 [sourceFileName]에서 나온 사본(굽는 중인 `.part` 포함)인가.
bool isPlaybackCopyOf(String copyFileName, String sourceFileName) =>
    copyFileName.startsWith(playbackCopyPrefix(sourceFileName));

/// 사본 폴더의 파일 이름에서 머리(`<줄기>__play_`)를 떼어 낸다. 우리 파일이 아니면 null.
String? playbackCopyPrefixOf(String copyFileName) {
  final at = copyFileName.lastIndexOf(kPlaybackCopyMarker);
  if (at <= 0) return null;
  return copyFileName.substring(0, at + kPlaybackCopyMarker.length);
}

/// 사본을 굽는 ffmpeg 인자. (순수 함수 — 실측으로 검증한 인자 그대로)
///
/// - `-vn -map_metadata -1`: 앨범 표지·태그를 떼어 순수 PCM만 남긴다.
/// - `pcm_s16le`: 원본 샘플레이트·채널을 그대로 둔다(리샘플 없음 = 시간축 불변).
/// - `-f wav`: 출력 이름이 `.part`로 끝나 확장자로 형식을 못 고르므로 명시한다.
/// - `-nostdin`: 뒤에서 도는 작업이 콘솔 입력을 기다리며 멎지 않게 한다.
List<String> buildPlaybackCopyArgs({
  required String input,
  required String output,
}) => [
  '-hide_banner',
  '-nostdin',
  '-y',
  '-i',
  input,
  '-vn',
  '-map_metadata',
  '-1',
  '-c:a',
  'pcm_s16le',
  '-f',
  'wav',
  output,
];

/// 캐시에 있는 사본 하나(축출 계산용).
typedef PlaybackCopyEntry = ({String name, int bytes, int lastUsedMs});

/// 용량 상한을 넘으면 **오래 안 쓴 것부터** 버릴 이름을 고른다. (순수 함수)
/// [keep]의 이름은 버리지 않는다(방금 구운 것·지금 재생 중인 것).
List<String> planPlaybackCopyEviction(
  List<PlaybackCopyEntry> entries, {
  required int maxBytes,
  Set<String> keep = const {},
}) {
  var total = entries.fold<int>(0, (sum, e) => sum + e.bytes);
  if (total <= maxBytes) return const [];
  final candidates = entries.where((e) => !keep.contains(e.name)).toList()
    ..sort((a, b) {
      final byAge = a.lastUsedMs.compareTo(b.lastUsedMs);
      return byAge != 0 ? byAge : a.name.compareTo(b.name);
    });
  final evict = <String>[];
  for (final entry in candidates) {
    if (total <= maxBytes) break;
    evict.add(entry.name);
    total -= entry.bytes;
  }
  return evict;
}
