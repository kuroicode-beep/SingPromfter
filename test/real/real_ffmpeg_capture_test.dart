// file: test/real/real_ffmpeg_capture_test.dart
//
// 실제 ffmpeg + 실제 마이크로 도는 **옵트인** 회귀 테스트.
//
// 가짜 러너로는 못 잡는 결함이 있었다(2026-09-22): ffmpeg 8.1.1이 ametadata
// 출력을 종료 때까지 쌓아 둬서 레벨 줄이 'q' 뒤에야 왔고, 입력 점검이 매번
// 4초를 다 채웠다. 가짜 러너는 줄을 곧바로 흘려 주니 테스트는 전부 초록이었다.
//
// 평소 `flutter test`에서는 건너뛴다. 돌리려면:
//   SP_REAL_FFMPEG=1 flutter test test/real/real_ffmpeg_capture_test.dart
//
// 🔴 testWidgets로 짜면 안 된다 — 가짜 시계에서는 실제 프로세스 스트림이 안 흐른다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singpromfter_app/controllers/recording_controller.dart';

void main() {
  final enabled = Platform.environment['SP_REAL_FFMPEG'] == '1';
  final skip = enabled ? null : 'SP_REAL_FFMPEG=1 일 때만 돈다(실제 마이크 사용)';

  late Directory tmp;
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('sp_real_ffmpeg_');
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('입력 점검이 타임아웃 전에 값을 돌려준다', () async {
    final recording = RecordingController(
      pathBuilder: (name) async => '${tmp.path}${Platform.pathSeparator}$name',
    );
    addTearDown(recording.dispose);
    await recording.refreshDevices();

    final watch = Stopwatch()..start();
    final peak = await recording.probeInputLevel();
    watch.stop();

    // ignore: avoid_print
    print('probe: ${watch.elapsedMilliseconds}ms peak=$peak');
    expect(peak, isNotNull, reason: '레벨 줄이 실시간으로 안 온다(direct=1 회귀)');
    // 장치 열기 0.5 + 창 0.9 + 종료 0.2 — 예전에는 4.5초였다.
    expect(watch.elapsedMilliseconds, lessThan(2600));
  }, skip: skip, timeout: const Timeout(Duration(seconds: 30)));

  test("녹음 중에 레벨·좌표 표본이 'q' 전에 들어온다", () async {
    final recording = RecordingController(
      pathBuilder: (name) async => '${tmp.path}${Platform.pathSeparator}$name',
    );
    addTearDown(recording.dispose);
    await recording.refreshDevices();

    // 재생 위치 대신 벽시계를 넣는다 — t=0의 「벽시계 좌표」가 역산된다.
    final clock = Stopwatch()..start();
    recording.songPositionProbe = () => clock.elapsedMilliseconds;

    final spawnAt = clock.elapsedMilliseconds;
    expect(await recording.start('real.wav'), 'real.wav');
    await Future<void>.delayed(const Duration(milliseconds: 2500));

    final levelBeforeQuit = recording.dbfs;
    final qAt = clock.elapsedMilliseconds;
    final result = await recording.stop();
    final stopTook = clock.elapsedMilliseconds - qAt;

    // ignore: avoid_print
    print(
      'level-before-q=$levelBeforeQuit anchor=${result?.songAnchorMs} '
      '(spawn=$spawnAt) duration=${result?.duration.inMilliseconds}ms '
      'q→exit=${stopTook}ms peak=${result?.peakDbfs}',
    );
    expect(levelBeforeQuit, isNotNull, reason: "레벨 줄이 'q' 전에 안 왔다");
    expect(result, isNotNull);
    expect(result!.songAnchorMs, isNotNull);
    // 장치 열기는 spawn 뒤 0.3~0.9초.
    final openMs = result.songAnchorMs! - spawnAt;
    expect(openMs, inInclusiveRange(200, 1200));
    // 길이 = q 시각 − t=0, 버퍼 50ms라 오차는 0.2초 안쪽(예전에는 0.5초 단위).
    final expected = qAt - result.songAnchorMs!;
    expect(
      (result.duration.inMilliseconds - expected).abs(),
      lessThan(250),
    );
    expect(stopTook, lessThan(1000));
  }, skip: skip, timeout: const Timeout(Duration(seconds: 30)));
}
