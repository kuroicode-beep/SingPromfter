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
import 'dart:io';

import 'process/external_tool_locator.dart';
import 'process/process_runner.dart';
import 'take_mix_service.dart';

/// 이어붙일 조각 하나. (경로 + 곡 위 좌표)
class StitchSegment {
  final String vocalPath;

  /// 녹음을 시작한 순간의 곡 재생 위치(ms).
  final int songPositionMs;

  /// 이 조각의 길이(ms).
  final int durationMs;

  /// 파일 안에서 **소리가 시작하는 지점**(ms). 리드인 무음의 길이다.
  /// 0이면 녹음을 걸자마자 뱉었다는 뜻.
  final int contentOffsetMs;

  const StitchSegment({
    required this.vocalPath,
    required this.songPositionMs,
    required this.durationMs,
    this.contentOffsetMs = 0,
  });

  /// 곡 타임라인 기준, 이 조각의 내용이 시작하는 시각(ms).
  int get contentStartMs => songPositionMs + contentOffsetMs;

  /// 이 조각이 덮는 곡 구간의 끝(ms).
  int get songEndMs => songPositionMs + durationMs;
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

/// 조각들의 이음새를 정한다. (순수 함수 — 테스트 대상)
///
/// 각 조각의 내용 시작점(리드인 무음을 걷어낸 자리)을 기준으로,
/// 조각 k는 [자기 내용 시작 ~ 다음 조각 내용 시작)을 맡고, 마지막 조각은
/// 자기 녹음이 끝나는 곳까지 맡는다. 조각이 다음 조각까지 닿지 못하면
/// 거기서 끝난다(억지로 늘이지 않는다 — 없는 소리를 지어내지 않는다).
List<StitchSpan> computeStitchSpans({
  required List<StitchSegment> segments,
  List<int> lineStartsMs = const [],
}) {
  if (segments.isEmpty) return const [];

  final sorted = [...segments]
    ..sort((a, b) => a.contentStartMs.compareTo(b.contentStartMs));
  final lines = [...lineStartsMs]..sort();

  final starts = [
    for (final s in sorted) snapToLineStart(s.contentStartMs, lines),
  ];

  final spans = <StitchSpan>[];
  for (var i = 0; i < sorted.length; i++) {
    final seg = sorted[i];
    final start = starts[i];
    // 다음 조각이 시작하는 곳에서 넘긴다. 없으면 내 녹음 끝까지.
    var end = i + 1 < sorted.length ? starts[i + 1] : seg.songEndMs;
    // 내 녹음이 거기까지 닿지 않으면 닿는 데까지만.
    if (end > seg.songEndMs) end = seg.songEndMs;
    if (end <= start) continue; // 다음 조각에 완전히 덮였다 — 버린다.
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

String _ff(int ms) => (ms / 1000).toStringAsFixed(3);

/// 리드인 무음을 재는 ffmpeg 인자. (순수 함수)
///
/// -40dB / 0.2초 — 숨소리는 넘기고 말은 잡는 선. 헤드폰 1채널 녹음은
/// 리드인이 실제로 조용해서 이 정도면 갈린다.
List<String> buildSilenceDetectArgs(String path) {
  return [
    '-hide_banner',
    '-i',
    path,
    '-af',
    'silencedetect=noise=-40dB:d=0.2',
    '-f',
    'null',
    '-',
  ];
}

/// silencedetect 출력에서 **소리가 처음 나는 지점**(ms)을 뽑는다. (순수 함수)
///
/// 파일 맨 앞이 무음이면 `silence_start: 0` 다음의 `silence_end`가 첫 소리다.
/// 맨 앞부터 소리가 있으면 리드인이 없다는 뜻이라 0.
int parseFirstSoundMs(String output) {
  final starts = RegExp(r'silence_start:\s*(-?[0-9.]+)').allMatches(output);
  if (starts.isEmpty) return 0;
  final first = double.tryParse(starts.first.group(1)!) ?? 0;
  // 맨 앞이 무음이 아니면 리드인이 없다.
  if (first > 0.05) return 0;
  final end = RegExp(r'silence_end:\s*([0-9.]+)').firstMatch(output);
  if (end == null) return 0;
  final seconds = double.tryParse(end.group(1)!) ?? 0;
  return (seconds * 1000).round();
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
    // 곡 시각 → 파일 시각.
    final fileStart = span.startMs - span.segment.songPositionMs;
    final fileEnd = span.endMs - span.segment.songPositionMs;
    // 크로스페이드가 구간보다 길면 안 된다.
    final fade = crossfadeMs * 2 >= span.lengthMs
        ? (span.lengthMs ~/ 4)
        : crossfadeMs;
    final fadeOutAt = span.lengthMs - fade;
    chains.add(
      '[$i:a]atrim=start=${_ff(fileStart)}:end=${_ff(fileEnd)},'
      'asetpts=PTS-STARTPTS,'
      'afade=t=in:st=0:d=${_ff(fade)},'
      'afade=t=out:st=${_ff(fadeOutAt)}:d=${_ff(fade)},'
      'adelay=${span.startMs}:all=1[s$i]',
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

  /// 조각의 리드인 무음 길이(ms)를 잰다. 못 재면 0(리드인 없음)으로 둔다 —
  /// 판정을 못 했다고 조각을 버리지는 않는다.
  Future<int> detectContentOffsetMs(String path) async {
    final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);
    if (!ffmpeg.found) return 0;
    // 무음 정보는 stderr로 나오고 종료 코드도 0이 아닐 수 있다(정상).
    final job = _runner.start(ffmpeg.path!, buildSilenceDetectArgs(path));
    final lines = <String>[];
    final sub = job.lines.listen(lines.add);
    await job.exitCode;
    await sub.cancel();
    return parseFirstSoundMs(lines.join('\n'));
  }

  /// 조각들의 리드인을 재서 내용 시작점이 채워진 사본을 돌려준다.
  Future<List<StitchSegment>> withDetectedOffsets(
    List<StitchSegment> segments,
  ) async {
    final out = <StitchSegment>[];
    for (final seg in segments) {
      final offset = await detectContentOffsetMs(seg.vocalPath);
      out.add(
        StitchSegment(
          vocalPath: seg.vocalPath,
          songPositionMs: seg.songPositionMs,
          durationMs: seg.durationMs,
          contentOffsetMs: offset,
        ),
      );
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
