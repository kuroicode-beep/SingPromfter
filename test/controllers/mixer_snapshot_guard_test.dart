import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/controllers/mixer_snapshot_guard.dart';
import 'package:singpromfter_app/services/mixer_state_service.dart';

const rec = MixerSnapshotState(lastSnapshot: 4, recordingSnapshot: 4);
const wrong = MixerSnapshotState(lastSnapshot: 1, recordingSnapshot: 4);
const mixerDevice = 'MAIN L/R(BEHRINGER FLOW 8 (Streaming))';

void main() {
  group('usesMixerMainInput — 녹음 스냅샷이 필요한 입력인가', () {
    test('믹서 메인 아웃이면 참', () {
      expect(usesMixerMainInput(mixerDevice), isTrue);
      expect(usesMixerMainInput('main l/r (flow 8)'), isTrue);
      expect(usesMixerMainInput('MAIN L/R'), isTrue);
    });

    test('USB 마이크 직결이면 거짓 — 믹서 상태와 무관하다', () {
      expect(usesMixerMainInput('마이크(RØDE NT-USB Mini)'), isFalse);
      expect(usesMixerMainInput('마이크(Razer Barracuda X 2.4)'), isFalse);
      expect(usesMixerMainInput(null), isFalse);
      expect(usesMixerMainInput(''), isFalse);
    });
  });

  group('mixerSnapshotWarning — 알릴 것이 있을 때만 말한다', () {
    test('녹음 스냅샷이면 말하지 않는다', () {
      expect(mixerSnapshotWarning(device: mixerDevice, state: rec), isNull);
    });

    test('다른 스냅샷이면 알린다 — 번호와 다음 동작을 함께', () {
      final text = mixerSnapshotWarning(device: mixerDevice, state: wrong);
      expect(text, isNotNull);
      expect(text, contains('1번'));
      expect(text, contains('4번'));
      expect(text, contains('섞여'));
      expect(text, contains('Ctrl+Alt+키패드 4'));
    });

    test('USB 마이크 직결이면 스냅샷이 어긋나도 말하지 않는다', () {
      expect(
        mixerSnapshotWarning(device: '마이크(RØDE NT-USB Mini)', state: wrong),
        isNull,
      );
    });

    test('상태를 모르면 말하지 않는다 — 추측으로 막지 않는다', () {
      expect(mixerSnapshotWarning(device: mixerDevice, state: null), isNull);
      expect(
        mixerSnapshotWarning(
          device: mixerDevice,
          state: const MixerSnapshotState(lastSnapshot: 1),
        ),
        isNull,
      );
      expect(
        mixerSnapshotWarning(
          device: mixerDevice,
          state: const MixerSnapshotState(recordingSnapshot: 4),
        ),
        isNull,
      );
    });
  });

  group('parseLastSnapshot — svil-flow8 섀도 상태', () {
    test('번호를 꺼낸다', () {
      expect(parseLastSnapshot('{"last_snapshot": 4}'), 4);
      expect(parseLastSnapshot('{"last_snapshot": 4.0}'), 4);
    });

    test('없거나 깨졌으면 null — 다른 프로그램이 쓰는 중일 수 있다', () {
      expect(parseLastSnapshot(null), isNull);
      expect(parseLastSnapshot(''), isNull);
      expect(parseLastSnapshot('{"last_snapshot": null}'), isNull);
      expect(parseLastSnapshot('{"channels": {}}'), isNull);
      expect(parseLastSnapshot('{"last_snapshot": 4'), isNull);
      expect(parseLastSnapshot('[1,2,3]'), isNull);
    });
  });

  group('parseRecordingSnapshot — audio-hotkeys 슬롯 설정', () {
    const config = '''
{"snapshots": {
  "0": {"name": "평소 음악감상", "flow8_snapshot": 1},
  "1": {"name": "방송 일반 (말하기)", "flow8_snapshot": 2},
  "4": {"name": "레코딩 (마이크·PC 분리)", "flow8_snapshot": 4}
}}''';

    test('이름에 「레코딩」이 든 슬롯의 번호를 찾는다', () {
      expect(parseRecordingSnapshot(config), 4);
    });

    test('슬롯을 옮겨도 이름으로 따라간다 — 번호를 코드에 박지 않는다', () {
      const moved = '''
{"snapshots": {"7": {"name": "레코딩", "flow8_snapshot": 9}}}''';
      expect(parseRecordingSnapshot(moved), 9);
    });

    test('녹음 슬롯이 없으면 null', () {
      const none = '''
{"snapshots": {"0": {"name": "평소 음악감상", "flow8_snapshot": 1}}}''';
      expect(parseRecordingSnapshot(none), isNull);
    });

    test('깨졌거나 모양이 다르면 null', () {
      expect(parseRecordingSnapshot(null), isNull);
      expect(parseRecordingSnapshot('{"snapshots": []}'), isNull);
      expect(parseRecordingSnapshot('{"snapshots": {"4": 3}}'), isNull);
      expect(
        parseRecordingSnapshot('{"snapshots": {"4": {"name": "레코딩"}}}'),
        isNull,
      );
    });
  });

  group('MixerStateService — 두 파일을 합쳐 읽는다', () {
    test('둘 다 읽히면 비교가 선다', () async {
      final svc = MixerStateService(
        readFile: (path) async => path.contains('svil-flow8')
            ? '{"last_snapshot": 1}'
            : '{"snapshots": {"4": {"name": "레코딩", "flow8_snapshot": 4}}}',
      );
      final state = await svc.read();
      expect(state, isNotNull);
      expect(state!.canJudge, isTrue);
      expect(state.mismatched, isTrue);
    });

    test('둘 다 없으면 null — FLOW 8을 안 쓰면 조용하다', () async {
      final svc = MixerStateService(readFile: (_) async => null);
      expect(await svc.read(), isNull);
    });

    test('한쪽만 읽히면 판단하지 않는다', () async {
      final svc = MixerStateService(
        readFile: (path) async =>
            path.contains('svil-flow8') ? '{"last_snapshot": 1}' : null,
      );
      final state = await svc.read();
      expect(state, isNotNull);
      expect(state!.canJudge, isFalse);
      expect(state.mismatched, isFalse);
    });
  });
}
