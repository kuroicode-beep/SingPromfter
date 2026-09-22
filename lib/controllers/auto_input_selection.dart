// file: lib/controllers/auto_input_selection.dart
//
// 입력 장치 「자동」 — 이름이 아니라 **소리가 실제로 들어오는지**로 마이크를 고른다.
//
// 예전의 자동은 「이름이 마이크 같은 첫 장치」였다. 이 PC에는 마이크가 둘인데
// (RØDE NT-USB Mini, Razer Barracuda X 2.4 동글), 동글은 헤드셋이 꺼져 있어도
// 장치 목록에 그대로 남아 **디지털 무음**(실측 −96.7dBFS)을 보낸다. dshow 열거
// 순서는 고정이 아니라서, 동글이 먼저 열거된 날에는 자동이 죽은 장치를 골라
// 무음을 녹음한다 — 저장까지 정상으로 끝나서 들어 보기 전에는 알 수 없다.
//
// 그래서 후보를 차례로 잠깐 열어 레벨을 재고, 처음으로 소리가 들어오는 장치를 쓴다.
// 비용을 묶어 두는 규칙:
//   · 직접 고른 장치가 있으면 아예 재지 않는다(지연 0).
//   · 후보가 하나뿐이면 재지 않는다 — 고를 것이 없다(무음은 기존 입력 점검이 잡는다).
//   · 살아 있는 장치는 −75dBFS를 넘는 첫 레벨 줄에서 곧바로 통과한다(실측 ≈0.56초).
//   · 무음 판정은 첫 줄 뒤 0.5초(실측 ≈1.06초), 장치당 상한 1.7초, 한 번에 3개까지만.
//   · 프로브는 'q'가 아니라 핸들로 끊는다 — 후보마다 0.5초를 아낀다.
//   · 결과는 컨트롤러가 앱을 켜 둔 동안 기억한다(RecordingController).
//
// 여기에는 프로세스와 무관한 규칙과 문구만 둔다. 실제로 장치를 여는 쪽은
// [probeInputPeakDbfs] 하나이고, 러너를 주입받아 테스트가 가짜로 바꾼다.
import 'dart:async';

import '../services/process/process_runner.dart';
import 'recording_controller.dart'
    show
        buildLevelProbeArgs,
        isSilentTake,
        looksLikeLoopbackDevice,
        looksLikeMicDevice,
        parseRmsLevel,
        preferredInputDevice;

/// 이보다 낮으면 장치가 **죽어 있다**(디지털 무음)고 본다(dBFS).
///
/// 「소리가 없다」의 기준([isSilentTake], −75)을 그대로 쓰지 않는 이유 — 실측
/// (2026-09-22 밤, 조용한 방): 살아 있는 RØDE의 첫 레벨 줄이 −70.5dBFS로 그 기준과
/// 4.5dB밖에 차이가 안 난다. Windows 마이크 볼륨을 조금만 내려도 −75 아래로 떨어져,
/// 그 기준으로 고르면 **멀쩡한 마이크를 건너뛰고 「전부 무음」**으로 막는다.
/// 죽은 장치(꺼진 Razer 동글 −96.7, 마스터를 내린 FLOW 8 −96.6)는 16비트 디더 바닥에
/// 붙어 있어서, 그 사이인 −85로 가르면 양쪽 모두 10dB 넘게 여유가 있다.
///
/// 고르는 기준만 이렇다. 「이 입력으로 녹음해도 되는가」는 여전히 [isSilentTake]가
/// 정한다 — [AutoInputSelection.inputConfirmed] 참고.
const double kDeadInputDbfs = -85;

/// 장치가 죽어 있는가(레벨 줄이 안 왔거나 디지털 무음). (순수 함수)
bool isDeadInput(double? peakDbfs) =>
    peakDbfs == null || peakDbfs < kDeadInputDbfs;

/// 자동 선택이 한 번에 소리를 재 보는 후보 수의 상한.
///
/// 후보마다 최대 1.7초라 셋이면 5초 남짓이다. 그보다 길면 「R을 눌렀는데 먹통」으로
/// 읽힌다 — 넘는 후보는 재지 않고, 재지 않았다는 사실을 경고에 적는다.
const int kAutoInputMaxProbes = 3;

/// 후보 하나의 소리를 재는 시간 규칙. 테스트가 짧게 줄여 쓴다.
class AutoProbeTiming {
  /// 첫 레벨 줄을 기다리는 상한. 실측은 프로세스 시작부터 0.53~0.58초다.
  final Duration firstLineCap;

  /// 첫 줄 뒤에 무음으로 판정하기까지 지켜보는 길이. 소리가 들어오면 기다리지 않는다.
  final Duration silentWindow;

  /// 핸들로 끊은 뒤 종료를 기다리는 상한(실측 0.01초). 넘으면 더 기다리지 않는다.
  final Duration quitCap;

  const AutoProbeTiming({
    this.firstLineCap = const Duration(milliseconds: 1200),
    this.silentWindow = const Duration(milliseconds: 500),
    this.quitCap = const Duration(milliseconds: 500),
  });
}

/// 자동 선택이 소리를 재 볼 후보를 순서대로 돌려준다. (순수 함수 — 테스트 대상)
///
/// [preferredInputDevice]와 같은 잣대다 — 이름이 마이크 같고 루프백이 아닌 장치.
/// 마이크가 하나도 없을 때만 루프백이 아닌 나머지를 후보로 본다. 믹서 메인 아웃·
/// 스테레오 믹스는 **반주가 흐르면 소리가 들어오는 장치**라, 후보에 넣으면 자동이
/// 목소리 대신 반주를 녹음한다 — 절대 넣지 않는다.
///
/// [tryFirst]는 직전에 소리가 확인됐던 장치다. 목록이 달라져 다시 고를 때 그 장치가
/// 아직 후보에 있으면 먼저 재서, 꺼진 동글을 다시 여는 1초를 아낀다.
List<String> inputDeviceCandidates(List<String> devices, {String? tryFirst}) {
  final usable = [
    for (final d in devices)
      if (!looksLikeLoopbackDevice(d)) d,
  ];
  final mics = [
    for (final d in usable)
      if (looksLikeMicDevice(d)) d,
  ];
  final candidates = mics.isNotEmpty ? mics : usable;
  if (tryFirst == null || !candidates.contains(tryFirst)) return candidates;
  return [
    tryFirst,
    for (final d in candidates)
      if (d != tryFirst) d,
  ];
}

/// 자동 선택의 결과 한 번. 불변 값이다.
class AutoInputSelection {
  /// 고른 장치. 후보가 없거나 **전부 무음**이면 null.
  final String? picked;

  /// 소리가 없어 건너뛴 장치(재 본 순서).
  final List<String> silent;

  /// 상한([kAutoInputMaxProbes]) 때문에 재 보지 않은 후보 수.
  final int untried;

  /// 실제로 소리를 재서 골랐는가. 후보가 하나 이하면 재지 않는다(거짓).
  final bool probed;

  /// 고른 장치에서 잰 최대 레벨(dBFS). 재지 않았으면 null.
  final double? pickedPeakDbfs;

  const AutoInputSelection({
    required this.picked,
    this.silent = const [],
    this.untried = 0,
    this.probed = false,
    this.pickedPeakDbfs,
  });

  /// 재 본 후보가 전부 무음이었다 — 이대로 녹음하면 무음만 저장된다.
  bool get allSilent => probed && picked == null;

  /// 고른 장치에 **녹음해도 될 만큼** 소리가 들어오는 것까지 확인됐는가.
  ///
  /// 거짓이면(재지 않았거나, 살아는 있는데 −75dBFS보다 조용했다) 화면이 기존 입력
  /// 점검을 한 번 더 돌린다 — 자동 선택이 그 안전망을 느슨하게 만들지 않는다.
  bool get inputConfirmed =>
      probed && picked != null && !isSilentTake(pickedPeakDbfs);
}

/// 후보를 차례로 재서 처음으로 소리가 들어오는 장치를 고른다. (테스트 대상)
///
/// [probePeakDbfs]는 장치 하나를 잠깐 열어 관측한 최대 레벨(dBFS)을 돌려준다 —
/// 못 열었거나 줄이 안 왔으면 null(= 무음으로 본다). 후보가 하나 이하면 부르지 않는다.
Future<AutoInputSelection> selectLiveInputDevice({
  required List<String> candidates,
  required Future<double?> Function(String device) probePeakDbfs,
  int maxProbes = kAutoInputMaxProbes,
}) async {
  if (candidates.length <= 1) {
    return AutoInputSelection(picked: candidates.firstOrNull);
  }
  final silent = <String>[];
  for (final device in candidates.take(maxProbes)) {
    final peak = await probePeakDbfs(device);
    if (!isDeadInput(peak)) {
      return AutoInputSelection(
        picked: device,
        silent: List.unmodifiable(silent),
        probed: true,
        pickedPeakDbfs: peak,
      );
    }
    silent.add(device);
  }
  return AutoInputSelection(
    picked: null,
    silent: List.unmodifiable(silent),
    untried: candidates.length - silent.length,
    probed: true,
  );
}

/// 장치 하나를 잠깐 열어 소리가 들어오는지 잰다. 관측한 최대 레벨(dBFS)을 돌려주고,
/// 못 열었거나 레벨 줄이 하나도 안 왔으면 null이다.
///
/// 소리가 들어오는 줄(−75dBFS 이상)을 보는 **그 자리에서** 끝낸다 — 살아 있는 마이크에
/// 0.5초를 더 쓸 이유가 없다. 그보다 조용한 줄만 오면 [AutoProbeTiming.silentWindow]
/// 만큼 지켜본 뒤 끝낸다(죽었는지는 부른 쪽이 [isDeadInput]으로 가른다).
///
/// 🔴 게인은 걸지 않는다(1.0). 입력 볼륨을 0%로 내려 둔 사용자는 모든 후보가
/// 무음으로 보인다 — 여기서 묻는 것은 「장치가 살아 있는가」이지 크기가 아니다.
///
/// 프로세스는 **우리 핸들로** 끊는다(이 PC는 남의 ffmpeg가 상시 돈다 — 이름으로
/// 죽이지 않는다). 파일을 쓰지 않는 프로브라 'q'로 우아하게 끝낼 이유가 없다 —
/// 실측(2026-09-22)으로 'q'는 끝나기까지 0.47~0.60초, 핸들은 0.01초였고, 끊은 직후
/// 같은 장치를 다시 열어도 첫 줄이 평소대로(0.55초) 왔다. 후보가 둘이면 1초 차이다.
/// [onJob]은 폐기 때 끊을 핸들을 알려 준다.
Future<double?> probeInputPeakDbfs({
  required ProcessRunner runner,
  required String ffmpegPath,
  required String deviceName,
  AutoProbeTiming timing = const AutoProbeTiming(),
  void Function(JobHandle? job)? onJob,
}) async {
  final JobHandle job;
  try {
    job = runner.start(ffmpegPath, buildLevelProbeArgs(deviceName: deviceName));
  } catch (_) {
    return null;
  }
  onJob?.call(job);

  final verdict = Completer<void>();
  void finish() {
    if (!verdict.isCompleted) verdict.complete();
  }

  double? peak;
  Timer? window;
  final firstLine = Timer(timing.firstLineCap, finish);
  final sub = job.lines.listen((line) {
    final rms = parseRmsLevel(line);
    if (rms == null) return;
    firstLine.cancel();
    if (peak == null || rms > peak!) peak = rms;
    if (!isSilentTake(rms)) {
      finish();
      return;
    }
    window ??= Timer(timing.silentWindow, finish);
  }, onError: (Object _) => finish());
  // 장치를 못 열면 ffmpeg가 스스로 죽는다 — 상한까지 기다리지 않는다.
  var exited = false;
  unawaited(
    job.exitCode.then((_) {
      exited = true;
      finish();
    }),
  );

  await verdict.future;
  firstLine.cancel();
  window?.cancel();
  if (!exited) {
    job.cancel();
    try {
      // 끝난 것을 보고 넘어간다 — 다음 후보(또는 실제 녹음)가 같은 장치를 열 수 있다.
      await job.exitCode.timeout(timing.quitCap);
    } on TimeoutException {
      // 핸들은 이미 끊었다 — 먹통 프로세스를 붙들고 녹음 시작을 늦추지 않는다.
    } catch (_) {}
  }
  await sub.cancel();
  onJob?.call(null);
  return peak;
}

/// 녹음·고정을 시작할 때 토스트에 붙이는 한 줄. 자동이 아니면 null. (순수 함수)
///
/// [device]는 자동이 지금 쓰는 장치, [missingExplicit]은 저장해 둔 직접 장치가
/// 목록에서 사라져 자동으로 물러났을 때의 그 이름이다. [withSkipped]는 이번에 새로
/// 고른 결과를 처음 알릴 때만 참 — 건너뛴 장치까지 매번 읽게 하지 않는다.
String? autoInputNotice({
  required String? device,
  AutoInputSelection? selection,
  String? missingExplicit,
  bool withSkipped = false,
}) {
  if (device == null) return null;
  final head = missingExplicit == null
      ? '입력 장치 자동 선택: $device'
      : '저장된 입력 장치 「$missingExplicit」를 찾지 못했습니다 — 입력 장치 자동 선택: $device';
  final skipped = selection?.silent ?? const <String>[];
  if (!withSkipped || skipped.isEmpty) return head;
  return '$head (소리가 없어 건너뜀: ${skipped.join(', ')})';
}

/// 기존 토스트 문구 앞에 자동 선택 안내를 얹는다. 안내가 없으면 그대로. (순수 함수)
String withAutoInputNotice(String? notice, String message) =>
    notice == null ? message : '$notice\n$message';

/// 「입력에 소리가 없다」 경고의 첫머리 — **어느 장치를 확인했는지** 이름으로 적는다.
/// (순수 함수 — 테스트 대상)
///
/// 전부 무음이면 재 본 장치를 모두 적고, 상한 때문에 안 재 본 후보가 있으면 그 수도
/// 적는다. 아니면 지금 쓰는 장치 하나를 적는다([auto]면 자동이 골랐다는 것까지).
String silentInputDeviceNote({
  required AutoInputSelection? selection,
  required String? device,
  required bool auto,
}) {
  if (selection != null && selection.allSilent) {
    final tried = selection.silent.join(', ');
    final rest = selection.untried > 0
        ? ' (나머지 후보 ${selection.untried}개는 확인하지 않았습니다 — '
              '한 번에 $kAutoInputMaxProbes개까지만 확인합니다)'
        : '';
    return '확인한 장치: $tried — 모두 소리 없음$rest';
  }
  if (device == null) return '입력 장치를 찾지 못했습니다';
  return auto ? '입력 장치(자동 선택): $device' : '입력 장치: $device';
}

/// 설정 > 녹음의 입력 장치 드롭다운 아래 상태 줄. **빈 문자열을 내지 않는다** —
/// 그 줄은 항상 떠 있고 글자만 바뀐다(접근성 노드를 만들었다 지우지 않는다).
/// (순수 함수 — 테스트 대상)
///
/// [explicitDevice]는 설정에서 직접 고른 장치(자동이면 null), [autoDevice]는 자동이
/// 지금 쓰는(쓸) 장치, [selection]은 이번 실행에서 마지막으로 소리를 재 본 결과다.
String inputDeviceStatusLabel({
  required String? explicitDevice,
  required List<String> devices,
  String? autoDevice,
  AutoInputSelection? selection,
}) {
  final explicit = (explicitDevice ?? '').isEmpty ? null : explicitDevice;
  final missing =
      explicit != null && devices.isNotEmpty && !devices.contains(explicit);
  if (explicit != null && !missing) {
    return '직접 고른 장치를 그대로 씁니다 — 자동으로 바꾸지 않습니다';
  }
  final head = missing ? '저장된 장치 「$explicit」가 목록에 없습니다. ' : '';
  if (selection != null && selection.allSilent) {
    return '$head자동 — 소리가 들어오는 마이크를 찾지 못했습니다 '
        '(확인한 장치: ${selection.silent.join(', ')})';
  }
  final device =
      selection?.picked ?? autoDevice ?? preferredInputDevice(devices);
  if (device == null) {
    return '$head자동 — 입력 장치가 없습니다. 새로고침을 눌러 주세요';
  }
  if (selection != null && selection.probed) {
    final skipped = selection.silent.isEmpty
        ? ''
        : ' · 소리 없는 장치 ${selection.silent.length}개 건너뜀';
    // 살아는 있는데 아주 조용했으면 「확인됨」이라고 하지 않는다 — 녹음 전 입력
    // 점검이 한 번 더 돈다.
    final confirmed = selection.inputConfirmed
        ? '소리 확인됨'
        : '장치 살아 있음 · 입력이 아주 작음';
    return '$head자동 — 지금은 $device ($confirmed$skipped)';
  }
  if (inputDeviceCandidates(devices).length > 1) {
    return '$head자동 — 지금은 $device '
        '(녹음을 시작할 때 소리가 들어오는 마이크인지 확인합니다)';
  }
  return '$head자동 — 지금은 $device';
}
