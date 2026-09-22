// file: lib/controllers/capture_session.dart
//
// 녹음 고정 — 상시 캡처 세션의 **순수 부품**. 프로세스도 위젯도 없다(전부 테스트 대상).
//
// 왜 필요한가: 테이크마다 ffmpeg를 띄우면 dshow 그래프를 짓는 0.44~0.53초 동안
// 마이크가 물리적으로 닫혀 있어, 스페이스 직후의 첫 음절을 구할 방법이 없다.
// 그래서 고정을 켜는 순간 ffmpeg 하나를 띄워 raw PCM 세션 파일에 계속 받아 두고,
// 스페이스는 벽시계로 「표시」만 찍는다. 저장할 때 세션 파일에서 구간을 잘라 낸다.
//
// 이 파일이 맡는 것: 세션 인자, 벽시계↔파일시각 환산(CaptureClock), 잘라낼 구간
// 계산(computeTakeSlice), WAV 쓰기와 가장자리 가공, 복구용 사이드카 모델.
// 설계: docs/architecture/설계_20260922_녹음고정_상시캡처세션_유미.md (3.1·3.2·3.4·3.6)
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../utils/recording_latency.dart';
import 'recording_controller.dart';

/// 세션 상한(초). 앱이 죽어 ffmpeg가 고아가 돼도 45분·259MB에서 스스로 끝난다.
/// 이 PC는 영상 파이프라인 ffmpeg가 상시 돌아서 PID로 죽여 정리할 수가 없다.
const int kSessionMaxSeconds = 2700;

/// 세션 파일의 표본화 주파수. raw s16le 모노라 헤더가 없다.
const int kSessionSampleRate = 48000;

/// 세션 파일 1ms의 바이트 수(48샘플 × 2바이트) — 바이트 오프셋 = ms × 96.
const int kSessionBytesPerMs = 96;

/// 스페이스를 누르기 전부터 담는 길이(ms). 「저장 과정에서 리드인」.
const int kArmedLeadInMs = 300;

/// 끝에서 잘라 내는 길이(ms) — 정지 키를 누르는 소리가 담기는 구간.
const int kStopClickTrimMs = 60;

/// 끝 페이드아웃(ms). 잘린 자리에서 파형이 끊겨 나는 틱 소리를 없앤다.
const int kTailFadeMs = 20;

/// 시작 키 클릭을 지우는 구간 — 마크 앞 40ms부터 뒤 60ms까지.
const int kStartClickGuardBeforeMs = 40;
const int kStartClickGuardAfterMs = 60;

/// 뮤트 구간 양끝의 램프(ms). 계단으로 끊으면 그 자체가 클릭이 된다.
const int kGuardRampMs = 5;

/// `IMFMediaEngine::Play()` → 클럭 첫 전진까지의 지연(실측 10~23ms의 중앙).
const int kPlaybackStartLatencyMs = 15;

/// 이만큼 표본이 쌓여야 시계를 믿는다. 그 전의 마크는 거절한다.
const int kClockLockFrames = 5;

/// 기준점 최소값 필터의 창 — 1초 버킷 × 10개.
const int kClockBucketUs = 1000000;
const int kClockBucketCount = 10;

/// pts 간격이 공칭보다 이만큼 넘게 벌어지면 드롭으로 본다.
const int kClockGapSlackUs = 20000;

/// 세션 **첫 간격**만의 드롭 문턱. dshow는 첫 버퍼 뒤에서 pts를 한 번 건너뛰고
/// (실측 RØDE 26~36ms, Razer 17~23ms, FLOW 8 0~4ms) 그만큼의 소리는 파일에 없다 —
/// 출력 파일이 정확히 그만큼 짧았다. 20ms 문턱으로는 Razer의 17~20ms가 구멍으로
/// 안 잡혀 세션 내내 파일시각이 그만큼 뒤로 밀린다. pts 흔들림(±2ms)보다만 크게 둔다.
const int kClockStartGapSlackUs = 5000;

/// 개루프 좌표(P0 − L)와 실측 좌표가 이보다 어긋나면 「좌표 의심」으로 알린다.
const int kTimelineSuspectMs = 40;

/// 끝 바이트가 디스크에 닿기를 기다리는 간격·상한(ms).
/// ffmpeg는 50ms씩 쓰고 실시간보다 0~70ms 늦다(실측) — 500ms면 넉넉하다.
const int kTakeWaitPollMs = 10;
const int kTakeWaitCapMs = 500;

/// 세션 멈춤 판정 — 레벨 줄 공백(ms)과 파일 크기 정체 횟수.
const int kStallRmsGapMs = 600;
const int kStallStagnantTicks = 2;

/// 세션 id로 PCM·사이드카 파일 이름을 만든다. (순수 함수)
String sessionPcmFileName(String sessionId) => '$sessionId.pcm';

/// 세션 id의 사이드카(JSON) 파일 이름. (순수 함수)
String sessionSidecarFileName(String sessionId) => '$sessionId.json';

/// 세션 id의 소유 잠금 파일 이름. (순수 함수)
///
/// 세션을 연 앱이 살아 있는 동안 이 파일을 배타 잠금으로 쥔다. 앱이 죽으면 OS가
/// 잠금을 푼다 — 부팅 복구가 「남의 살아 있는 세션」과 「내 크래시가 남긴 고아」를
/// 가르는 근거다(파일이 자라는지로는 못 가른다 — 고아 ffmpeg도 계속 쓴다).
String sessionLockFileName(String sessionId) => '$sessionId.lock';

/// 열린 조각이 있는 동안 사이드카에 생존 표시를 남기는 간격(ms).
const int kSidecarHeartbeatMs = 2000;

/// 생존 표시 뒤로 더 살리는 여유(ms) — 표시를 쓰는 데 걸린 시간과 쓰기 지연 몫.
const int kSidecarAliveSlackMs = 500;

/// 상시 캡처 세션의 ffmpeg 인자. (순수 함수 — 프로세스를 띄우지 않는다)
///
/// 테이크 녹음([buildRecordArgs])과 다른 점:
/// - `-progress`가 없다. 515ms 간격이라 쓸모가 없고 줄만 늘린다.
/// - `-f s16le` raw PCM. 헤더가 없어 **쓰는 중에도** 아무 구간이나 잘라 읽을 수 있다.
/// - `-flush_packets 1`. 없으면 muxer 버퍼에 쌓여 파일이 실시간으로 안 자란다.
/// - `-t`. 앱이 죽어도 고아 프로세스가 스스로 끝난다([kSessionMaxSeconds]).
/// - 입력이 하나다. 고정 중에는 반주 채널을 열지 않는다(보컬 1채널).
List<String> buildSessionCaptureArgs({
  required String deviceName,
  required String outputPath,
  double gain = 1.0,
}) {
  return [
    '-hide_banner',
    '-f', 'dshow',
    '-audio_buffer_size', '$kDshowAudioBufferMs',
    '-i', 'audio=$deviceName',
    '-ac', '1',
    '-ar', '$kSessionSampleRate',
    // 필터 문자열은 테이크 녹음과 **같은 함수**를 쓴다(복사 금지).
    '-af', captureFilterChain(gain),
    '-nostats',
    '-flush_packets', '1',
    '-t', '$kSessionMaxSeconds',
    '-f', 's16le',
    '-y',
    outputPath,
  ];
}

final RegExp _frameLinePattern = RegExp(
  r'^frame:[0-9]+ +pts:(-?[0-9]+) +pts_time:(-?[0-9.]+(?:[eE][-+]?[0-9]+)?)',
);

// pts의 시간축 분모로 나올 수 있는 값(오디오 필터의 time_base = 1/표본화 주파수).
const List<int> _kPtsTimebases = [
  8000,
  11025,
  16000,
  22050,
  32000,
  44100,
  48000,
  88200,
  96000,
  176400,
  192000,
];

/// ametadata 프레임 머리줄에서 프레임 시작 시각을 **µs**로 읽는다. (순수 함수)
/// 입력 예: `frame:3    pts:3072    pts_time:0.0696599`
///
/// ms로 읽는 [parseAmetadataFramePtsMs]로는 시계를 못 만든다 — 반올림 0.5ms가
/// 최소값 필터에 그대로 실린다.
///
/// `pts_time`만 믿지 않는 이유: ffmpeg 7.1 이전은 이 값을 유효숫자 6자리(`%.6g`)로
/// 찍어서 100초를 넘기면 해상도가 ms 단위로 무너진다. 그래서 정수 `pts`와의
/// 비로 시간축(1/N)을 알아내고, 알아냈으면 `pts ÷ N`으로 정확히 계산한다.
int? parseAmetadataFramePtsUs(String line) {
  final match = _frameLinePattern.firstMatch(line.trim());
  if (match == null) return null;
  final pts = int.tryParse(match.group(1)!);
  final seconds = double.tryParse(match.group(2)!);
  if (seconds == null || !seconds.isFinite) return null;
  if (pts != null && pts > 0 && seconds > 0) {
    final ratio = pts / seconds;
    for (final base in _kPtsTimebases) {
      if ((ratio - base).abs() <= base * 0.001) {
        return (pts * 1000000 / base).round();
      }
    }
  }
  return (seconds * 1000000).round();
}

/// µs를 ms로 반올림한다. (순수 함수)
int usToMs(int us) => (us / 1000).round();

/// 벽시계(µs) ↔ 세션 파일시각 환산기. (프로세스와 무관 — 테스트 대상)
///
/// 재료는 ametadata 프레임 머리줄의 **도착 시각**과 **pts**뿐이다.
/// - 프레임 k의 줄이 도착했다면 프레임 k는 이미 다 담겼다. 그 끝 시각은 **다음 줄의
///   pts**로 확정한다(프레임 길이를 가정하지 않는다).
/// - `offset = (앞 줄 도착) − (다음 줄 pts)`. 줄의 도착은 늦어질 수만 있으니
///   (파이프·이벤트 루프) 값은 클 수만 있다 — **최소값**이 참값에 가장 가깝다.
///   여러 줄이 한꺼번에 몰려 와도(같은 도착 시각) 최소값 아래로는 못 내려간다.
/// - 전역 최소가 아니라 **1초 버킷 × 10개 창**의 최소다. USB 마이크 발진기와
///   QPC는 서로 흐르기 때문에(실측 45초에 0.7ms) 옛 표본을 붙들면 안 된다.
/// - raw PCM은 pts 없이 이어 쓰인다. pts가 공칭+20ms 넘게 건너뛰면 그만큼의
///   소리가 **파일에는 없다** — 그 구멍을 시간표로 쌓아 두고 환산 때 뺀다.
///   세션의 **첫 간격**만은 문턱이 5ms다([kClockStartGapSlackUs]) — dshow의 시작
///   점프는 장치마다 17~36ms라 20ms 문턱에 걸쳐 있고, 놓치면 세션 내내 어긋난다.
///
/// 파일시각 `F(W) = (W − t_ref) − gap(W)`. 마크는 벽시계로만 들고 있다가 **저장할
/// 때** 환산한다 — 그때는 마크 뒤의 표본까지 쌓여 기준점이 수렴해 있다.
class CaptureClock {
  CaptureClock({
    this.bucketUs = kClockBucketUs,
    this.bucketCount = kClockBucketCount,
    this.lockFrames = kClockLockFrames,
  });

  final int bucketUs;
  final int bucketCount;
  final int lockFrames;

  // 공칭 프레임 길이를 정하기 전에 모아 두는 줄 수(간격 3개).
  // 첫 간격부터 드롭일 수 있는데, 공칭을 모르면 그걸 가릴 수 없다. 걸친 표본이
  // 그대로 들어가면 최소값 필터가 **그 틀린 값**을 골라 버린다.
  static const int _warmupFrames = 4;

  // 공칭 길이는 최근 간격의 중앙값이다. 최소값은 짧은 프레임 하나에, 평균은
  // 드롭 하나에 무너진다.
  static const int _stepHistory = 15;

  List<({int arrivalUs, int ptsUs})>? _warmup = [];
  ({int arrivalUs, int ptsUs})? _prev;
  final List<int> _recentSteps = [];
  int? _nominalUs;
  final Map<int, int> _bucketMin = {};
  int? _latestBucket;
  int _samples = 0;
  final List<({int startPtsUs, int lengthUs})> _holes = [];
  int _totalGapUs = 0;

  // 아직 첫 간격을 보지 않았는가 — 첫 간격만 시작 점프 문턱으로 판정한다.
  bool _firstStep = true;

  /// 기준점 표본 수.
  int get sampleCount => _samples;

  /// 시계를 믿어도 되는가. 거짓이면 마크를 받지 않는다.
  bool get isLocked => _samples >= lockFrames;

  /// 공칭 프레임 길이(µs). 아직 모르면 null.
  int? get nominalFrameUs => _nominalUs;

  /// 지금까지 쌓인 구멍의 합(µs).
  int get totalGapUs => _totalGapUs;

  /// 줄로 확인된 파일 길이(µs) — 마지막 줄의 pts까지는 확실히 담겼다.
  int get confirmedFileUs {
    final prev = _prev;
    if (prev == null) return 0;
    final file = prev.ptsUs - _totalGapUs;
    return file < 0 ? 0 : file;
  }

  /// **지금**의 기준점(파일 t=0의 벽시계, µs) — 최근 [bucketCount]개 버킷의 최소.
  int? get tRefUs {
    final latest = _latestBucket;
    if (latest == null) return null;
    return _minAround(latest, back: bucketCount - 1, forward: 0);
  }

  /// 프레임 머리줄 하나. [arrivalUs]는 줄이 **도착한 순간**의 단조 시계 값이다.
  void addFrame({required int arrivalUs, required int ptsUs}) {
    final warmup = _warmup;
    if (warmup == null) {
      _process(arrivalUs, ptsUs);
      return;
    }
    // pts가 제자리거나 뒤로 간 줄로는 간격을 잴 수 없다.
    if (warmup.isNotEmpty && ptsUs <= warmup.last.ptsUs) return;
    warmup.add((arrivalUs: arrivalUs, ptsUs: ptsUs));
    if (warmup.length < _warmupFrames) return;
    _nominalUs = _median([
      for (var i = 1; i < warmup.length; i++)
        warmup[i].ptsUs - warmup[i - 1].ptsUs,
    ]);
    _warmup = null;
    for (final frame in warmup) {
      _process(frame.arrivalUs, frame.ptsUs);
    }
  }

  /// 줄 하나를 표본·구멍으로 반영한다.
  void _process(int arrivalUs, int ptsUs) {
    final prev = _prev;
    if (prev != null && ptsUs <= prev.ptsUs) return;
    _prev = (arrivalUs: arrivalUs, ptsUs: ptsUs);
    if (prev == null) return;

    final step = ptsUs - prev.ptsUs;
    // 판정은 이 간격을 넣기 **전**의 공칭으로 한다.
    final nominal = _nominalUs ?? step;
    _pushStep(step);
    // 첫 간격의 초과분은 크기가 작아도 「파일에 없는 소리」다(실측 — 파일 결손과
    // 1~3ms 안에서 일치). 그 뒤의 간격은 흔들림일 수 있어 넉넉한 문턱을 쓴다.
    final slack = _firstStep ? kClockStartGapSlackUs : kClockGapSlackUs;
    _firstStep = false;
    if (step > nominal + slack) {
      final gap = step - nominal;
      // 앞 프레임은 공칭 길이만큼은 담겼다 — 구멍은 그 뒤부터다.
      _holes.add((startPtsUs: prev.ptsUs + nominal, lengthUs: gap));
      _totalGapUs += gap;
      // 구멍에 걸친 표본은 버린다. 다음 pts가 구멍만큼 커서 offset이 그만큼
      // **작게** 나오는데, 최소값 필터는 작은 값을 고른다.
      return;
    }

    final offset = prev.arrivalUs - ptsUs;
    final bucket = _bucketOf(prev.arrivalUs);
    final known = _bucketMin[bucket];
    if (known == null || offset < known) _bucketMin[bucket] = offset;
    final latest = _latestBucket;
    if (latest == null || bucket > latest) _latestBucket = bucket;
    _samples++;
  }

  /// 간격 하나를 이력에 넣고 공칭(중앙값)을 갱신한다.
  ///
  /// 드롭으로 판정한 간격도 넣는다. 장치가 프레임 길이를 **정말로** 바꿨을 때
  /// 공칭이 따라가지 못하면 매 프레임을 드롭으로 세는 상태에 갇힌다.
  void _pushStep(int step) {
    _recentSteps.add(step);
    if (_recentSteps.length > _stepHistory) _recentSteps.removeAt(0);
    if (_recentSteps.length >= _warmupFrames - 1) {
      _nominalUs = _median(_recentSteps);
    }
  }

  /// 중앙값. 빈 목록은 부르지 않는다.
  static int _median(List<int> values) {
    final sorted = [...values]..sort();
    return sorted[sorted.length ~/ 2];
  }

  /// 벽시계가 속한 버킷 번호(음수에서도 내림).
  int _bucketOf(int wallUs) => (wallUs / bucketUs).floor();

  /// [center] 버킷 앞뒤 범위의 최소 offset. 범위가 비었으면 null.
  int? _minAround(int center, {required int back, required int forward}) {
    int? best;
    for (var b = center - back; b <= center + forward; b++) {
      final value = _bucketMin[b];
      if (value != null && (best == null || value < best)) best = value;
    }
    return best;
  }

  /// 벽시계 [wallUs] **무렵**의 기준점(µs).
  ///
  /// 그 시각 앞뒤 창의 최소값을 쓴다. 저장 시점의 기준점 하나로 옛 마크까지
  /// 환산하면 테이크 길이 × 드리프트만큼 어긋난다(50ppm × 4분 = 12ms).
  /// 마크 뒤의 버킷도 보므로, 잠긴 직후에 찍은 마크도 수렴된 값으로 환산된다.
  int? tRefUsAt(int wallUs) {
    if (_bucketMin.isEmpty) return null;
    final center = _bucketOf(wallUs);
    final near = _minAround(
      center,
      back: bucketCount - 1,
      forward: bucketCount - 1,
    );
    if (near != null) return near;
    // 그 무렵에 줄이 없었다(세션이 멈췄던 구간) — 가장 가까운 버킷을 쓴다.
    int? nearest;
    for (final bucket in _bucketMin.keys) {
      if (nearest == null ||
          (bucket - center).abs() < (nearest - center).abs()) {
        nearest = bucket;
      }
    }
    return nearest == null ? null : _bucketMin[nearest];
  }

  /// pts 좌표 [ptsUs]까지 쌓인 구멍의 합. 구멍 안이면 들어간 만큼만 센다.
  int _gapUsUpToPts(int ptsUs) {
    var total = 0;
    for (final hole in _holes) {
      final into = ptsUs - hole.startPtsUs;
      if (into <= 0) continue;
      total += into < hole.lengthUs ? into : hole.lengthUs;
    }
    return total;
  }

  /// 벽시계 [wallUs]**까지** 쌓인 구멍의 합(µs). 그 뒤에 생긴 구멍은 세지 않는다 —
  /// 드롭 전에 찍은 마크의 파일 위치는 드롭과 무관하기 때문이다.
  int gapUsUpTo(int wallUs) {
    final ref = tRefUsAt(wallUs);
    if (ref == null) return 0;
    return _gapUsUpToPts(wallUs - ref);
  }

  /// 세션 파일 구간 ([fromFileUs], [toFileUs]) **안쪽**에 있는 구멍들 — 파일 오프셋(µs)과
  /// 길이(µs). 구멍은 파일에 없는 소리라, 조각을 자를 때 그 자리에 무음을 끼워야
  /// 구멍 뒤의 소리가 제 곡 좌표에 놓인다(마크 환산만 구멍을 알면 내용은 어긋난다).
  List<({int fileUs, int lengthUs})> holesInFileRange(
    int fromFileUs,
    int toFileUs,
  ) {
    final out = <({int fileUs, int lengthUs})>[];
    // 구멍은 시간순으로 쌓인다 — 앞선 구멍의 합을 빼면 파일 오프셋이다.
    var before = 0;
    for (final hole in _holes) {
      final fileUs = hole.startPtsUs - before;
      before += hole.lengthUs;
      if (fileUs > fromFileUs && fileUs < toFileUs) {
        out.add((fileUs: fileUs, lengthUs: hole.lengthUs));
      }
    }
    return out;
  }

  /// 벽시계 [wallUs]에 마이크로 들어온 소리가 세션 파일의 어디에 있는지(µs).
  /// 아직 잠기지 않았으면 null.
  int? fileTimeUsAt(int wallUs) {
    if (!isLocked) return null;
    final ref = tRefUsAt(wallUs);
    if (ref == null) return null;
    final pts = wallUs - ref;
    final file = pts - _gapUsUpToPts(pts);
    return file < 0 ? 0 : file;
  }
}

/// 세션 파일에서 잘라 낼 구간과 그 조각의 좌표.
///
/// `slice*`는 **세션 파일** 기준 ms, `guard*`는 **조각** 기준 ms(조각 t=0 = 0)다.
class TakeSlicePlan {
  const TakeSlicePlan({
    required this.sliceStartMs,
    required this.sliceEndMs,
    required this.leadInMs,
    required this.songPositionMs,
    required this.guardFromMs,
    required this.guardToMs,
  });

  final int sliceStartMs;
  final int sliceEndMs;

  /// 조각 머리의 리드인(ms) — 마크(스페이스)보다 앞서 담긴 길이.
  final int leadInMs;

  /// 조각 t=0의 곡 좌표(ms).
  final int songPositionMs;

  /// 시작 키 클릭을 지우는 구간(조각 기준 ms).
  final int guardFromMs;
  final int guardToMs;

  int get durationMs => sliceEndMs - sliceStartMs;

  /// 리드인을 뺀 본 내용의 길이(ms).
  int get contentMs => durationMs - leadInMs;

  int get startByte => sliceStartMs * kSessionBytesPerMs;
  int get endByte => sliceEndMs * kSessionBytesPerMs;

  @override
  String toString() =>
      'TakeSlicePlan(file $sliceStartMs~$sliceEndMs, leadIn $leadInMs, '
      'song $songPositionMs, guard $guardFromMs~$guardToMs)';
}

/// 마크 한 쌍으로 잘라 낼 구간을 정한다. (순수 함수 — 테스트 대상)
///
/// [startFileMs]·[endFileMs]는 마크의 세션 파일시각, [songPosAtStartMs]는 시작
/// 마크를 찍은 순간의 재생 위치(P0)다. [playbackAlreadyRunning]이면 재생 시작
/// 지연([kPlaybackStartLatencyMs])을 빼지 않는다 — 이미 흐르던 위치를 읽은 것이다.
/// [fileLengthMs]는 세션 파일이 **더 자라지 않을 때만** 준다(세션 사망·부팅 복구).
/// 살아 있는 세션은 null로 두고 [writeTakeFromSession]이 끝 바이트를 기다리게 한다.
/// [latencyCompensationMs]는 마크를 찍을 때 굳힌 「녹음 지연 보정」 C(−300…+300ms)다.
///
/// 좌표 식: 시작 마크가 파일 F에 있고 재생은 그 L ms 뒤에 P0에서 흐르기 시작하며,
/// 목소리는 거기서 다시 C만큼 늦게 파일에 닿는다. 그래서 조각 t=0(= F − leadIn)의
/// 곡 좌표는 `P0 − L − C − leadIn`이다(부호는 [compensateSongPositionMs] 한 곳).
/// 불변식 `songPositionMs + leadInMs + L + C == P0`.
///
/// 🔴 곡 앞머리(P0 < leadIn + L + C)에서는 좌표를 0으로 눕히지 않고 **리드인을 줄인다.**
/// 눕히면 조각 안의 소리가 그만큼 뒤로 밀린 좌표로 저장된다 — 곡 처음에서
/// 스페이스를 누르는 가장 흔한 경우에 이어붙이기가 315ms 어긋난다.
/// P0 < L + C이면 모자란 만큼 조각 머리를 마크 뒤에서 시작해 t=0을 곡 0에 맞춘다 —
/// 보정값이 커져도 같은 방식이라 좌표 계약(파일 t ↔ 곡 songPositionMs + t)이 안 깨진다.
///
/// 마크 구간이 [kMinimumTakeDuration]보다 짧으면 null(저장하지 않는다).
TakeSlicePlan? computeTakeSlice({
  required int startFileMs,
  required int endFileMs,
  required int songPosAtStartMs,
  required bool playbackAlreadyRunning,
  int? fileLengthMs,
  int latencyCompensationMs = 0,
}) {
  final start = startFileMs < 0 ? 0 : startFileMs;
  if (endFileMs - start < kMinimumTakeDuration.inMilliseconds) return null;

  final latency = playbackAlreadyRunning ? 0 : kPlaybackStartLatencyMs;
  final p0 = songPosAtStartMs < 0 ? 0 : songPosAtStartMs;
  // 마크 자리의 곡 좌표 — 곡 좌표가 0 밑으로 내려가지 않는 선에서 담을 수 있는 리드인.
  // 보정값이 음수면 늘어나고, P0 < L + C면 음수가 된다(아래에서 머리를 뒤로 옮긴다).
  final songRoom = compensateSongPositionMs(
    p0 - latency,
    latencyCompensationMs,
  );
  var lead = math.min(kArmedLeadInMs, start);
  if (songRoom < lead) lead = songRoom;

  // lead가 음수면(P0 < L) 조각이 마크 **뒤**에서 시작한다.
  final sliceStart = start - lead;
  var sliceEnd = endFileMs - kStopClickTrimMs;
  if (fileLengthMs != null && fileLengthMs < sliceEnd) sliceEnd = fileLengthMs;
  // 마크 뒤로 남은 소리가 없으면 저장할 게 없다.
  if (sliceEnd <= sliceStart || sliceEnd <= start) return null;

  final duration = sliceEnd - sliceStart;
  int clampToSlice(int ms) => ms < 0 ? 0 : (ms > duration ? duration : ms);
  return TakeSlicePlan(
    sliceStartMs: sliceStart,
    sliceEndMs: sliceEnd,
    leadInMs: lead < 0 ? 0 : lead,
    songPositionMs: songRoom - lead,
    guardFromMs: clampToSlice(lead - kStartClickGuardBeforeMs),
    guardToMs: clampToSlice(lead + kStartClickGuardAfterMs),
  );
}

/// 개루프 좌표와 실측 좌표가 의심스럽게 어긋났는가. (순수 함수)
///
/// 표시만 한다 — 값은 개루프 식을 쓴다. PositionClock의 resync 잡음은 양방향이라
/// 실측을 자동 채택하면 멀쩡한 조각까지 흔들린다.
bool isTimelineSuspect({required int openLoopMs, required int? measuredMs}) {
  if (measuredMs == null) return false;
  return (openLoopMs - measuredMs).abs() > kTimelineSuspectMs;
}

/// PCM s16 WAV 헤더(44바이트)를 만든다. (순수 함수)
Uint8List buildWavHeader(
  int dataBytes, {
  int sampleRate = kSessionSampleRate,
  int channels = 1,
  int bitsPerSample = 16,
}) {
  if (dataBytes < 0 || dataBytes > 0xFFFFFFFF - 36) {
    throw ArgumentError.value(dataBytes, 'dataBytes', 'WAV에 담을 수 없는 크기');
  }
  final header = ByteData(44);
  void tag(int offset, String text) {
    for (var i = 0; i < 4; i++) {
      header.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  final blockAlign = channels * bitsPerSample ~/ 8;
  tag(0, 'RIFF');
  header.setUint32(4, 36 + dataBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * blockAlign, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  tag(36, 'data');
  header.setUint32(40, dataBytes, Endian.little);
  return header.buffer.asUint8List();
}

/// 조각의 가장자리를 다듬는다 — 시작 키 클릭 뮤트 + 끝 페이드아웃. (제자리 수정)
///
/// 🔴 뮤트 구간과 끝 [kTailFadeMs] **밖의 샘플은 건드리지 않는다.** 램프도 구간
/// 안쪽에 둔다 — 바깥으로 번지면 부른 소리의 머리가 깎인다.
/// 구간이 조각의 처음(끝)에 붙어 있으면 그쪽 램프는 없다(이을 소리가 없다).
void shapeTakeEdges(
  Int16List samples,
  TakeSlicePlan plan, {
  int sampleRate = kSessionSampleRate,
}) {
  final n = samples.length;
  if (n == 0) return;
  final perMs = sampleRate / 1000;
  int indexAt(int ms) {
    final index = (ms * perMs).round();
    return index < 0 ? 0 : (index > n ? n : index);
  }

  final from = indexAt(plan.guardFromMs);
  final to = indexAt(plan.guardToMs);
  if (to > from) {
    final ramp = math.min((kGuardRampMs * perMs).round(), (to - from) ~/ 2);
    final down = from > 0 ? ramp : 0;
    final up = to < n ? ramp : 0;
    for (var i = from; i < to; i++) {
      var gain = 0.0;
      if (i - from < down) {
        gain = (down - 1 - (i - from)) / down;
      } else if (to - i <= up) {
        gain = (i - (to - up)) / up;
      }
      samples[i] = (samples[i] * gain).round();
    }
  }

  final fade = math.min((kTailFadeMs * perMs).round(), n);
  final fadeFrom = n - fade;
  for (var i = fadeFrom; i < n; i++) {
    // 마지막 샘플이 정확히 0이 되게 한다.
    final gain = (n - 1 - i) / fade;
    samples[i] = (samples[i] * gain).round();
  }
}

/// 샘플에서 창(기본 50ms)별 RMS의 최대값을 dBFS로 구한다. (순수 함수)
///
/// 캡처 중의 레벨 줄(astats 프레임 RMS)과 같은 잣대라 [isSilentTake]에 그대로
/// 넣을 수 있다. 완전 무음은 [parseRmsLevel]과 같이 -100으로 돌려준다.
double? maxWindowRmsDbfs(
  Int16List samples, {
  int windowSamples = kSessionSampleRate ~/ 20,
}) {
  if (samples.isEmpty || windowSamples <= 0) return null;
  var best = 0.0;
  for (var at = 0; at < samples.length; at += windowSamples) {
    final end = math.min(at + windowSamples, samples.length);
    var sum = 0.0;
    for (var i = at; i < end; i++) {
      final v = samples[i] / 32768.0;
      sum += v * v;
    }
    final meanSquare = sum / (end - at);
    if (meanSquare > best) best = meanSquare;
  }
  if (best <= 0) return -100;
  final db = 10 * math.log(best) / math.ln10;
  return db < -100 ? -100 : db;
}

/// [writeTakeFromSession]의 결과.
class TakeWriteResult {
  const TakeWriteResult({
    required this.ok,
    required this.writtenMs,
    required this.truncated,
    required this.message,
    this.peakDbfs,
    this.filledMs = 0,
  });

  /// 실패 결과를 만든다.
  const TakeWriteResult.failure(this.message)
    : ok = false,
      writtenMs = 0,
      truncated = false,
      peakDbfs = null,
      filledMs = 0;

  final bool ok;

  /// 실제로 쓴 길이(ms) — 끼워 넣은 무음 포함.
  final int writtenMs;

  /// pts 구멍 자리에 끼워 넣은 무음의 합(ms). 없으면 0.
  final int filledMs;

  /// 세션 파일이 덜 자라 계획보다 짧게 저장했는가.
  final bool truncated;

  /// 사람이 읽을 결과 문구(실패 원인 포함).
  final String message;

  /// 저장한 조각의 최대 창 RMS(dBFS) — 무음 판정용.
  final double? peakDbfs;
}

/// [file]이 [targetBytes]까지 자랄 때까지 **조건 루프**로 기다린다.
/// 상한을 넘기면 포기하고, 어느 쪽이든 마지막에 본 길이를 돌려준다.
///
/// 경로가 아니라 열린 핸들로 재는 이유: Windows는 다른 프로세스가 쓰는 중인
/// 파일의 디렉터리 항목 크기를 늦게 갱신한다. 핸들로 물으면 실제 크기가 나온다.
Future<int> waitUntilBytes(
  RandomAccessFile file,
  int targetBytes, {
  Duration poll = const Duration(milliseconds: kTakeWaitPollMs),
  Duration cap = const Duration(milliseconds: kTakeWaitCapMs),
}) async {
  final watch = Stopwatch()..start();
  var length = await file.length();
  while (length < targetBytes && watch.elapsed < cap) {
    await Future<void>.delayed(poll);
    length = await file.length();
  }
  return length;
}

/// s16le 바이트를 샘플로 본다. 리틀엔디언 호스트에서는 복사 없이 같은 메모리다.
Int16List _decodeS16le(Uint8List bytes) {
  final count = bytes.length ~/ 2;
  if (Endian.host == Endian.little && bytes.offsetInBytes.isEven) {
    return bytes.buffer.asInt16List(bytes.offsetInBytes, count);
  }
  final data = ByteData.sublistView(bytes);
  final out = Int16List(count);
  for (var i = 0; i < count; i++) {
    out[i] = data.getInt16(i * 2, Endian.little);
  }
  return out;
}

/// 샘플을 s16le 바이트로 되돌린다.
Uint8List _encodeS16le(Int16List samples) {
  if (Endian.host == Endian.little) {
    return samples.buffer.asUint8List(
      samples.offsetInBytes,
      samples.lengthInBytes,
    );
  }
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

/// 조각 안에 끼워 넣을 무음 하나 — **끼우기 전** 조각 기준 위치(ms)와 길이(ms).
typedef TakeFill = ({int atMs, int lengthMs});

/// 샘플의 [fills] 자리에 무음(0)을 끼운 새 목록을 만든다. (순수 함수 — 테스트 대상)
///
/// pts 구멍은 **파일에 없는 소리**다. 그대로 이어 붙이면 구멍 뒤의 소리가 그만큼
/// 앞당겨진 곡 좌표로 남아 반주·이어붙이기에서 어긋난다 — 빈 만큼을 무음으로 메운다.
/// 길이가 0 이하이거나 샘플 끝을 넘는 위치의 항목은 버린다(이을 소리가 없다).
/// 끼울 것이 없으면 [samples]를 그대로 돌려준다.
Int16List insertSilence(
  Int16List samples,
  List<TakeFill> fills, {
  int sampleRate = kSessionSampleRate,
}) {
  int indexOf(int ms) => (ms * sampleRate / 1000).round();
  final valid = [
    for (final fill in fills)
      if (fill.lengthMs > 0 &&
          fill.atMs >= 0 &&
          indexOf(fill.atMs) < samples.length)
        fill,
  ]..sort((a, b) => a.atMs.compareTo(b.atMs));
  if (valid.isEmpty) return samples;

  var extra = 0;
  for (final fill in valid) {
    extra += indexOf(fill.lengthMs);
  }
  // Int16List는 0으로 채워져 나온다 — 건너뛴 자리가 곧 무음이다.
  final out = Int16List(samples.length + extra);
  var src = 0;
  var dst = 0;
  for (final fill in valid) {
    final at = math.max(src, indexOf(fill.atMs));
    out.setRange(dst, dst + (at - src), samples, src);
    dst += (at - src) + indexOf(fill.lengthMs);
    src = at;
  }
  out.setRange(dst, dst + (samples.length - src), samples, src);
  return out;
}

/// 세션 PCM에서 [plan] 구간을 잘라 WAV로 저장한다.
///
/// 1. 끝 바이트가 디스크에 닿을 때까지 기다린다([waitUntilBytes]). 상한을 넘기면
///    **있는 데까지** 저장하고 `truncated`로 알린다 — 부른 소리를 버리는 것보다 낫다.
/// 2. [fills](pts 구멍)의 자리에 무음을 끼운다([insertSilence]) — 구멍 뒤의 소리가
///    제 곡 좌표에 놓이고, 길이도 벽시계 길이와 맞는다.
/// 3. 가장자리를 다듬는다([shapeTakeEdges]).
/// 4. `<출력>.part`에 쓰고 → 크기를 확인하고 → 이름을 바꾼다. 쓰다 죽어도
///    반쪽짜리 WAV가 테이크로 등록되지 않는다.
///
/// 세션 파일은 읽기만 한다. 실패해도 지우지 않는다(호출부가 복구에 쓴다).
Future<TakeWriteResult> writeTakeFromSession({
  required String sessionPath,
  required TakeSlicePlan plan,
  required String outputPath,
  List<TakeFill> fills = const [],
  Duration poll = const Duration(milliseconds: kTakeWaitPollMs),
  Duration waitCap = const Duration(milliseconds: kTakeWaitCapMs),
}) async {
  final part = File('$outputPath.part');
  RandomAccessFile? session;
  try {
    final source = File(sessionPath);
    if (!await source.exists()) {
      return TakeWriteResult.failure('세션 파일이 없습니다 — $sessionPath');
    }
    session = await source.open();
    final available = await waitUntilBytes(
      session,
      plan.endByte,
      poll: poll,
      cap: waitCap,
    );
    var endByte = math.min(plan.endByte, available);
    endByte -= endByte % 2;
    if (endByte <= plan.startByte) {
      return const TakeWriteResult.failure('세션 파일이 조각의 시작점까지 자라지 않았습니다.');
    }

    await session.setPosition(plan.startByte);
    final read = await session.read(endByte - plan.startByte);
    final usable = read.length - read.length % 2;
    if (usable <= 0) {
      return const TakeWriteResult.failure('세션 파일에서 읽은 소리가 없습니다.');
    }
    final raw = _decodeS16le(Uint8List.sublistView(read, 0, usable));
    // 구멍 메우기는 가장자리 가공보다 먼저다 — 끝 페이드가 메운 뒤의 끝에 걸려야 한다.
    final samples = insertSilence(raw, fills);
    shapeTakeEdges(samples, plan);
    final peak = maxWindowRmsDbfs(samples);
    // 길이·헤더·크기 검증은 **메운 뒤**의 바이트로 한다(잘림 판정만 원본 바이트).
    final dataBytes = samples.lengthInBytes;

    final out = await part.open(mode: FileMode.write);
    try {
      await out.writeFrom(buildWavHeader(dataBytes));
      await out.writeFrom(_encodeS16le(samples));
      await out.flush();
    } finally {
      await out.close();
    }

    final expected = 44 + dataBytes;
    final written = await part.length();
    if (written != expected) {
      await _deleteQuietly(part);
      return TakeWriteResult.failure(
        '저장한 파일 크기가 맞지 않습니다($written / $expected바이트).',
      );
    }
    await part.rename(outputPath);

    final truncated = usable < plan.endByte - plan.startByte;
    final readMs = usable ~/ kSessionBytesPerMs;
    final writtenMs = dataBytes ~/ kSessionBytesPerMs;
    final filledMs = writtenMs - readMs;
    final filledNote = filledMs > 0
        ? ' 녹음 중 끊긴 ${filledMs}ms는 무음으로 메웠습니다.'
        : '';
    return TakeWriteResult(
      ok: true,
      writtenMs: writtenMs,
      truncated: truncated,
      message: truncated
          ? '세션 파일이 덜 자라 ${plan.durationMs}ms 중 ${readMs}ms만 저장했습니다.$filledNote'
          : '조각을 저장했습니다.$filledNote',
      peakDbfs: peak,
      filledMs: filledMs,
    );
  } on FileSystemException catch (e) {
    await _deleteQuietly(part);
    return TakeWriteResult.failure('조각을 저장하지 못했습니다 — ${e.message}');
  } finally {
    try {
      await session?.close();
    } on FileSystemException {
      // 닫기 실패는 결과를 바꾸지 않는다.
    }
  }
}

/// 파일을 지운다. 없거나 못 지워도 조용히 넘어간다(정리용).
Future<void> _deleteQuietly(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } on FileSystemException {
    // 정리 실패가 본래의 오류를 가리면 안 된다.
  }
}

/// 세션 멈춤 판정. (순수 함수)
///
/// 프로세스 종료는 그 자체로 멈춤이다. 살아 있을 때는 레벨 줄 공백과 파일 크기
/// 정체가 **둘 다** 보여야 한다 — OR로 묶으면 UI 스레드가 밀려 줄 처리가 늦은
/// 것만으로 멀쩡한 세션을 죽었다고 오판한다.
bool isSessionStalled({
  required bool processExited,
  required int rmsGapMs,
  required int stagnantTicks,
}) {
  if (processExited) return true;
  return rmsGapMs >= kStallRmsGapMs && stagnantTicks >= kStallStagnantTicks;
}

/// 세션 안의 조각 표시 하나. [endFileMs]가 null이면 아직 열려 있다.
class SessionTakeMark {
  const SessionTakeMark({
    required this.startFileMs,
    this.endFileMs,
    required this.songPosAtStartMs,
    this.markedAtMs,
    this.playbackAlreadyRunning = false,
    this.latencyCompensationMs = 0,
    this.context = const {},
  });

  final int startFileMs;
  final int? endFileMs;
  final int songPosAtStartMs;

  /// 마크를 찍은 달력 시각(epoch ms). 부팅 복구가 테이크의 recordedAt으로 쓴다 —
  /// 복구 시각을 찍으면 같은 줄을 다시 받은 정상 조각이 이어붙이기에서 옛 실패
  /// 조각에 밀린다. 옛 사이드카(v5.16.0)에는 없다(null → 세션 시작 + 파일 오프셋).
  final int? markedAtMs;
  final bool playbackAlreadyRunning;

  /// 마크를 찍을 때의 「녹음 지연 보정」(ms). 복구가 **그때 값**으로 자르게 한다 —
  /// 지금 설정을 읽으면 그사이 값을 바꾼 사용자의 조각이 다른 좌표로 되살아난다.
  /// 옛 사이드카에는 없다(0 = 보정 없음 = 그때의 동작).
  final int latencyCompensationMs;

  /// 시작 순간에 굳힌 컨텍스트(곡 id·슬롯·피치·반주 경로·템포 등).
  /// 이 모듈은 내용을 해석하지 않는다 — 그대로 보관했다 돌려준다.
  final Map<String, Object?> context;

  bool get isOpen => endFileMs == null;

  /// 끝을 찍은 사본.
  SessionTakeMark closedAt(int endMs) => SessionTakeMark(
    startFileMs: startFileMs,
    endFileMs: endMs,
    songPosAtStartMs: songPosAtStartMs,
    markedAtMs: markedAtMs,
    playbackAlreadyRunning: playbackAlreadyRunning,
    latencyCompensationMs: latencyCompensationMs,
    context: context,
  );

  Map<String, Object?> toJson() => {
    'startFileMs': startFileMs,
    if (endFileMs != null) 'endFileMs': endFileMs,
    'songPosAtStartMs': songPosAtStartMs,
    if (markedAtMs != null) 'markedAtMs': markedAtMs,
    'playbackAlreadyRunning': playbackAlreadyRunning,
    'latencyCompensationMs': latencyCompensationMs,
    'context': context,
  };

  /// 관대하게 읽는다. 시작점조차 없으면 자를 수 없으니 null.
  static SessionTakeMark? fromJson(Object? json) {
    if (json is! Map) return null;
    final start = _asInt(json['startFileMs']);
    if (start == null) return null;
    return SessionTakeMark(
      startFileMs: start,
      endFileMs: _asInt(json['endFileMs']),
      songPosAtStartMs: _asInt(json['songPosAtStartMs']) ?? 0,
      markedAtMs: _asInt(json['markedAtMs']),
      playbackAlreadyRunning: json['playbackAlreadyRunning'] == true,
      latencyCompensationMs: clampRecordingLatencyMs(
        json['latencyCompensationMs'],
      ),
      context: _asStringKeyedMap(json['context']),
    );
  }
}

/// 세션 사이드카(`<세션id>.json`) — 앱이 죽었을 때 부른 소리를 되살리는 단서.
///
/// 빠진 필드는 기본값으로 읽는다. 버전이 달라 필드 하나 없다고 복구를 통째로
/// 포기하면 사이드카를 두는 의미가 없다.
class SessionSidecar {
  const SessionSidecar({
    required this.sessionId,
    this.deviceName = '',
    this.gain = 1.0,
    this.startedAtIso = '',
    this.openTake,
    this.pending = const [],
    this.aliveFileMs,
  });

  final String sessionId;
  final String deviceName;
  final double gain;
  final String startedAtIso;

  /// 소유 앱이 **마지막으로 살아 있던** 순간의 세션 파일시각(ms). 조각이 열려 있는
  /// 동안 [kSidecarHeartbeatMs]마다 갱신된다. 옛 사이드카에는 없다(null).
  ///
  /// 앱이 죽어도 고아 ffmpeg는 `-t` 상한까지 계속 쓴다 — 열린 조각의 끝을 파일
  /// 길이로 닫으면 최대 45분짜리 「복구됨」 테이크가 나온다. 이 값으로 끝을 묶는다.
  final int? aliveFileMs;

  /// 지금 열려 있는 조각(끝 미정).
  final SessionTakeMark? openTake;

  /// 끝은 찍혔지만 아직 테이크로 저장되지 않은 구간.
  final List<SessionTakeMark> pending;

  /// 되살릴 구간이 남아 있는가.
  bool get hasUnsaved => openTake != null || pending.isNotEmpty;

  /// 일부만 바꾼 사본. [clearOpenTake]는 열린 조각을 비운다.
  SessionSidecar copyWith({
    SessionTakeMark? openTake,
    bool clearOpenTake = false,
    List<SessionTakeMark>? pending,
  }) => SessionSidecar(
    sessionId: sessionId,
    deviceName: deviceName,
    gain: gain,
    startedAtIso: startedAtIso,
    openTake: clearOpenTake ? null : (openTake ?? this.openTake),
    pending: pending ?? this.pending,
    aliveFileMs: aliveFileMs,
  );

  /// 부팅 복구 때 잘라 낼 구간들.
  ///
  /// 열린 조각의 끝은 `min(파일 길이, 마지막 생존 표시 + 여유)`로 닫는다 — 파일
  /// 길이는 앱이 죽은 시각이 아니라 고아 ffmpeg가 끝난 시각이기 때문이다.
  /// 생존 표시가 없는 옛 사이드카는 파일 길이로 닫는다.
  List<SessionTakeMark> spansToRecover(int fileLengthMs) {
    final open = openTake;
    final alive = aliveFileMs;
    final openEnd = alive == null
        ? fileLengthMs
        : math.min(
            fileLengthMs,
            alive + kSidecarHeartbeatMs + kSidecarAliveSlackMs,
          );
    return [
      for (final mark in pending)
        if (!mark.isOpen) mark,
      if (open != null) open.closedAt(openEnd),
    ];
  }

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'deviceName': deviceName,
    'gain': gain,
    'startedAtIso': startedAtIso,
    'openTake': openTake?.toJson(),
    'pending': [for (final mark in pending) mark.toJson()],
    if (aliveFileMs != null) 'aliveFileMs': aliveFileMs,
  };

  String encode() => jsonEncode(toJson());

  /// 관대하게 읽는다 — 빠졌거나 형이 다른 필드는 기본값.
  factory SessionSidecar.fromJson(Map<String, Object?> json) {
    final id = json['sessionId'];
    final device = json['deviceName'];
    final gain = json['gain'];
    final started = json['startedAtIso'];
    final pending = json['pending'];
    return SessionSidecar(
      sessionId: id is String ? id : '',
      deviceName: device is String ? device : '',
      gain: gain is num && gain > 0 ? gain.toDouble() : 1.0,
      startedAtIso: started is String ? started : '',
      openTake: SessionTakeMark.fromJson(json['openTake']),
      pending: [
        if (pending is List)
          // 시작점이 없어 못 읽은 항목(null)은 빠진다.
          for (final item in pending) ?SessionTakeMark.fromJson(item),
      ],
      aliveFileMs: _asInt(json['aliveFileMs']),
    );
  }

  /// JSON 문자열에서 읽는다. 깨졌으면 null(쓰다 죽은 사이드카).
  static SessionSidecar? tryDecode(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      return SessionSidecar.fromJson(_asStringKeyedMap(decoded));
    } on FormatException {
      return null;
    }
  }
}

/// JSON 값에서 정수를 꺼낸다(실수로 저장됐어도 받는다).
int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite) return value.round();
  return null;
}

/// JSON 맵을 문자열 키 맵으로 옮긴다. 맵이 아니면 빈 맵.
Map<String, Object?> _asStringKeyedMap(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

/// 고정 대기 중 화면에 보여 줄 입력 상태. 버킷이 **바뀔 때만** 화면에 알린다 —
/// 레벨 줄마다 전체 화면을 다시 그리면 접근성 브리지 크래시 노출이 커진다.
enum InputLevelBucket { none, low, good }

/// 입력 레벨을 세 단계로 나눈다. (순수 함수)
/// 없음: 값이 없거나 [kSilentTakeDbfs] 미만(디지털 무음) / 작음: -45dB 미만.
InputLevelBucket inputLevelBucket(double? dbfs) {
  if (dbfs == null || dbfs.isNaN || dbfs < kSilentTakeDbfs) {
    return InputLevelBucket.none;
  }
  if (dbfs < -45) return InputLevelBucket.low;
  return InputLevelBucket.good;
}

/// 입력 상태의 한국어 문구 — 색이 아니라 말로 알린다.
extension InputLevelBucketLabel on InputLevelBucket {
  String get label => switch (this) {
    InputLevelBucket.none => '입력 없음',
    InputLevelBucket.low => '입력 작음',
    InputLevelBucket.good => '입력 좋음',
  };
}
