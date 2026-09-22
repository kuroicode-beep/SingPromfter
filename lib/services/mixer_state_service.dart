// file: lib/services/mixer_state_service.dart
//
// FLOW 8 믹서의 「지금 상태」를 **다른 프로그램이 남긴 파일**에서 읽어 온다.
// 판정 규칙은 [mixer_snapshot_guard.dart]에 있고, 여기는 읽어 오는 일만 한다.
//
// 믹서는 USB MIDI로 상태를 돌려주지 않는다(한 방향). 대신 이 PC에는 믹서로 무엇을
// 보냈는지 적어 두는 두 파일이 있다.
//   · `%LOCALAPPDATA%\svil-flow8\state.json`   — 마지막으로 보낸 스냅샷 번호
//   · `%LOCALAPPDATA%\audio-hotkeys\config.json` — 어느 슬롯이 녹음용인지
//
// 녹음용 번호를 상수로 박지 않고 슬롯 설정에서 읽는 이유: 슬롯을 재배치해도 따라온다.
// 두 파일 중 하나라도 없거나 읽히지 않으면 **아무 말도 하지 않는다** — FLOW 8을 안
// 쓰는 사람에게 경고가 뜨면 안 된다.
import 'dart:convert';
import 'dart:io';

import '../controllers/mixer_snapshot_guard.dart';
import '../utils/platform_capabilities.dart';

/// 녹음용 슬롯을 고르는 이름 키워드. audio-hotkeys 쪽 `RECORDING_KEYWORD`와 같다.
const String kRecordingSlotKeyword = '레코딩';

class MixerStateService {
  /// [readFile]는 테스트가 디스크 없이 돌리기 위한 우회로다. 못 읽으면 null을 준다.
  MixerStateService({Future<String?> Function(String path)? readFile})
    : _readFile = readFile ?? _readIfExists;

  final Future<String?> Function(String path) _readFile;

  static Future<String?> _readIfExists(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  static String? get _localAppData => Platform.environment['LOCALAPPDATA'];

  /// 두 파일을 읽어 아는 만큼 채운다. 하나도 못 읽으면 null.
  Future<MixerSnapshotState?> read() async {
    if (PlatformCapabilities.isMobile) return null;
    final base = _localAppData;
    if (base == null || base.isEmpty) return null;

    final last = parseLastSnapshot(
      await _readFile('$base\\svil-flow8\\state.json'),
    );
    final rec = parseRecordingSnapshot(
      await _readFile('$base\\audio-hotkeys\\config.json'),
    );
    if (last == null && rec == null) return null;
    return MixerSnapshotState(lastSnapshot: last, recordingSnapshot: rec);
  }
}

/// svil-flow8 섀도 상태에서 마지막 스냅샷 번호를 꺼낸다. (순수 함수 — 테스트 대상)
int? parseLastSnapshot(String? json) {
  final map = _decodeMap(json);
  if (map == null) return null;
  final v = map['last_snapshot'];
  return v is int ? v : (v is num ? v.toInt() : null);
}

/// audio-hotkeys 슬롯 설정에서 **녹음 슬롯이 부르는** 스냅샷 번호를 꺼낸다.
/// 이름에 [kRecordingSlotKeyword]가 든 슬롯을 찾는다. (순수 함수 — 테스트 대상)
int? parseRecordingSnapshot(String? json) {
  final map = _decodeMap(json);
  if (map == null) return null;
  final snaps = map['snapshots'];
  if (snaps is! Map) return null;
  for (final entry in snaps.entries) {
    final slot = entry.value;
    if (slot is! Map) continue;
    final name = slot['name'];
    if (name is! String || !name.contains(kRecordingSlotKeyword)) continue;
    final n = slot['flow8_snapshot'];
    if (n is int) return n;
    if (n is num) return n.toInt();
  }
  return null;
}

Map<String, dynamic>? _decodeMap(String? json) {
  if (json == null || json.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(json);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null; // 다른 프로그램이 쓰는 중이라 반쯤 쓰인 파일을 읽을 수 있다
  }
}
