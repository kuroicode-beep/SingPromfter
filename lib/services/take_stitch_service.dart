// file: lib/services/take_stitch_service.dart
//
// 조각 이어붙이기 — 곡을 나눠 녹음한 테이크 여러 개를 한 벌의 보컬로 잇는다.
//
// 랩처럼 빠른 구간은 한 번에 뱉기 어려워 두 줄씩 끊어 녹음하게 된다(펀치인).
// 각 테이크는 녹음을 시작한 순간의 곡 재생 위치(songPositionMs)를 갖고 있어
// 「파일 시각 t = 곡 시각 songPositionMs + t」로 정확히 되돌릴 수 있다.
// 그래서 이어붙이기는 귀로 맞추는 일이 아니라 계산이다.
//
// 🔴 이음새를 「조각 시작 위치」로 정하면 안 된다. 박을 미리 타려고 2마디쯤
// 앞에서 녹음을 걸기 때문에, 조각의 리드인이 **앞 조각의 가사 줄까지 덮는다.**
// 그러면 두 조각이 같은 줄을 가리켜 앞 조각이 통째로 버려진다(설계 초안의
// 실제 결함 — 테스트에서 드러났다).
//
// 그래서 **소리가 실제로 시작하는 지점**을 본다. 헤드폰을 끼고 1채널로 받으면
// 리드인 구간은 무음이라 이 판정이 정확하다. 그렇게 얻은 내용 시작점을 가까운
// **싱크 가사 줄 경계**로 스냅한다 — 줄 경계는 박 위이면서 말이 끊기는 자리라
// 단어 중간이 아니라 빈 곳에서 잘린다.
//
// 반주는 조각에서 가져오지 않는다 — 2채널로 받았다면 조각마다 반주가 들어
// 있어서 그대로 겹치면 울린다. 이어붙인 보컬을 원본 반주 한 벌 위에 얹는다.
//
// ── v5.16.0에서 고친 것 ─────────────────────────────────────────
// · 좌표축: 조각 좌표(songPositionMs)는 **플레이어 축**이다. 줄 경계도 같은 축으로
//   옮겨야 스냅이 맞는다([stitchLineStartsMs]). 예전에는 LRC 원본 축 값을 그대로
//   넘겨, 가사 오프셋이 1800ms인 곡에서 ±200ms 스냅이 엉뚱한 줄을 잡거나 아예
//   못 잡았다.
// · 무음 조각: 꺼진 장치를 녹음한 조각이 끼면, 그 조각의 「내용 시작」이 앞 조각의
//   꼬리를 잘라 놓고 자기는 아무 소리도 안 낸다 — 노래에 구멍이 난다. 뺀다.
// · 리드인: 녹음 고정 조각은 머리에 최대 300ms의 리드인(키 누르기 전 소리)이 있다.
//   거기 든 키 소리·숨소리를 「맨 앞부터 소리가 있다」로 읽으면 내용 시작이 곧 녹음
//   시작이 되어, **앞 조각의 꼬리가 다음 조각의 말 시작이 아니라 녹음 시작에서
//   잘렸다.** 리드인 + 250ms부터 잰다.
// · 스냅이 조각 자기 시작보다 앞으로 가면 파일 오프셋이 음수가 된다 — 없는 소리를
//   자르는 셈이라 조각이 그만큼 일찍 놓인다. 자기 시작에서 막는다.
//
// ── v5.17.0에서 고친 것 ─────────────────────────────────────────
// · 같은 줄을 다시 받은 조각: 예전에는 「내용 시작이 몇 ms 늦은 쪽」이 남았다. 새로 받은
//   조각이 50ms 일찍 들어오면 **옛 조각이 이겼고**, 가사가 없는 곡에서는 옛 조각의
//   80ms 토막 뒤에 새 조각이 붙어 첫 음절이 두 번 났다. 이제 같은 자리의 조각은
//   **받은 시각이 가장 늦은 것 하나만** 쓰고 나머지는 통째로 뺀다([dedupeSameLineSegments]).
import 'dart:io';

import '../controllers/recording_controller.dart' show isSilentTake;
import '../models/recording_take.dart';
import '../models/timed_lyrics.dart';
import 'lyrics_sync_math.dart';
import 'process/external_tool_locator.dart';
import 'process/process_runner.dart';
import 'take_mix_service.dart';

/// 이어붙일 조각 하나. (경로 + 곡 위 좌표)
class StitchSegment {
  final String vocalPath;

  /// 녹음을 시작한 순간의 곡 재생 위치(ms). 파일 t=0의 좌표다(플레이어 축).
  final int songPositionMs;

  /// 이 조각의 길이(ms).
  final int durationMs;

  /// 파일 안에서 **소리가 시작하는 지점**(ms). 리드인 무음의 길이다.
  /// 0이면 녹음을 걸자마자 뱉었다는 뜻.
  final int contentOffsetMs;

  /// 파일 머리에 일부러 담은 리드인 길이(ms) — 녹음 고정 조각만 0보다 크다.
  /// 고정값(300)이 아니다. 곡 앞머리에서 찍은 조각은 더 짧다.
  final int leadInMs;

  /// 녹음할 때 잰 최대 레벨(dBFS). null이면 모른다(파일을 직접 재서 가린다).
  final double? peakDbfs;

  /// 이 조각을 받은 시각. 같은 줄을 다시 받은 조각들 가운데 **최신 것**을 고르는 근거다.
  /// null이면 모른다 — 시각을 아는 조각에게 지고, 서로 모르면 입력 순서상 뒤가 이긴다.
  final DateTime? recordedAt;

  const StitchSegment({
    required this.vocalPath,
    required this.songPositionMs,
    required this.durationMs,
    this.contentOffsetMs = 0,
    this.leadInMs = 0,
    this.peakDbfs,
    this.recordedAt,
  });

  /// 곡 타임라인 기준, 이 조각의 내용이 시작하는 시각(ms).
  int get contentStartMs => songPositionMs + contentOffsetMs;

  /// 이 조각이 덮는 곡 구간의 끝(ms).
  int get songEndMs => songPositionMs + durationMs;

  /// 내용 시작점만 바꾼 사본. 나머지 좌표는 그대로 들고 간다.
  StitchSegment withContentOffset(int offsetMs) => StitchSegment(
    vocalPath: vocalPath,
    songPositionMs: songPositionMs,
    durationMs: durationMs,
    contentOffsetMs: offsetMs,
    leadInMs: leadInMs,
    peakDbfs: peakDbfs,
    recordedAt: recordedAt,
  );
}

/// 조각이 실제로 쓰일 곡 구간. (이음새 계산 결과)
class StitchSpan {
  final StitchSegment segment;

  /// 곡 타임라인 기준 시작·끝(ms).
  final int startMs;
  final int endMs;

  const StitchSpan({
    required this.segment,
    required this.startMs,
    required this.endMs,
  });

  int get lengthMs => endMs - startMs;
}

/// 두 테이크를 한 타임라인에 올릴 수 있는가. (순수 함수)
///
/// 템포를 바꾸면 재생 파일의 길이 자체가 달라진다 — 0.8배로 받은 조각의 60초는
/// 원래 속도의 48초 지점이다. 좌표를 그대로 섞으면 조각이 엉뚱한 자리에 놓인다.
/// 템포는 5% 단위로만 바뀌므로 0.5% 안쪽이면 같은 값이다.
bool isSameStitchTimeline(double tempoScaleA, double tempoScaleB) =>
    (tempoScaleA - tempoScaleB).abs() < 0.005;

/// [picked]와 한 벌로 이을 **재료**를 고른다. (순수 함수)
///
/// 같은 곡 · 곡 좌표가 있음 · 같은 템포 · **이어붙인 결과물이 아님**.
///
/// 🔴 결과물은 곡 좌표 0에서 시작하는 한 벌이라 좌표만 보면 조각과 구분이 안 된다.
/// 재료에 끼면 첫 조각과 같은 자리를 차지해 첫 조각을 밀어내고, 그사이 **지운 조각의
/// 소리까지 되살린다**(결과물 안에 그 소리가 들어 있다). 표식([RecordingTake.stitched])으로 뺀다.
List<RecordingTake> stitchSiblings(
  Iterable<RecordingTake> takes,
  RecordingTake picked,
) => [
  for (final t in takes)
    if (t.songId == picked.songId &&
        t.isStitchable &&
        isSameStitchTimeline(t.tempoScale, picked.tempoScale))
      t,
];

/// 싱크 가사 줄 시작을 **플레이어 축**(ms)으로 옮긴다. (순수 함수)
///
/// 🔴 조각 좌표(RecordingTake.songPositionMs)는 재생 중인 파일의 시각이다. 가사 줄
/// 시각은 LRC 원본 축이라 그대로 비교하면 가사 오프셋·트림·템포만큼 어긋난다.
/// 환산은 화면이 줄로 이동할 때 쓰는 [LyricsSyncMath.playerPositionForLine]과
/// **같은 식**을 쓴다 — 가사가 뜨는 순간이 곧 그 줄의 경계다.
///
/// [trackStartMs]는 슬롯의 트림 시작(원본 축, BackingTrack.startMs),
/// [lyricsOffsetMs]는 그 슬롯의 가사 오프셋, [tempoScale]은 녹음 당시 템포다.
List<int> stitchLineStartsMs({
  required TimedLyrics lyrics,
  int? trackStartMs,
  int lyricsOffsetMs = 0,
  double tempoScale = 1,
}) {
  if (lyrics.isEmpty) return const [];
  // 트림 지점은 원본 축으로 저장돼 있다 — 재생 컨트롤러와 같이 렌더 축으로 옮긴다.
  final renderedStartMs = trackStartMs == null
      ? null
      : LyricsSyncMath.toRendered(
          Duration(milliseconds: trackStartMs),
          tempoScale,
        ).inMilliseconds;
  final starts = <int>{
    for (var i = 0; i < lyrics.lines.length; i++)
      LyricsSyncMath.playerPositionForLine(
        lyrics: lyrics,
        index: i,
        trackStartMs: renderedStartMs,
        lyricsOffsetMs: lyricsOffsetMs,
        tempoScale: tempoScale,
      ).inMilliseconds,
  };
  return starts.toList()..sort();
}

/// 내용 시작점을 가까운 가사 줄 경계로 당긴다. (순수 함수)
///
/// 무음 판정은 숨소리·옷 스치는 소리에 몇십 ms씩 흔들린다. 줄 경계가
/// [toleranceMs] 안에 있으면 거기로 스냅해 **박 위에서** 잘리게 한다.
/// 가까운 줄이 없으면 잰 값을 그대로 믿는다.
int snapToLineStart(
  int ms,
  List<int> lineStartsMs, {
  int toleranceMs = kStitchSnapToleranceMs,
}) {
  int? best;
  for (final line in lineStartsMs) {
    final d = (line - ms).abs();
    if (d <= toleranceMs && (best == null || d < (best - ms).abs())) {
      best = line;
    }
  }
  return best ?? ms;
}

/// 조각의 내용 시작점을 줄 경계로 당기되 **자기 녹음 시작보다 앞으로는 안 간다.**
/// (순수 함수)
///
/// 줄 경계가 조각 시작보다 앞에 있으면(박보다 조금 늦게 녹음을 건 경우) 스냅한
/// 자리에는 이 조각의 소리가 없다. 그대로 두면 파일 오프셋이 음수가 되고,
/// 조각은 그만큼 **일찍** 놓여 박이 어긋난다. 갈 수 있는 데까지만 간다.
int snappedContentStartMs(StitchSegment segment, List<int> lineStartsMs) {
  final snapped = snapToLineStart(segment.contentStartMs, lineStartsMs);
  return snapped < segment.songPositionMs ? segment.songPositionMs : snapped;
}

/// 같은 자리를 다시 받은 조각을 가려낸 결과.
class StitchDedupe {
  /// 남긴 조각 — 시작이 이른 순.
  final List<StitchSegment> kept;

  /// [kept]와 같은 순서의 시작 시각(ms, 줄 경계로 스냅된 값).
  final List<int> startsMs;

  /// 더 늦게 받은 조각에 밀려 **통째로 빠진** 조각 수.
  final int droppedCount;

  const StitchDedupe({
    required this.kept,
    required this.startsMs,
    required this.droppedCount,
  });
}

/// 입력 순번·조각·스냅된 시작을 한데 묶은 것([dedupeSameLineSegments] 안에서만 쓴다).
typedef _StitchEntry = ({int index, StitchSegment segment, int startMs});

/// [candidate]가 [best]보다 나중에 받은 조각인가. (순수 함수)
///
/// 받은 시각으로 가리고, 시각을 모르는 조각은 아는 조각에게 진다. 둘 다 모르거나 같으면
/// 입력 순서상 뒤가 이긴다 — 시각 없이 부르던 예전 호출부의 동작이다.
bool _isNewerStitchEntry(_StitchEntry candidate, _StitchEntry best) {
  final a = candidate.segment.recordedAt;
  final b = best.segment.recordedAt;
  if (a != null && b != null && !a.isAtSameMomentAs(b)) return a.isAfter(b);
  if ((a == null) != (b == null)) return a != null;
  return candidate.index > best.index;
}

/// 같은 자리를 다시 받은 조각들 가운데 **가장 늦게 받은 것만** 남긴다. (순수 함수)
///
/// 「같은 자리」 = 스냅된 내용 시작이 같은 줄이거나, 서로 [kStitchSnapToleranceMs] 안쪽으로
/// 이어진 묶음. 가사가 없는 곡에서는 스냅할 줄이 없어 시작이 몇십 ms씩 어긋나는데, 그걸
/// 다른 자리로 보면 옛 조각의 토막이 새 조각 앞에 남아 첫 음절이 두 번 난다.
///
/// 🔴 진 조각은 **통째로** 뺀다. 조각 하나는 구간을 하나만 맡으므로, 옛 조각이 더 길어
/// 다음 줄까지 덮고 있었더라도 그 뒷부분은 쓰지 않는다 — 다시 받았다는 것은 그 자리의
/// 옛 소리를 버리겠다는 뜻이다. 몇 개를 뺐는지는 [StitchDedupe.droppedCount]로 알린다.
///
/// 정렬 기준은 스냅된 시작이다(입력 순번으로 동률을 가른다 — List.sort는 안정 정렬이
/// 아니다). 남긴 조각끼리는 허용 오차보다 멀리 떨어지므로 두 번 걸러도 결과가 같다.
StitchDedupe dedupeSameLineSegments({
  required List<StitchSegment> segments,
  List<int> lineStartsMs = const [],
}) {
  final lines = [...lineStartsMs]..sort();
  final entries = <_StitchEntry>[
    for (var i = 0; i < segments.length; i++)
      (
        index: i,
        segment: segments[i],
        startMs: snappedContentStartMs(segments[i], lines),
      ),
  ];
  entries.sort((a, b) {
    final byStart = a.startMs.compareTo(b.startMs);
    return byStart != 0 ? byStart : a.index.compareTo(b.index);
  });

  final kept = <StitchSegment>[];
  final starts = <int>[];
  var dropped = 0;
  var from = 0;
  while (from < entries.length) {
    // 바로 앞 조각과 시작이 허용 오차 안으로 이어지는 동안이 한 묶음이다.
    var to = from + 1;
    while (to < entries.length &&
        entries[to].startMs - entries[to - 1].startMs <=
            kStitchSnapToleranceMs) {
      to++;
    }
    var winner = entries[from];
    for (var k = from + 1; k < to; k++) {
      if (_isNewerStitchEntry(entries[k], winner)) winner = entries[k];
    }
    kept.add(winner.segment);
    starts.add(winner.startMs);
    dropped += to - from - 1;
    from = to;
  }
  return StitchDedupe(kept: kept, startsMs: starts, droppedCount: dropped);
}

/// 이어붙이기 안내에 붙는 「뺀 조각」 설명. 뺀 것이 없으면 빈 문자열. (순수 함수)
///
/// 조용히 빼면 「분명히 받았는데 왜 안 들리지」가 된다 — 몇 개를 왜 뺐는지 말한다.
String stitchExclusionNote({
  required int silentCount,
  required int retakeCount,
}) {
  final parts = [
    if (silentCount > 0) '무음 조각 $silentCount개 제외',
    if (retakeCount > 0) '같은 줄을 다시 받은 조각 $retakeCount개는 최신 것만 사용',
  ];
  return parts.isEmpty ? '' : ' (${parts.join(' · ')})';
}

/// 조각들의 이음새를 정한다. (순수 함수 — 테스트 대상)
///
/// 각 조각의 내용 시작점(리드인 무음을 걷어낸 자리)을 기준으로,
/// 조각 k는 [자기 내용 시작 ~ 다음 조각 내용 시작)을 맡고, 마지막 조각은
/// 자기 녹음이 끝나는 곳까지 맡는다. 조각이 다음 조각까지 닿지 못하면
/// 거기서 끝난다(억지로 늘이지 않는다 — 없는 소리를 지어내지 않는다).
///
/// 🔴 앞 조각의 꼬리는 다음 조각의 **녹음 시작이 아니라 말 시작**에서 끝난다.
/// 다음 조각은 2마디 앞에서 녹음을 걸기 때문에, 녹음 시작에서 자르면 앞 조각의
/// 마지막 줄이 통째로 날아간다.
///
/// 같은 자리를 다시 받은 조각은 먼저 [dedupeSameLineSegments]로 최신 것만 남긴다.
List<StitchSpan> computeStitchSpans({
  required List<StitchSegment> segments,
  List<int> lineStartsMs = const [],
}) {
  if (segments.isEmpty) return const [];

  final deduped = dedupeSameLineSegments(
    segments: segments,
    lineStartsMs: lineStartsMs,
  );
  final sorted = deduped.kept;
  final starts = deduped.startsMs;

  final spans = <StitchSpan>[];
  for (var i = 0; i < sorted.length; i++) {
    final seg = sorted[i];
    final start = starts[i];
    // 다음 조각의 **내용**이 시작하는 곳에서 넘긴다. 없으면 내 녹음 끝까지.
    var end = i + 1 < sorted.length ? starts[i + 1] : seg.songEndMs;
    // 내 녹음이 거기까지 닿지 않으면 닿는 데까지만.
    if (end > seg.songEndMs) end = seg.songEndMs;
    // 자기 녹음이 내용 시작에도 못 닿는 조각(길이 0·오프셋이 길이를 넘음) — 버린다.
    // 같은 자리의 중복은 위에서 이미 걸렀다.
    if (end <= start) continue;
    spans.add(StitchSpan(segment: seg, startMs: start, endMs: end));
  }
  return spans;
}

/// 이음새에 거는 크로스페이드 길이(ms). 줄 경계는 말이 끊긴 자리라
/// 짧아도 충분하고, 길면 앞뒤 숨소리를 끌어온다.
const int kStitchCrossfadeMs = 30;

/// 내용 시작점을 가사 줄 경계로 당기는 허용 오차(ms).
/// 135 BPM에서 한 박이 444ms라, 이보다 크면 옆 박으로 끌려간다.
const int kStitchSnapToleranceMs = 200;

/// 리드인이 있는 조각에서, 리드인 **뒤로 더** 건너뛰고 재기 시작하는 길이(ms).
///
/// 시작 키 소리는 저장할 때 리드인 +60ms까지만 눌러 둔다. 키를 떼는 소리와 손이
/// 돌아가는 소리는 그 뒤로도 이어져서, 거기서부터 재면 「맨 앞부터 소리가 있다」로
/// 읽힌다. 박을 타려고 앞에서 녹음을 거는 조각은 이 구간이 어차피 무음이다.
const int kStitchLeadInSkipMs = 250;

/// 이보다 조용하면 무음으로 본다(dB). silencedetect의 임계와 같은 값이어야 한다.
const double kStitchSilenceDb = -40;

/// 첫 무음이 이 시각(초) 안에서 시작해야 「맨 앞이 무음」이다.
const double kStitchLeadingSilenceSec = 0.05;

String _ff(int ms) => (ms / 1000).toStringAsFixed(3);

/// 이 조각을 어디서부터 잴지(ms). (순수 함수) 리드인이 없으면 맨 앞부터다.
int stitchScanSkipMs(int leadInMs) =>
    leadInMs > 0 ? leadInMs + kStitchLeadInSkipMs : 0;

/// 리드인 무음을 재는 ffmpeg 인자. (순수 함수)
///
/// -40dB / 0.2초 — 숨소리는 넘기고 말은 잡는 선. 헤드폰 1채널 녹음은
/// 리드인이 실제로 조용해서 이 정도면 갈린다.
///
/// [skipMs]가 0보다 크면 그만큼 건너뛰고 잰다. **입력 쪽 `-ss`**(`-i` 앞)여야 한다 —
/// 출력 쪽에 두면 필터는 파일 전체를 그대로 본다. 입력 쪽 `-ss`는 시각을 0부터
/// 다시 매기므로 나온 값은 「건너뛴 자리 기준」이다(ffmpeg 8.1.1 실측).
///
/// volumedetect를 함께 거는 이유: 끝까지 조용한 파일에서 최신 ffmpeg는 EOF에
/// `silence_end`를 찍는다. 그 값만 보면 「끝에서 소리가 시작했다」와 구분이 안 되고,
/// 저장된 길이(durationMs)는 파일 실제 길이와 0.5초까지 어긋날 수 있어 기준이 못 된다.
/// 최대 음량이 임계 아래면 한 샘플도 임계를 넘지 않았다는 뜻이라 확실하다.
List<String> buildSilenceDetectArgs(String path, {int skipMs = 0}) {
  final threshold = kStitchSilenceDb.toStringAsFixed(0);
  return [
    '-hide_banner',
    if (skipMs > 0) ...['-ss', _ff(skipMs)],
    '-i',
    path,
    '-af',
    'silencedetect=noise=${threshold}dB:d=0.2,volumedetect',
    '-f',
    'null',
    '-',
  ];
}

/// silencedetect(+volumedetect) 출력을 읽은 결과.
class SilenceScan {
  /// 재기 시작한 자리에 이미 소리가 있었는가.
  final bool soundAtStart;

  /// 앞머리 무음이 끝나고 첫 소리가 나는 지점(재기 시작한 자리 기준 ms).
  /// [soundAtStart]면 0, 끝까지 소리가 없으면 null.
  final int? firstSoundMs;

  const SilenceScan({required this.soundAtStart, required this.firstSoundMs});

  /// 잰 구간 전체가 조용했는가.
  bool get isAllSilent => !soundAtStart && firstSoundMs == null;
}

/// silencedetect(+volumedetect) 출력을 읽는다. (순수 함수)
///
/// · 최대 음량이 임계 아래 → 전체 무음(EOF의 `silence_end`에 속지 않는다).
/// · 첫 `silence_start`가 없거나 50ms보다 늦다 → 맨 앞부터 소리가 있다.
/// · 맨 앞이 무음이고 `silence_end`가 있다 → 거기가 첫 소리.
/// · 맨 앞이 무음인데 `silence_end`가 없다 → 끝까지 무음(EOF에 안 찍는 옛 ffmpeg).
SilenceScan parseSilenceScan(String output) {
  const silent = SilenceScan(soundAtStart: false, firstSoundMs: null);
  const immediate = SilenceScan(soundAtStart: true, firstSoundMs: 0);

  final volume = RegExp(
    r'max_volume:\s*(-?(?:inf|[0-9.]+))\s*dB',
  ).firstMatch(output);
  if (volume != null) {
    final raw = volume.group(1)!;
    final db = raw.contains('inf')
        ? double.negativeInfinity
        : double.parse(raw);
    if (db < kStitchSilenceDb) return silent;
  }

  final start = RegExp(r'silence_start:\s*(-?[0-9.]+)').firstMatch(output);
  if (start == null) return immediate;
  final first = double.tryParse(start.group(1)!) ?? 0;
  // 맨 앞이 무음이 아니면 리드인이 없다.
  if (first > kStitchLeadingSilenceSec) return immediate;

  final end = RegExp(r'silence_end:\s*([0-9.]+)').firstMatch(output);
  if (end == null) return silent;
  final seconds = double.tryParse(end.group(1)!) ?? 0;
  return SilenceScan(
    soundAtStart: false,
    firstSoundMs: (seconds * 1000).round(),
  );
}

/// 잰 결과를 「파일 안에서 내용이 시작하는 자리」(ms)로 바꾼다. 내용이 없으면 null.
/// (순수 함수)
///
/// ① [soundAtSkip] — 건너뛴 자리에 이미 소리가 있다. 누르자마자 부른 조각이다.
///    정확히 어디서부터인지는 알 수 없지만 리드인(키를 누르기 **전**)은 내용이
///    아니므로, 키를 누른 자리([leadInMs])를 내용 시작으로 본다.
/// ② 건너뛴 뒤 무음이 이어지다 소리가 났다 → [skipMs] + [detectedAfterSkipMs].
/// ③ 끝까지 조용했다 → null. 이 조각에는 이을 내용이 없다.
int? contentOffsetFromDetection({
  required int leadInMs,
  required int skipMs,
  required int? detectedAfterSkipMs,
  required bool soundAtSkip,
}) {
  if (soundAtSkip) return leadInMs;
  if (detectedAfterSkipMs != null) return skipMs + detectedAfterSkipMs;
  return null;
}

/// 조각들을 곡 타임라인 위에 놓아 한 벌의 보컬 wav를 만드는 인자.
/// (순수 함수 — 프로세스를 띄우지 않는다)
List<String> buildStitchArgs({
  required List<StitchSpan> spans,
  required String outputPath,
  int crossfadeMs = kStitchCrossfadeMs,
}) {
  final args = <String>['-y'];
  for (final span in spans) {
    args
      ..add('-i')
      ..add(span.segment.vocalPath);
  }

  final chains = <String>[];
  for (var i = 0; i < spans.length; i++) {
    final span = spans[i];
    // 조각이 시작하기 전의 소리는 없다 — 구간이 앞으로 삐져나왔으면 조각 시작에서
    // 막는다. 음수 오프셋을 그대로 넘기면 조각이 그만큼 일찍 놓인다.
    final startMs = span.startMs < span.segment.songPositionMs
        ? span.segment.songPositionMs
        : span.startMs;
    final lengthMs = span.endMs - startMs;
    // 곡 시각 → 파일 시각.
    final fileStart = startMs - span.segment.songPositionMs;
    final fileEnd = span.endMs - span.segment.songPositionMs;
    // 크로스페이드가 구간보다 길면 안 된다.
    final fade = crossfadeMs * 2 >= lengthMs ? (lengthMs ~/ 4) : crossfadeMs;
    final fadeOutAt = lengthMs - fade;
    chains.add(
      '[$i:a]atrim=start=${_ff(fileStart)}:end=${_ff(fileEnd)},'
      'asetpts=PTS-STARTPTS,'
      'afade=t=in:st=0:d=${_ff(fade)},'
      'afade=t=out:st=${_ff(fadeOutAt)}:d=${_ff(fade)},'
      'adelay=$startMs:all=1[s$i]',
    );
  }
  final mixIn = [for (var i = 0; i < spans.length; i++) '[s$i]'].join();
  // normalize=0 — 조각 수에 따라 음량이 줄면 안 된다(겹치는 곳만 합쳐진다).
  chains.add(
    '$mixIn'
    'amix=inputs=${spans.length}:normalize=0[out]',
  );

  args
    ..add('-filter_complex')
    ..add(chains.join(';'))
    ..add('-map')
    ..add('[out]')
    ..add('-ac')
    ..add('1')
    ..add('-ar')
    ..add('48000')
    ..add('-c:a')
    ..add('pcm_s16le')
    ..add(outputPath);
  return args;
}

class TakeStitchService {
  final ProcessRunner _runner;
  final ExternalToolLocator _locator;

  TakeStitchService({
    ProcessRunner runner = const SystemProcessRunner(),
    ExternalToolLocator? locator,
  }) : _runner = runner,
       _locator = locator ?? ExternalToolLocator(runner: runner);

  /// 조각 안에서 내용이 시작하는 자리(ms)를 잰다. 끝까지 조용하면 null.
  ///
  /// 못 재면(ffmpeg 없음·파일 못 읽음) 리드인 끝으로 둔다 — 판정을 못 했다고
  /// 조각을 버리지는 않는다.
  Future<int?> detectContentOffsetMs(StitchSegment segment) async {
    final skipMs = stitchScanSkipMs(segment.leadInMs);
    // 건너뛸 자리가 조각 밖이면 잴 것이 없다(0.5초 남짓한 조각) — 키를 누른
    // 자리부터 내용으로 본다.
    if (skipMs >= segment.durationMs) {
      return segment.leadInMs.clamp(0, segment.durationMs);
    }

    final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);
    if (!ffmpeg.found) return segment.leadInMs;
    // 무음 정보는 stderr로 나오고 종료 코드도 0이 아닐 수 있다(정상).
    final job = _runner.start(
      ffmpeg.path!,
      buildSilenceDetectArgs(segment.vocalPath, skipMs: skipMs),
    );
    final lines = <String>[];
    final sub = job.lines.listen(lines.add);
    await job.exitCode;
    await sub.cancel();

    final scan = parseSilenceScan(lines.join('\n'));
    return contentOffsetFromDetection(
      leadInMs: segment.leadInMs,
      skipMs: skipMs,
      detectedAfterSkipMs: scan.firstSoundMs,
      soundAtSkip: scan.soundAtStart,
    );
  }

  /// 조각들의 리드인을 재서 내용 시작점이 채워진 사본을 돌려준다.
  ///
  /// 🔴 **소리가 없는 조각은 뺀다.** 무음 조각이 끼면 그 조각의 자리에서 앞 조각의
  /// 꼬리가 잘리고, 정작 그 자리에는 아무 소리도 안 나 노래에 구멍이 난다.
  /// 녹음할 때 잰 레벨이 남아 있으면 그걸로 가리고(디지털 무음), 없으면 파일
  /// 전체가 조용한지를 직접 잰다. 돌려준 목록이 받은 것보다 짧으면 그만큼 뺀 것이다.
  Future<List<StitchSegment>> withDetectedOffsets(
    List<StitchSegment> segments,
  ) async {
    final out = <StitchSegment>[];
    for (final seg in segments) {
      if (seg.peakDbfs != null && isSilentTake(seg.peakDbfs)) continue;
      final offset = await detectContentOffsetMs(seg);
      if (offset == null) continue;
      out.add(seg.withContentOffset(offset));
    }
    return out;
  }

  /// 조각들을 이어 한 벌의 보컬 wav를 만든다.
  Future<TakeMixResult> stitchVocals({
    required List<StitchSegment> segments,
    required String outputPath,
    List<int> lineStartsMs = const [],
  }) async {
    if (segments.length < 2) {
      return const TakeMixResult.failure('이어붙이려면 조각이 둘 이상 필요합니다.');
    }
    final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);
    if (!ffmpeg.found) {
      return const TakeMixResult.failure('이어붙이려면 ffmpeg가 필요합니다.');
    }
    for (final seg in segments) {
      if (!await File(seg.vocalPath).exists()) {
        return const TakeMixResult.failure('조각 파일을 찾을 수 없습니다.');
      }
    }

    final spans = computeStitchSpans(
      segments: segments,
      lineStartsMs: lineStartsMs,
    );
    if (spans.length < 2) {
      return const TakeMixResult.failure(
        '조각들이 서로 겹쳐서 이을 구간이 없습니다. 녹음 위치를 확인해 주세요.',
      );
    }

    final tempPath = '$outputPath.tmp.wav';
    final result = await _runner.run(
      ffmpeg.path!,
      buildStitchArgs(spans: spans, outputPath: tempPath),
    );
    if (!result.ok || !await File(tempPath).exists()) {
      await _deleteIfExists(tempPath);
      return const TakeMixResult.failure('조각 이어붙이기에 실패했습니다.');
    }
    try {
      await File(tempPath).rename(outputPath);
    } catch (_) {
      await _deleteIfExists(tempPath);
      return const TakeMixResult.failure('이어붙인 보컬을 저장하지 못했습니다.');
    }
    return TakeMixResult.success(outputPath);
  }

  Future<void> _deleteIfExists(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
