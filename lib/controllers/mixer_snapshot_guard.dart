// file: lib/controllers/mixer_snapshot_guard.dart
//
// 「지금 믹서가 녹음용 상태인가」를 가르는 순수 판정. 파일을 읽는 쪽은
// [MixerStateService]이고, 여기에는 프로세스·디스크와 무관한 규칙만 둔다.
//
// 왜 필요한가 — 녹음 입력을 FLOW 8의 `MAIN L/R`로 잡아 두면(2026-09-23 전환),
// 믹서가 **녹음 스냅샷일 때만** 마이크만 들어온다. 그 스냅샷은 PC 재생을 USB 3/4로
// 빼서 모니터 버스로만 흘린다. 다른 스냅샷이면 USB 1/2가 메인 믹스로 들어가
// **반주가 보컬 트랙에 그대로 섞인다** — 실측 −38dBFS.
//
// 이게 고약한 건 조용히 실패한다는 점이다. 녹음은 정상으로 끝나고 파일도 멀쩡하다.
// 들어 보기 전에는 알 수 없고, 알았을 때는 다시 불러야 한다. 무음 점검([isSilentTake])이
// 「소리가 안 들어오는」 실패를 막는 것과 같은 이유로, 이쪽은 「너무 많이 들어오는」
// 실패를 막는다.
//
// 믹서는 상태를 PC로 돌려주지 않는다. 그래서 확실히 아는 것은 「이 PC가 마지막으로
// 어떤 스냅샷을 보냈는가」뿐이다 — 소장님이 본체 버튼을 눌러 바꿨다면 알 수 없다.
// 그래서 **막지 않고 한 번 알린다**(호출부 정책). 모르면 아무 말도 하지 않는다.

/// 이름이 믹서의 메인 아웃(= 마이크와 PC 소리가 합쳐지는 자리)인가. (순수 함수)
///
/// [looksLikeLoopbackDevice]와 같은 잣대다 — 그쪽은 자동 선택에서 빼기 위해,
/// 이쪽은 「녹음 스냅샷이 필요한 입력인가」를 알기 위해 본다.
bool usesMixerMainInput(String? device) {
  final name = (device ?? '').toLowerCase();
  return name.contains('main l/r');
}

/// 믹서 상태를 아는 만큼만 담은 값. 모르는 항목은 null이다.
class MixerSnapshotState {
  const MixerSnapshotState({this.lastSnapshot, this.recordingSnapshot});

  /// 이 PC가 마지막으로 보낸 본체 스냅샷 번호(svil-flow8 섀도 상태).
  final int? lastSnapshot;

  /// 녹음용으로 약속된 스냅샷 번호(audio-hotkeys 녹음 슬롯이 부르는 번호).
  final int? recordingSnapshot;

  /// 둘 다 알아야 비교가 선다.
  bool get canJudge => lastSnapshot != null && recordingSnapshot != null;

  /// 녹음 스냅샷과 다른 것이 **확인된** 상태인가.
  bool get mismatched => canJudge && lastSnapshot != recordingSnapshot;
}

/// 경고 제목. 문구를 한곳에 모아 화면이 조립하지 않게 한다.
const String kMixerSnapshotAlertTitle = '믹서가 녹음 상태가 아닙니다';

/// 경고 본문을 만든다. 알릴 것이 없으면 null. (순수 함수 — 테스트 대상)
///
/// [device]가 믹서 메인 아웃이 아니면(예: USB 마이크 직결) 해당 없음이라 null이다.
/// 스냅샷을 모를 때도 null
/// — 추측으로 막으면 FLOW 8을 안 쓰는 날에도 계속 걸린다.
String? mixerSnapshotWarning({
  required String? device,
  required MixerSnapshotState? state,
}) {
  if (!usesMixerMainInput(device)) return null;
  if (state == null || !state.mismatched) return null;
  return '지금 녹음하면 반주가 보컬 트랙에 섞여 들어갑니다.\n'
      '녹음 입력이 믹서의 메인 아웃($device)이라, 믹서가 녹음 스냅샷일 때만 '
      '마이크만 들어옵니다.\n\n'
      '· 마지막으로 보낸 스냅샷: ${state.lastSnapshot}번 (녹음용은 ${state.recordingSnapshot}번)\n'
      '· Ctrl+Alt+키패드 4를 눌러 녹음 슬롯을 적용해 주세요\n'
      '· Ctrl+Alt+, 로 녹음 점검을 돌리면 실제로 섞이는지까지 확인합니다\n\n'
      '본체 버튼으로 직접 바꾸셨다면 이 안내가 틀렸을 수 있습니다 — '
      '한 번 더 누르면 그대로 녹음합니다.';
}
