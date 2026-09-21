// file: test/controllers/armed_session_controller_test.dart
//
// 녹음 고정 세션 — RecordingController 파사드 + ArmedCaptureSession.
//
// 가짜 러너가 ffmpeg의 프레임·레벨 줄과 종료를 대본대로 흘리고, 단조 시계(nowUs)는
// 테스트가 직접 움직인다. 그래서 시각에 기대는 판정(잠금·입력 점검·마크 환산·멈춤
// 감시)이 전부 결정적이다.
//
// 🔴 testWidgets로 짜면 안 된다 — 가짜 시계에서는 프로세스 스트림·파일 IO가 영영
// 안 끝나 테스트당 10분씩 타임아웃한다. 전부 plain test()다.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singpromfter_app/controllers/armed_capture_session.dart';
import 'package:singpromfter_app/controllers/capture_session.dart';
import 'package:singpromfter_app/controllers/recording_controller.dart';
import 'package:singpromfter_app/services/process/process_runner.dart';

/// 세션 파일 t=0의 벽시계(µs). 줄은 지연 없이 도착한다고 본다 — 기준점이 정확히 이 값이다.
const int _tRef = 1000000;

void main() {
  late Directory tmp;
  late Directory sessionDir;
  late Directory outDir;
  _Harness? harness;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('sp_armed_session_');
    sessionDir = Directory('${tmp.path}${Platform.pathSeparator}sessions');
    outDir = Directory('${tmp.path}${Platform.pathSeparator}out')..createSync();
  });

  tearDown(() async {
    harness?.dispose();
    harness = null;
    // 막 닫은 핸들이 늦게 풀릴 수 있어 조건 루프로 지운다.
    for (var attempt = 0; attempt < 20 && tmp.existsSync(); attempt++) {
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });

  _Harness make({Duration liveTimeout = kSessionLiveTimeout}) {
    final created = _Harness(
      sessionDir: sessionDir,
      outDir: outDir,
      liveTimeout: liveTimeout,
    );
    harness = created;
    return created;
  }

  group('armedSessionStatusLabel', () {
    test('설계 3.7의 문구', () {
      String label(ArmedSessionState state, {bool checked = false}) =>
          armedSessionStatusLabel(
            state: state,
            checked: checked,
            bucket: InputLevelBucket.good,
          );
      expect(label(ArmedSessionState.off), '');
      expect(label(ArmedSessionState.opening), '● 고정 — 마이크 여는 중');
      // 열렸어도 점검이 끝나기 전에는 스페이스를 안 받는다 — 「여는 중」으로 보인다.
      expect(label(ArmedSessionState.live), '● 고정 — 마이크 여는 중');
      expect(
        label(ArmedSessionState.live, checked: true),
        '● 고정 ON · 마이크 열림 · 입력 좋음',
      );
      expect(label(ArmedSessionState.failed), '● 고정 — 마이크 끊김');
    });
  });

  group('세션 열기', () {
    test('opening → live, 세션 인자로 띄운다', () async {
      final h = make();
      expect(h.recording.sessionState, ArmedSessionState.off);
      expect(h.recording.sessionStatusLabel, '');

      final opening = h.recording.openSession(gain: 1.5);
      expect(h.recording.sessionState, ArmedSessionState.opening);
      expect(h.recording.isSessionOpen, isTrue);
      final job = await h.runner.session(0);
      expect(h.recording.sessionState, ArmedSessionState.opening);
      expect(job.arguments, contains('-flush_packets'));
      expect(job.arguments, contains('s16le'));
      expect(job.arguments, isNot(contains('-progress')));
      expect(job.arguments.join(' '), contains('volume=1.50'));
      expect(job.outputPath, startsWith(sessionDir.path));
      expect(job.outputPath, endsWith('.pcm'));

      h.feed(job, 0);
      expect(await opening, isTrue);
      expect(h.recording.sessionState, ArmedSessionState.live);
      // 열렸지만 시계 잠금·입력 점검 전이다.
      expect(h.recording.isSessionReady, isFalse);
      expect(h.recording.sessionStatusLabel, '● 고정 — 마이크 여는 중');

      h.feedFrames(job, 1, 20);
      expect(h.recording.isSessionReady, isTrue);
      expect(h.recording.sessionStatusLabel, '● 고정 ON · 마이크 열림 · 입력 좋음');
      expect(await h.recording.sessionInputCheck, -20.0);
      expect(h.recording.sessionInputPeakDbfs, -20.0);
      expect(h.lost, isEmpty);
    });

    test('동시에 두 번 불러도 프로세스는 하나다', () async {
      final h = make();
      final first = h.recording.openSession();
      final second = h.recording.openSession();
      final job = await h.runner.session(0);
      h.feed(job, 0);
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(h.runner.sessions, hasLength(1));
      // 이미 열려 있으면 그대로 true.
      expect(await h.recording.openSession(), isTrue);
      expect(h.runner.sessions, hasLength(1));
    });

    test('장치를 못 열고 죽으면 false + 원인 + 빈 파일 정리', () async {
      final h = make();
      final opening = h.recording.openSession();
      final job = await h.runner.session(0);
      File(job.outputPath).writeAsBytesSync(const []);
      job.emit('[dshow @ 0x1] Could not find audio only device with name [x]');
      job.exit(1);

      expect(await opening, isFalse);
      expect(h.recording.sessionState, ArmedSessionState.failed);
      expect(h.recording.sessionError, contains('Could not find audio'));
      expect(h.recording.sessionStatusLabel, '● 고정 — 마이크 끊김');
      // 점검을 기다리던 화면이 멈추지 않는다.
      expect(await h.recording.sessionInputCheck, isNull);
      // 첫 열기 실패는 반환값으로 안다 — 끊김 콜백까지 부르면 경고가 두 번 뜬다.
      expect(h.lost, isEmpty);
      await _waitFor(() => sessionDir.listSync().isEmpty);
    });

    test('상한 안에 첫 프레임이 안 오면 핸들로 끊고 false', () async {
      final h = make(liveTimeout: const Duration(milliseconds: 60));
      final opening = h.recording.openSession();
      final job = await h.runner.session(0);
      expect(await opening, isFalse);
      expect(job.cancelled, isTrue);
      expect(h.recording.sessionState, ArmedSessionState.failed);
      expect(h.recording.sessionError, contains('열리지 않았습니다'));
    });

    test('열려 있는 동안 start()·프로브는 아무것도 닫지 않고 거절한다', () async {
      final h = make();
      await h.openReady();
      expect(await h.recording.start('t.wav'), isNull);
      expect(await h.recording.startLevelProbe(), isFalse);
      expect(h.recording.isRecording, isFalse);
      expect(h.runner.others, isEmpty);
      expect(h.recording.sessionState, ArmedSessionState.live);
      expect(h.runner.sessions.single.stdin, isEmpty);
    });

    test('닫은 뒤에는 예전 녹음 경로가 그대로 돈다', () async {
      final h = make();
      await h.openReady();
      await h.recording.closeSession();
      expect(await h.recording.start('t.wav'), 't.wav');
      expect(h.recording.isRecording, isTrue);
      expect(h.runner.others, hasLength(1));
      expect(h.runner.others.single.arguments, contains('-progress'));
      await h.recording.stop();
      expect(h.recording.isRecording, isFalse);
    });
  });

  group('마크', () {
    test('잠금 전·입력 점검 전에는 거절한다', () async {
      final h = make();
      final opening = h.recording.openSession();
      final job = await h.runner.session(0);
      h.feedFrames(job, 0, 3);
      expect(await opening, isTrue);
      // live지만 표본이 5개가 안 된다.
      expect(h.recording.debugSessionClock!.isLocked, isFalse);
      expect(h.recording.markTakeStart(songPositionMs: 1000), isNull);

      h.feedFrames(job, 3, 11);
      // 잠겼지만 입력 점검(900ms)이 안 끝났다.
      expect(h.recording.debugSessionClock!.isLocked, isTrue);
      expect(h.recording.isSessionInputChecked, isFalse);
      expect(h.recording.markTakeStart(songPositionMs: 1000), isNull);
      expect(h.recording.isTakeOpen, isFalse);

      h.feedFrames(job, 11, 19);
      expect(h.recording.isSessionInputChecked, isTrue);
      expect(h.recording.markTakeStart(songPositionMs: 1000), isNotNull);
    });

    test('입력이 무음이면 준비되지 않고 결과로 알린다', () async {
      final h = make();
      final opening = h.recording.openSession();
      final job = await h.runner.session(0);
      h.feedFrames(job, 0, 20, rms: -100);
      expect(await opening, isTrue);

      final peak = await h.recording.sessionInputCheck;
      expect(peak, -100.0);
      expect(isSilentTake(peak), isTrue);
      expect(h.recording.isSessionInputChecked, isTrue);
      expect(h.recording.isSessionReady, isFalse);
      expect(h.recording.markTakeStart(songPositionMs: 0), isNull);
      expect(h.recording.sessionLevelBucket, InputLevelBucket.none);
      expect(h.recording.sessionStatusLabel, '● 고정 ON · 마이크 열림 · 입력 없음');
      // 첫 열기의 무음은 화면이 결과를 기다려 처리한다(끊김 콜백 아님).
      expect(h.lost, isEmpty);
    });

    test('마크 사이에만 isTakeOpen, 최대 레벨은 그 사이만 센다', () async {
      final h = make();
      final job = await h.openReady(rms: -5);
      expect(h.recording.isTakeOpen, isFalse);
      expect(h.recording.markTakeEnd(), isNull);

      h.now = _tRef + 1000000;
      final start = h.recording.markTakeStart(
        songPositionMs: 20000,
        context: const {'songId': 'abc', 'slot': 2},
      );
      expect(start, isNotNull);
      expect(start!.wallUs, _tRef + 1000000);
      expect(start.songPositionMs, 20000);
      expect(start.context['songId'], 'abc');
      expect(h.recording.isTakeOpen, isTrue);
      // 열려 있는 동안 두 번째 시작은 없다(재진입·유령 녹음 방지).
      expect(h.recording.markTakeStart(songPositionMs: 1), isNull);

      h.feed(job, 20, rms: -30);
      h.feed(job, 21, rms: -12);
      h.feed(job, 22, rms: -25);
      expect(h.recording.sessionTakeElapsed, const Duration(milliseconds: 150));

      h.now = _tRef + 1200000;
      final end = h.recording.markTakeEnd();
      expect(end, isNotNull);
      expect(end!.id, start.id);
      expect(end.wallUs, _tRef + 1200000);
      // 마크 전의 -5는 세지 않는다.
      expect(end.peakDbfs, -12.0);
      expect(h.recording.isTakeOpen, isFalse);
      expect(h.recording.hasUnslicedSessionMarks, isTrue);
      expect(h.recording.sessionTakeElapsed, Duration.zero);
    });

    test('cancelOpenTake는 조각을 없던 일로 한다', () async {
      final h = make();
      await h.openReady();
      expect(h.recording.markTakeStart(songPositionMs: 5000), isNotNull);
      h.recording.cancelOpenTake();
      expect(h.recording.isTakeOpen, isFalse);
      expect(h.recording.hasUnslicedSessionMarks, isFalse);
      expect(h.recording.markTakeEnd(), isNull);
      // 곧바로 다음 조각을 걸 수 있다.
      expect(h.recording.markTakeStart(songPositionMs: 5000), isNotNull);
    });

    test('사이드카는 마크 뒤에 비동기로 따라온다', () async {
      final h = make();
      final job = await h.openReady();
      final sidecar = File(
        job.outputPath.replaceAll(RegExp(r'\.pcm$'), '.json'),
      );
      // 세션을 띄우기 전에 빈 사이드카부터 쓴다.
      expect(SessionSidecar.tryDecode(sidecar.readAsStringSync()), isNotNull);

      h.now = _tRef + 1000000;
      final start = h.recording.markTakeStart(
        songPositionMs: 20000,
        context: const {'songId': 'abc'},
      );
      // 동기 구간에서는 파일을 건드리지 않는다.
      expect(
        SessionSidecar.tryDecode(sidecar.readAsStringSync())!.openTake,
        isNull,
      );
      await _waitFor(
        () =>
            SessionSidecar.tryDecode(sidecar.readAsStringSync())?.openTake !=
            null,
      );
      final open = SessionSidecar.tryDecode(sidecar.readAsStringSync())!;
      expect(open.openTake!.startFileMs, 1000);
      expect(open.openTake!.songPosAtStartMs, 20000);
      expect(open.openTake!.context['songId'], 'abc');
      expect(open.deviceName, contains('RØDE'));

      h.feedFrames(job, 20, 44);
      h.now = _tRef + 2200000;
      h.recording.markTakeEnd();
      await _waitFor(
        () =>
            SessionSidecar.tryDecode(
              sidecar.readAsStringSync(),
            )?.pending.length ==
            1,
      );
      final closed = SessionSidecar.tryDecode(sidecar.readAsStringSync())!;
      expect(closed.openTake, isNull);
      expect(closed.pending.single.startFileMs, 1000);
      expect(closed.pending.single.endFileMs, 2200);
      expect(start, isNotNull);
    });
  });

  group('sliceTake', () {
    test('합성 PCM에서 기대한 길이·좌표·내용의 WAV를 만든다', () async {
      final h = make();
      final job = await h.openReady();
      _writePcm(job.outputPath, ms: 3000);

      final marks = h.markSpan(job, startMs: 1000, endMs: 2200, p0: 20000);
      final out = h.outPath('take1.wav');
      final sliced = await h.recording.sliceTake(
        marks.start,
        marks.end,
        outputPath: out,
      );

      expect(sliced, isNotNull);
      expect(sliced!.ok, isTrue);
      expect(sliced.fileName, 'take1.wav');
      expect(sliced.path, out);
      // 구간 1200 + 리드인 300 − 끝 트림 60.
      expect(sliced.durationMs, 1440);
      expect(sliced.leadInMs, 300);
      // P0 − L(15) − 리드인.
      expect(sliced.songPositionMs, 20000 - 15 - 300);
      expect(sliced.truncated, isFalse);
      expect(isSilentTake(sliced.peakDbfs), isFalse);
      expect(sliced.timelineSuspect, isFalse);

      final wav = File(out).readAsBytesSync();
      expect(wav.length, 44 + 1440 * kSessionBytesPerMs);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      // 가장자리 가공 밖의 샘플은 세션 파일 그대로다 — 조각은 파일 700ms에서 시작한다.
      final data = ByteData.sublistView(wav, 44);
      const n = 500 * 48;
      expect(data.getInt16(n * 2, Endian.little), _pcmSample(700 * 48 + n));
      expect(File('$out.part').existsSync(), isFalse);
      // 자르기만으로는 대기열에서 안 빠진다 — 목록 등록을 확인해야 빠진다.
      expect(h.recording.hasUnslicedSessionMarks, isTrue);
      await h.recording.confirmTakeSaved(marks.start);
      expect(h.recording.hasUnslicedSessionMarks, isFalse);
      // 세션 원본은 고정을 끌 때까지 둔다.
      expect(File(job.outputPath).existsSync(), isTrue);
    });

    test('0.5초보다 짧은 구간은 null이고 대기열에서 빠진다', () async {
      final h = make();
      final job = await h.openReady();
      _writePcm(job.outputPath, ms: 3000);
      final marks = h.markSpan(job, startMs: 1000, endMs: 1300, p0: 20000);
      final out = h.outPath('short.wav');
      expect(
        await h.recording.sliceTake(marks.start, marks.end, outputPath: out),
        isNull,
      );
      expect(File(out).existsSync(), isFalse);
      expect(h.recording.hasUnslicedSessionMarks, isFalse);
    });

    test('저장에 실패하면 ok=false이고 마크는 대기열에 남는다', () async {
      final h = make();
      final job = await h.openReady();
      // 세션 파일이 없다 → 자를 수 없다.
      final marks = h.markSpan(job, startMs: 1000, endMs: 2200, p0: 20000);
      final sliced = await h.recording.sliceTake(
        marks.start,
        marks.end,
        outputPath: h.outPath('fail.wav'),
      );
      expect(sliced, isNotNull);
      expect(sliced!.ok, isFalse);
      expect(sliced.message, isNotEmpty);
      expect(h.recording.hasUnslicedSessionMarks, isTrue);
    });

    test('🔴 자르기만 하고 등록을 확인하지 않으면 닫은 뒤에도 세션과 마크가 남는다', () async {
      // WAV를 쓴 직후 ~ 목록(recordings.json)에 닿기 전에 앱이 끝나는 경우의 대역.
      // 예전에는 자르자마자 사이드카에서 빼서, 조각이 목록에도 없고 복구도 안 됐다.
      final h = make();
      final job = await h.openReady();
      _writePcm(job.outputPath, ms: 3000);
      final marks = h.markSpan(job, startMs: 1000, endMs: 2200, p0: 20000);
      final sliced = await h.recording.sliceTake(
        marks.start,
        marks.end,
        outputPath: h.outPath('unconfirmed.wav'),
      );
      expect(sliced!.ok, isTrue);

      await h.recording.closeSession();
      expect(File(job.outputPath).existsSync(), isTrue);
      final sidecar = File(_siblingOf(job.outputPath, '.json'));
      await _waitFor(
        () =>
            SessionSidecar.tryDecode(
              sidecar.readAsStringSync(),
            )?.pending.length ==
            1,
      );
      expect(h.recording.hasUnslicedSessionMarks, isTrue);
    });

    test('🔴 파일이 잠깐 밀려 끝이 잘렸으면 한 번 더 기다려 다시 자른다', () async {
      final h = make();
      final job = await h.openReady();
      // 끝 바이트(2140ms)까지 못 자란 파일 — 첫 시도는 500ms 상한 뒤 있는 데까지만 쓴다.
      _writePcm(job.outputPath, ms: 1800);
      final marks = h.markSpan(job, startMs: 1000, endMs: 2200, p0: 20000);
      final out = h.outPath('late_tail.wav');
      final slicing = h.recording.sliceTake(
        marks.start,
        marks.end,
        outputPath: out,
      );
      // 첫 시도의 (잘린) 결과가 놓인 **뒤에** 나머지 소리가 도착한다.
      await _waitFor(() => File(out).existsSync());
      expect(File(out).lengthSync(), 44 + 1100 * kSessionBytesPerMs);
      _writePcm(job.outputPath, ms: 3000);

      final sliced = await slicing;
      expect(sliced!.ok, isTrue);
      expect(sliced.truncated, isFalse);
      expect(sliced.durationMs, 1440);
      expect(File(out).lengthSync(), 44 + 1440 * kSessionBytesPerMs);
      expect(File('$out.part').existsSync(), isFalse);
    });

    test('끝내 안 자라면 있는 데까지 저장하고 truncated로 알린다', () async {
      final h = make();
      final job = await h.openReady();
      _writePcm(job.outputPath, ms: 1800);
      final marks = h.markSpan(job, startMs: 1000, endMs: 2200, p0: 20000);
      final sliced = await h.recording.sliceTake(
        marks.start,
        marks.end,
        outputPath: h.outPath('cut_tail.wav'),
      );
      expect(sliced!.ok, isTrue);
      expect(sliced.truncated, isTrue);
      expect(sliced.durationMs, 1100);
    });

    test('🔴 조각 도중의 pts 구멍(드롭)은 무음으로 메워 구멍 뒤 소리를 제자리에 놓는다', () async {
      final h = make();
      final job = await h.openReady();
      _writePcm(job.outputPath, ms: 3000);

      h.now = _tRef + 1000000;
      final start = h.recording.markTakeStart(songPositionMs: 20000);
      h.feedFrames(job, 20, 30);
      // 프레임 30에서 장치가 100ms를 흘렸다 — pts도 벽시계도 100ms 건너뛴다.
      // 세션 파일에는 그 소리가 없어서, 파일은 1500ms에서 곧바로 이어진다.
      h.feedFrames(job, 30, 46, ptsShiftMs: 100);
      h.now = _tRef + 2400000;
      final end = h.recording.markTakeEnd();
      h.feedFrames(job, 46, 50, ptsShiftMs: 100);
      expect(h.recording.debugSessionClock, isNotNull);

      final out = h.outPath('holed.wav');
      final sliced = await h.recording.sliceTake(start!, end, outputPath: out);
      expect(sliced!.ok, isTrue);
      expect(sliced.filledGapMs, 100);
      // 벽시계 구간 1400 + 리드인 300 − 끝 트림 60. (안 메우면 1540 — 100ms 짧다.)
      expect(sliced.durationMs, 1640);
      expect(sliced.songPositionMs, 20000 - 15 - 300);

      final wav = File(out).readAsBytesSync();
      expect(wav.length, 44 + 1640 * kSessionBytesPerMs);
      final data = ByteData.sublistView(wav, 44);
      int at(int index) => data.getInt16(index * 2, Endian.little);
      // 구멍 앞: 조각 t=500ms = 파일 1200ms.
      expect(at(500 * 48), _pcmSample(1200 * 48));
      // 구멍(조각 800~900ms)은 무음.
      for (var i = 800 * 48; i < 900 * 48; i++) {
        expect(at(i), 0, reason: 'index $i');
      }
      // 구멍 뒤: 조각 t=900ms+n = 파일 1500ms+n — 곡 좌표로는 100ms 뒤가 맞다.
      const n = 200 * 48;
      expect(at(900 * 48 + n), _pcmSample(1500 * 48 + n));
    });

    test('교차 검증 — 재생 좌표가 맞으면 조용하고 100ms 어긋나면 표시한다', () async {
      Future<SlicedTake> run(int skewMs) async {
        final h = make();
        final job = await h.openReady();
        _writePcm(job.outputPath, ms: 3000);
        const p0 = 20000;
        const w0 = _tRef + 1000000;
        // 재생은 마크 L(15ms) 뒤에 P0에서 흐르기 시작한다.
        h.recording.songPositionProbe = () =>
            p0 + (h.now - w0) ~/ 1000 - kPlaybackStartLatencyMs + skewMs;
        final marks = h.markSpan(job, startMs: 1000, endMs: 2200, p0: p0);
        final sliced = await h.recording.sliceTake(
          marks.start,
          marks.end,
          outputPath: h.outPath('x$skewMs.wav'),
        );
        h.dispose();
        return sliced!;
      }

      final aligned = await run(0);
      expect(aligned.timelineErrorMs, 0);
      expect(aligned.timelineSuspect, isFalse);

      final skewed = await run(100);
      expect(skewed.timelineErrorMs, 100);
      expect(skewed.timelineSuspect, isTrue);
      // 표시만 한다 — 좌표는 개루프 식 그대로다.
      expect(skewed.songPositionMs, aligned.songPositionMs);
    });
  });

  group('세션 사망', () {
    test('조각이 열린 채 죽으면 onSessionLost가 마크를 넘기고 끊긴 데까지 살린다', () async {
      final h = make();
      final job = await h.openReady();
      _writePcm(job.outputPath, ms: 3000);

      h.now = _tRef + 1000000;
      final start = h.recording.markTakeStart(songPositionMs: 20000);
      h.feedFrames(job, 20, 40);
      job.emit('Error reading from device');
      job.exit(1);
      await _waitFor(() => h.lost.isNotEmpty);

      expect(h.lost, hasLength(1));
      expect(h.lost.single.message, contains('Error reading from device'));
      expect(h.lost.single.openTake, same(start));
      expect(h.recording.sessionState, ArmedSessionState.failed);
      expect(h.recording.isTakeOpen, isFalse);
      expect(h.recording.isSessionReady, isFalse);
      expect(h.recording.sessionStatusLabel, '● 고정 — 마이크 끊김');
      // 부른 소리가 남아 있다 — 세션 파일을 지우면 안 된다.
      expect(h.recording.hasUnslicedSessionMarks, isTrue);

      final out = h.outPath('salvage.wav');
      final sliced = await h.recording.sliceTake(start!, null, outputPath: out);
      expect(sliced!.ok, isTrue);
      // 파일 700ms(마크 1000 − 리드인 300)부터 끝(3000)까지. 정지 키가 없으니 트림도 없다.
      expect(sliced.durationMs, 2300);
      expect(File(out).lengthSync(), 44 + 2300 * kSessionBytesPerMs);
      await h.recording.confirmTakeSaved(start);
      expect(h.recording.hasUnslicedSessionMarks, isFalse);
    });

    test('대기 중에 죽으면 마크 없이 알린다', () async {
      final h = make();
      final job = await h.openReady();
      job.exit(1);
      await _waitFor(() => h.lost.isNotEmpty);
      expect(h.lost.single.openTake, isNull);
      expect(h.lost.single.message, contains('종료 코드 1'));
      expect(h.recording.sessionState, ArmedSessionState.failed);
    });

    test('상한이 아닌데 코드 0으로 끝나면 재기동하지 않는다', () async {
      final h = make();
      final job = await h.openReady();
      job.exit(0);
      await _waitFor(() => h.lost.isNotEmpty);
      expect(h.runner.sessions, hasLength(1));
      expect(h.recording.sessionState, ArmedSessionState.failed);
    });

    test('멈춤 감시 — 레벨 줄 공백과 파일 정체가 둘 다여야 끊김이다', () async {
      final h = make();
      final job = await h.openReady();
      _writePcm(job.outputPath, ms: 1000);

      // 줄이 방금 왔다 — 파일을 볼 것도 없다.
      await h.recording.debugSessionWatchdogTick();
      expect(h.lost, isEmpty);

      // 공백 700ms인데 파일은 자란다(= UI가 밀려 줄 처리가 늦었을 뿐).
      h.now += 700000;
      await h.recording.debugSessionWatchdogTick();
      _writePcm(job.outputPath, ms: 1100);
      await h.recording.debugSessionWatchdogTick();
      _writePcm(job.outputPath, ms: 1200);
      await h.recording.debugSessionWatchdogTick();
      expect(h.lost, isEmpty);

      // 파일도 멈췄다 — 연속 2틱 정체에서 끊김.
      await h.recording.debugSessionWatchdogTick();
      expect(h.lost, isEmpty);
      await h.recording.debugSessionWatchdogTick();
      expect(h.lost, hasLength(1));
      expect(h.lost.single.message, contains('들어오지 않습니다'));
      expect(job.cancelled, isTrue);
      expect(h.recording.sessionState, ArmedSessionState.failed);
    });

    test('줄이 다시 오면 정체 횟수를 처음부터 센다', () async {
      final h = make();
      final job = await h.openReady();
      _writePcm(job.outputPath, ms: 1000);
      h.now += 700000;
      await h.recording.debugSessionWatchdogTick();
      await h.recording.debugSessionWatchdogTick();
      // 정체 1틱에서 줄이 돌아왔다.
      h.feed(job, 40);
      h.now += 700000;
      await h.recording.debugSessionWatchdogTick();
      await h.recording.debugSessionWatchdogTick();
      expect(h.lost, isEmpty);
    });
  });

  group('상한(-t) 도달', () {
    test('코드 0 + 상한 근처 pts면 조용히 다시 열고, 옛 파일의 조각도 자를 수 있다', () async {
      final h = make();
      final job = await h.openReady();
      _writePcm(job.outputPath, ms: 3000);
      final marks = h.markSpan(job, startMs: 1000, endMs: 2200, p0: 20000);

      // 45분째의 마지막 프레임 → 정상 종료.
      h.feed(job, kSessionMaxSeconds * 20 - 10);
      job.exit(0);

      final second = await h.runner.session(1);
      expect(h.recording.sessionState, ArmedSessionState.opening);
      expect(h.recording.isSessionReady, isFalse);
      expect(second.outputPath, isNot(job.outputPath));
      h.feedFrames(second, 0, 20, base: h.now + 500000);
      expect(h.recording.sessionState, ArmedSessionState.live);
      expect(h.recording.isSessionReady, isTrue);
      expect(h.lost, isEmpty);

      // 옛 세션 파일은 저장 대기 조각 때문에 남아 있고, 그대로 잘린다.
      expect(File(job.outputPath).existsSync(), isTrue);
      final sliced = await h.recording.sliceTake(
        marks.start,
        marks.end,
        outputPath: h.outPath('old.wav'),
      );
      expect(sliced!.ok, isTrue);
      expect(sliced.durationMs, 1440);

      // 새 세션에서도 마크가 된다.
      expect(h.recording.markTakeStart(songPositionMs: 0), isNotNull);
    });

    test('다시 연 세션이 무음이면 끊김으로 알린다', () async {
      final h = make();
      final job = await h.openReady();
      // 저장 대기 조각이 있으면 미리 갈아타지 않는다 — 상한(-t) 경로를 그대로 탄다.
      h.markSpan(job, startMs: 1000, endMs: 2200, p0: 20000);
      h.feed(job, kSessionMaxSeconds * 20 - 10);
      job.exit(0);
      final second = await h.runner.session(1);
      h.feedFrames(second, 0, 20, base: h.now + 500000, rms: -100);
      expect(h.lost, hasLength(1));
      expect(h.lost.single.message, contains('소리가 없습니다'));
      expect(h.recording.sessionState, ArmedSessionState.failed);
      expect(second.cancelled, isTrue);
    });

    test('조각이 열린 채 상한에 닿으면 다시 열지 않고 마크를 넘긴다', () async {
      final h = make();
      final job = await h.openReady();
      h.now = _tRef + 1000000;
      final start = h.recording.markTakeStart(songPositionMs: 0);
      h.feed(job, kSessionMaxSeconds * 20 - 10);
      job.exit(0);
      await _waitFor(() => h.lost.isNotEmpty);
      expect(h.lost.single.openTake, same(start));
      expect(h.lost.single.message, contains('상한'));
      expect(h.runner.sessions, hasLength(1));
    });
  });

  group('선제 갈아타기(35분)', () {
    test('🔴 대기 중에 35분을 넘기면 조용히 새 세션으로 갈아탄다', () async {
      // 상한(-t 45분)이 조각 도중에 닿으면 조각이 잘리고 고정까지 풀린다. 대기 중에
      // 미리 갈아타면 상한까지 10분이 남는다.
      final h = make();
      final job = await h.openReady();
      expect(kSessionRolloverSeconds, 2100);

      // 그 직전까지는 아무 일도 없다.
      h.feed(job, kSessionRolloverSeconds * 20 - 1);
      expect(job.stdin, isEmpty);

      h.feed(job, kSessionRolloverSeconds * 20);
      expect(job.stdin, ['q']);
      expect(job.cancelled, isFalse);
      // 갈아타는 동안에는 마크를 받지 않는다(화면은 「마이크를 여는 중」으로 거절한다).
      expect(h.recording.sessionState, ArmedSessionState.opening);
      expect(h.recording.isSessionReady, isFalse);
      expect(h.recording.markTakeStart(songPositionMs: 0), isNull);

      final second = await h.runner.session(1);
      expect(second.outputPath, isNot(job.outputPath));
      h.feedFrames(second, 0, 20, base: h.now + 500000);
      expect(h.recording.isSessionReady, isTrue);
      expect(h.recording.markTakeStart(songPositionMs: 0), isNotNull);
      // 끊김이 아니다 — 경고도 고정 해제도 없다.
      expect(h.lost, isEmpty);
      expect(h.runner.sessions, hasLength(2));

      // 옛 세션 파일은 고정을 끌 때 함께 지운다.
      h.recording.cancelOpenTake();
      await h.recording.closeSession();
      expect(sessionDir.listSync(), isEmpty);
    });

    test('조각이 열려 있으면 갈아타지 않는다', () async {
      final h = make();
      final job = await h.openReady();
      h.now = _tRef + 1000000;
      expect(h.recording.markTakeStart(songPositionMs: 0), isNotNull);
      h.feed(job, kSessionRolloverSeconds * 20);
      h.feed(job, kSessionRolloverSeconds * 20 + 1);
      expect(job.stdin, isEmpty);
      expect(h.runner.sessions, hasLength(1));
      expect(h.recording.isTakeOpen, isTrue);
    });

    test('저장 대기 조각이 있으면 미루고, 등록이 확인되면 갈아탄다', () async {
      final h = make();
      final job = await h.openReady();
      _writePcm(job.outputPath, ms: 3000);
      final marks = h.markSpan(job, startMs: 1000, endMs: 2200, p0: 20000);
      h.feed(job, kSessionRolloverSeconds * 20);
      // 끝 바이트가 디스크에 닿기 전에 'q'를 보내면 조각의 끝이 잘릴 수 있다.
      expect(job.stdin, isEmpty);

      final sliced = await h.recording.sliceTake(
        marks.start,
        marks.end,
        outputPath: h.outPath('before_roll.wav'),
      );
      expect(sliced!.ok, isTrue);
      await h.recording.confirmTakeSaved(marks.start);
      h.feed(job, kSessionRolloverSeconds * 20 + 1);
      expect(job.stdin, ['q']);
      await h.runner.session(1);
      expect(h.lost, isEmpty);
    });

    test('갈아타는 도중에 닫으면 새 세션을 띄우지 않는다', () async {
      final h = make();
      final job = await h.openReady();
      // 'q'를 무시하는 프로세스 — 갈아타기가 종료를 기다리는 사이에 닫기가 온다.
      job.quitOnQ = false;
      h.feed(job, kSessionRolloverSeconds * 20);
      expect(job.stdin, ['q']);
      await h.recording.shutdown(cap: const Duration(milliseconds: 80));
      await _waitFor(() => h.recording.sessionState == ArmedSessionState.off);
      await _pump();
      expect(h.runner.sessions, hasLength(1));
      expect(h.lost, isEmpty);
    });
  });

  group('생존 표시(사이드카 하트비트)', () {
    test('🔴 조각이 열려 있는 동안 2초마다 마지막 생존 시각을 남긴다', () async {
      final h = make();
      final job = await h.openReady();
      final sidecar = File(_siblingOf(job.outputPath, '.json'));
      int? aliveMs() =>
          SessionSidecar.tryDecode(sidecar.readAsStringSync())?.aliveFileMs;

      h.now = _tRef + 1000000;
      h.recording.markTakeStart(songPositionMs: 20000);
      // 마크 직후의 사이드카에도 실린다 — 첫 하트비트 전에 죽어도 끝이 묶인다.
      await _waitFor(() => aliveMs() == 1000);

      // 1.5초 뒤 — 아직 2초가 안 됐다.
      h.feedFrames(job, 20, 50);
      await h.recording.debugSessionWatchdogTick();
      await _pump();
      expect(aliveMs(), 1000);

      // 3.0초 뒤 — 생존 표시가 따라온다(파일시각 4000ms).
      h.feedFrames(job, 50, 80);
      await h.recording.debugSessionWatchdogTick();
      await _waitFor(() => aliveMs() == 4000);
    });

    test('대기 중(조각 없음)에는 쓰지 않는다 — 주기적인 파일 쓰기도 화면 알림도 없다', () async {
      final h = make();
      final job = await h.openReady();
      final sidecar = File(_siblingOf(job.outputPath, '.json'));
      await _pump();
      final before = sidecar.readAsStringSync();
      var notified = 0;
      h.recording.addListener(() => notified++);

      h.feedFrames(job, 20, 140);
      await h.recording.debugSessionWatchdogTick();
      await _pump();
      expect(sidecar.readAsStringSync(), before);
      expect(notified, 0);
    });
  });

  group('알림', () {
    test('고정 대기 중에는 주기 알림이 없다 — 버킷이 바뀔 때만 알린다', () async {
      final h = make();
      final job = await h.openReady();
      await _pump();
      var count = 0;
      h.recording.addListener(() => count++);

      // 5초 동안 같은 레벨 — 줄은 200개가 오지만 화면은 한 번도 안 깨운다.
      h.feedFrames(job, 20, 120);
      await _pump();
      expect(count, 0);

      // 조용해졌다. 최대값 유지 창(2초)이 비면 「작음」으로 **한 번** 알린다.
      h.feedFrames(job, 120, 220, rms: -60);
      await _pump();
      expect(count, 1);
      expect(h.recording.sessionLevelBucket, InputLevelBucket.low);
      expect(h.recording.sessionStatusLabel, '● 고정 ON · 마이크 열림 · 입력 작음');

      // 큰 소리는 곧바로 「좋음」.
      h.feed(job, 220, rms: -18);
      await _pump();
      expect(count, 2);
      expect(h.recording.sessionLevelBucket, InputLevelBucket.good);
    });

    test('조각이 열려 있는 동안에는 레벨 알림이 (묶여서) 온다', () async {
      final h = make();
      final job = await h.openReady();
      await _pump();
      var count = 0;
      h.recording.addListener(() => count++);

      h.now = _tRef + 1000000;
      h.recording.markTakeStart(songPositionMs: 0);
      await _pump();
      // 마크 자체의 알림(핫패스 뒤 마이크로태스크).
      expect(count, 1);

      h.feedFrames(job, 20, 60);
      await _pump();
      // 120ms 묶음이라 줄 수(80)보다 훨씬 적다.
      expect(count, greaterThan(1));
      expect(count, lessThan(20));
      // 세션이 열려 있으면 미터는 세션의 레벨을 본다.
      expect(h.recording.dbfs, -20.0);
    });
  });

  group('닫기', () {
    test("'q'로 끝내고 세션 파일을 지운다", () async {
      final h = make();
      final job = await h.openReady();
      _writePcm(job.outputPath, ms: 1000);
      await h.recording.closeSession();

      expect(job.stdin, ['q']);
      expect(job.cancelled, isFalse);
      expect(h.recording.sessionState, ArmedSessionState.off);
      expect(h.recording.isSessionOpen, isFalse);
      expect(h.recording.sessionStatusLabel, '');
      expect(h.recording.dbfs, isNull);
      expect(sessionDir.listSync(), isEmpty);
      // 정상 종료는 끊김이 아니다.
      expect(h.lost, isEmpty);
    });

    test('저장하지 않은 마크가 있으면 PCM을 남기고, 저장이 끝나면 지운다', () async {
      final h = make();
      final job = await h.openReady();
      _writePcm(job.outputPath, ms: 3000);
      final marks = h.markSpan(job, startMs: 1000, endMs: 2200, p0: 20000);

      await h.recording.closeSession();
      expect(h.recording.sessionState, ArmedSessionState.off);
      expect(File(job.outputPath).existsSync(), isTrue);
      final sidecar = File(
        job.outputPath.replaceAll(RegExp(r'\.pcm$'), '.json'),
      );
      await _waitFor(
        () =>
            SessionSidecar.tryDecode(
              sidecar.readAsStringSync(),
            )?.pending.length ==
            1,
      );

      // 닫은 뒤에도 자를 수 있다(직렬 저장 큐가 닫기보다 늦게 도는 경우).
      final sliced = await h.recording.sliceTake(
        marks.start,
        marks.end,
        outputPath: h.outPath('late.wav'),
      );
      expect(sliced!.ok, isTrue);
      expect(sliced.durationMs, 1440);
      // 목록에 등록된 것을 확인한 뒤에야 닫힌 세션의 파일이 치워진다.
      expect(File(job.outputPath).existsSync(), isTrue);
      await h.recording.confirmTakeSaved(marks.start);
      await _waitFor(() => sessionDir.listSync().isEmpty);
    });

    test('조각이 열린 채 닫으면 끝을 찍어 대기열로 옮긴다', () async {
      final h = make();
      final job = await h.openReady();
      _writePcm(job.outputPath, ms: 3000);
      h.now = _tRef + 1000000;
      h.recording.markTakeStart(songPositionMs: 0);
      h.feedFrames(job, 20, 40);
      await h.recording.closeSession();
      expect(h.recording.isTakeOpen, isFalse);
      expect(h.recording.hasUnslicedSessionMarks, isTrue);
      expect(File(job.outputPath).existsSync(), isTrue);
    });

    test("shutdown — 'q'를 무시하는 프로세스는 상한 뒤 핸들로 끊는다", () async {
      final h = make();
      final job = await h.openReady();
      job.quitOnQ = false;
      final watch = Stopwatch()..start();
      await h.recording.shutdown(cap: const Duration(milliseconds: 80));
      expect(job.stdin, ['q']);
      expect(job.cancelled, isTrue);
      expect(await job.handle.exitCode, isNotNull);
      expect(watch.elapsedMilliseconds, lessThan(1500));
      expect(h.recording.sessionState, ArmedSessionState.off);
    });

    test('dispose는 세션 프로세스를 끊는다', () async {
      final h = make();
      final job = await h.openReady();
      h.dispose();
      expect(job.cancelled, isTrue);
      // 폐기 뒤에 늦게 온 줄·종료가 폐기된 객체를 깨우지 않는다.
      job.emit('frame:99    pts:237600    pts_time:4.95');
      await _pump();
    });

    test('여는 도중에 닫으면 뒤늦게 프로세스를 띄우지 않는다', () async {
      final h = make();
      final opening = h.recording.openSession();
      await h.recording.closeSession();
      expect(await opening, isFalse);
      await _pump();
      expect(h.runner.sessions, isEmpty);
      expect(h.recording.sessionState, ArmedSessionState.off);
      await _waitFor(
        () => !sessionDir.existsSync() || sessionDir.listSync().isEmpty,
      );
    });
  });

  group('recoverStaleSessions', () {
    String pcmOf(String id) =>
        '${sessionDir.path}${Platform.pathSeparator}$id.pcm';
    String jsonOf(String id) =>
        '${sessionDir.path}${Platform.pathSeparator}$id.json';

    test('미저장 구간을 잘라 돌려주고 나머지는 지운다', () async {
      sessionDir.createSync(recursive: true);
      final old = DateTime.now().subtract(const Duration(days: 8));

      // A: 저장 대기 1개 + 열린 조각 1개.
      _writePcm(pcmOf('a'), ms: 3000);
      File(jsonOf('a')).writeAsStringSync(
        const SessionSidecar(
          sessionId: 'a',
          deviceName: 'mic',
          openTake: SessionTakeMark(
            startFileMs: 2400,
            songPosAtStartMs: 50000,
            context: {'songId': 'open'},
          ),
          pending: [
            SessionTakeMark(
              startFileMs: 1000,
              endFileMs: 2200,
              songPosAtStartMs: 20000,
              context: {'songId': 'pending'},
            ),
          ],
        ).encode(),
      );
      // B: 미저장 구간 없음 → 지운다.
      _writePcm(pcmOf('b'), ms: 500);
      File(
        jsonOf('b'),
      ).writeAsStringSync(const SessionSidecar(sessionId: 'b').encode());
      // C: 사이드카 없음 + 새 파일 → 둔다.
      _writePcm(pcmOf('c'), ms: 500);
      // D: 사이드카 없음 + 8일 → 지운다.
      _writePcm(pcmOf('d'), ms: 500);
      File(pcmOf('d')).setLastModifiedSync(old);
      // E: PCM 없는 사이드카 → 지운다.
      File(
        jsonOf('e'),
      ).writeAsStringSync(const SessionSidecar(sessionId: 'e').encode());
      // F: 깨진 사이드카 + 새 파일 → 무엇이 담겼는지 모르니 둔다.
      _writePcm(pcmOf('f'), ms: 500);
      File(jsonOf('f')).writeAsStringSync('{"sessionId": "f", "pend');

      final h = make();
      final recovered = await h.recording.recoverStaleSessions();

      expect(recovered, hasLength(2));
      final pending = recovered[0];
      expect(pending.sessionId, 'a');
      expect(pending.wasOpenTake, isFalse);
      expect(pending.durationMs, 1440);
      expect(pending.leadInMs, 300);
      expect(pending.songPositionMs, 20000 - 15 - 300);
      expect(pending.context['songId'], 'pending');
      expect(pending.fileName, 'recovered_a_0.wav');
      expect(File(pending.path).lengthSync(), 44 + 1440 * kSessionBytesPerMs);
      expect(isSilentTake(pending.peakDbfs), isFalse);

      final open = recovered[1];
      expect(open.wasOpenTake, isTrue);
      // 2100(= 2400 − 300)부터 파일 끝 3000까지 — 끝 트림 없음.
      expect(open.durationMs, 900);
      expect(open.context['songId'], 'open');

      final left = sessionDir
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .toSet();
      expect(left, {'c.pcm', 'f.pcm', 'f.json'});
    });

    String lockOf(String id) =>
        '${sessionDir.path}${Platform.pathSeparator}$id.lock';
    Future<List<RecoveredSlice>> recoverDirect({
      Future<bool> Function(RecoveredSlice slice)? onSlice,
      String Function(String sessionId, int index)? fileNameFor,
    }) => recoverStaleCaptureSessions(
      dir: sessionDir,
      pathBuilder: (name) async => h0(outDir, name),
      onSlice: onSlice,
      fileNameFor: fileNameFor,
      growthProbe: const Duration(milliseconds: 120),
    );
    const pendingSpan = SessionTakeMark(
      startFileMs: 1000,
      endFileMs: 2200,
      songPosAtStartMs: 20000,
      context: {'songId': 'pending'},
    );

    test('세션을 여는 동안 소유 잠금을 쥐고, 닫으면 놓고 지운다', () async {
      final h = make();
      final job = await h.openReady();
      final lock = File(_siblingOf(job.outputPath, '.lock'));
      expect(lock.existsSync(), isTrue);
      if (Platform.isWindows) {
        // 다른 핸들은 잠글 수 없다 — 부팅 복구가 「살아 있는 남의 세션」으로 읽는 근거다.
        final other = await lock.open(mode: FileMode.append);
        await expectLater(
          other.lock(FileLock.exclusive),
          throwsA(isA<FileSystemException>()),
        );
        await other.close();
      }
      await h.recording.closeSession();
      expect(sessionDir.listSync(), isEmpty);
    });

    test('🔴 소유 앱이 죽었으면 고아 ffmpeg가 쓰는 중이어도 곧바로 복구하고, 열린 조각은 '
        '마지막 생존 표시에서 닫는다', () async {
      sessionDir.createSync(recursive: true);
      _writePcm(pcmOf('a'), ms: 6000);
      // 소유 앱이 죽어 잠금이 풀린 .lock.
      File(lockOf('a')).writeAsBytesSync(const []);
      File(jsonOf('a')).writeAsStringSync(
        SessionSidecar(
          sessionId: 'a',
          // 방금 시작한 세션 — 예전 판정(상한 안에 시작 + 자라는 중)으로는 「남의 살아
          // 있는 세션」이라 복구가 통째로 건너뛰어졌다.
          startedAtIso: DateTime.now().toIso8601String(),
          openTake: const SessionTakeMark(
            startFileMs: 2400,
            songPosAtStartMs: 50000,
            context: {'songId': 'open'},
          ),
          pending: const [pendingSpan],
          aliveFileMs: 2600,
        ).encode(),
      );
      // 고아 ffmpeg의 대역 — 파일을 쥔 채 계속 쓴다(그래서 지울 수도 없다).
      final orphan = _Orphan(pcmOf('a'));
      final registered = <String>[];
      try {
        final recovered = await recoverDirect(
          onSlice: (slice) async {
            registered.add(slice.fileName);
            return true;
          },
        );
        expect(recovered, hasLength(2));
        expect(registered, ['recovered_a_0.wav', 'recovered_a_1.wav']);
        expect(recovered[0].durationMs, 1440);
        final open = recovered[1];
        expect(open.wasOpenTake, isTrue);
        // 2100(= 2400 − 300)부터 「생존 2600 + 2000 + 500」 − 끝 트림 60까지.
        // 파일 길이(6초 넘게 자라는 중)까지 가지 않는다.
        expect(open.durationMs, 5100 - 60 - 2100);
        expect(
          File(open.path).lengthSync(),
          44 + open.durationMs * kSessionBytesPerMs,
        );

        if (Platform.isWindows) {
          // PCM은 고아가 쥐고 있어 못 지운다 — 사이드카가 「복구 끝」으로 남는다.
          expect(File(pcmOf('a')).existsSync(), isTrue);
          final kept = SessionSidecar.tryDecode(
            File(jsonOf('a')).readAsStringSync(),
          )!;
          expect(kept.hasUnsaved, isFalse);
        } else {
          // 열린 파일도 지워지는 OS(CI의 리눅스)에서는 그 자리에서 치워진다 —
          // 「못 지우는 고아」는 Windows의 공유 삭제 규칙에서만 생기는 상황이다.
          expect(File(pcmOf('a')).existsSync(), isFalse);
        }
      } finally {
        orphan.stop();
      }

      // 고아가 끝난 뒤의 다음 부팅 — 중복 등록 없이 치운다.
      final again = await recoverDirect(
        onSlice: (slice) async {
          registered.add(slice.fileName);
          return true;
        },
      );
      expect(again, isEmpty);
      expect(registered, hasLength(2));
      expect(sessionDir.listSync(), isEmpty);
    });

    test('🔴 다른 인스턴스가 잠금을 쥐고 있는 세션은 건드리지 않는다', () async {
      sessionDir.createSync(recursive: true);
      _writePcm(pcmOf('a'), ms: 3000);
      File(jsonOf('a')).writeAsStringSync(
        const SessionSidecar(sessionId: 'a', pending: [pendingSpan]).encode(),
      );
      final holder = await File(lockOf('a')).open(mode: FileMode.write);
      await holder.lock(FileLock.exclusive);
      try {
        expect(await recoverDirect(), isEmpty);
        expect(File(pcmOf('a')).existsSync(), isTrue);
        expect(File(jsonOf('a')).existsSync(), isTrue);
        expect(File(lockOf('a')).existsSync(), isTrue);
      } finally {
        await holder.unlock();
        await holder.close();
      }
      // 그 인스턴스가 죽으면(잠금이 풀리면) 다음 부팅이 살리고 잠금 파일도 치운다.
      final recovered = await recoverDirect();
      expect(recovered.single.durationMs, 1440);
      expect(sessionDir.listSync(), isEmpty);
    }, skip: Platform.isWindows ? null : 'Windows 전용(핸들 단위 강제 잠금)');

    test('잠금 파일이 없으면 파일 성장으로 짐작한다(폴백) — 자라는 세션은 두고, 멈추면 살린다', () async {
      sessionDir.createSync(recursive: true);
      _writePcm(pcmOf('a'), ms: 3000);
      File(jsonOf('a')).writeAsStringSync(
        SessionSidecar(
          sessionId: 'a',
          startedAtIso: DateTime.now().toIso8601String(),
          pending: const [pendingSpan],
        ).encode(),
      );
      final orphan = _Orphan(pcmOf('a'));
      try {
        expect(await recoverDirect(), isEmpty);
        expect(File(jsonOf('a')).existsSync(), isTrue);
      } finally {
        orphan.stop();
      }
      expect((await recoverDirect()).single.durationMs, 1440);
      expect(sessionDir.listSync(), isEmpty);
    });

    test('dispose는 잠금을 놓는다 — 다음 부팅이 열린 조각을 곧바로 살린다', () async {
      final h = make();
      final job = await h.openReady();
      _writePcm(job.outputPath, ms: 3000);
      final sidecar = File(_siblingOf(job.outputPath, '.json'));
      h.now = _tRef + 1000000;
      h.recording.markTakeStart(
        songPositionMs: 20000,
        context: const {'songId': 'crashed'},
      );
      await _waitFor(
        () =>
            SessionSidecar.tryDecode(sidecar.readAsStringSync())?.openTake !=
            null,
      );
      // 앱이 죽는 대역 — 닫지 못하고 폐기된다.
      h.dispose();

      final recovered = await recoverDirect();
      expect(recovered.single.wasOpenTake, isTrue);
      expect(recovered.single.context['songId'], 'crashed');
      // 700(= 1000 − 300)부터 파일 끝 3000까지(생존 표시 1000 + 2500이 파일보다 뒤다).
      expect(recovered.single.durationMs, 2300);
      await _waitFor(() => sessionDir.listSync().isEmpty);
    });

    test('🔴 등록(onSlice)이 실패한 구간은 세션에 남아 다음 부팅에 다시 시도된다', () async {
      sessionDir.createSync(recursive: true);
      _writePcm(pcmOf('a'), ms: 3000);
      File(jsonOf('a')).writeAsStringSync(
        const SessionSidecar(
          sessionId: 'a',
          pending: [
            SessionTakeMark(
              startFileMs: 200,
              endFileMs: 1200,
              songPosAtStartMs: 9000,
            ),
            SessionTakeMark(
              startFileMs: 1500,
              endFileMs: 2700,
              songPosAtStartMs: 20000,
            ),
          ],
        ).encode(),
      );
      var serial = 0;
      String name(String id, int index) => 'take_${serial++}.wav';

      // 둘째 조각의 목록 등록이 실패했다(recordings.json 쓰기 실패의 대역).
      var calls = 0;
      final first = await recoverDirect(
        fileNameFor: name,
        onSlice: (slice) async => ++calls == 1,
      );
      expect(first.single.fileName, 'take_0.wav');
      expect(File(pcmOf('a')).existsSync(), isTrue);
      final kept = SessionSidecar.tryDecode(
        File(jsonOf('a')).readAsStringSync(),
      )!;
      expect(kept.pending.single.startFileMs, 1500);

      // 등록을 맡은 쪽이 예외를 던져도 「실패」로 친다 — 세션은 남는다.
      final second = await recoverDirect(
        fileNameFor: name,
        onSlice: (slice) async => throw StateError('목록 저장 실패'),
      );
      expect(second, isEmpty);
      expect(File(pcmOf('a')).existsSync(), isTrue);

      final third = await recoverDirect(
        fileNameFor: name,
        onSlice: (slice) async => true,
      );
      expect(third.single.durationMs, 1440);
      expect(sessionDir.listSync(), isEmpty);
    });

    test('이름은 호출부가 정할 수 있다', () async {
      sessionDir.createSync(recursive: true);
      _writePcm(pcmOf('a'), ms: 3000);
      File(jsonOf('a')).writeAsStringSync(
        const SessionSidecar(
          sessionId: 'a',
          pending: [
            SessionTakeMark(
              startFileMs: 1000,
              endFileMs: 2200,
              songPosAtStartMs: 20000,
            ),
          ],
        ).encode(),
      );
      final h = make();
      final recovered = await h.recording.recoverStaleSessions(
        fileNameFor: (id, index) => 'uuid-$id-$index.wav',
      );
      expect(recovered.single.fileName, 'uuid-a-0.wav');
      expect(File(h.outPath('uuid-a-0.wav')).existsSync(), isTrue);
    });

    test('못 살린 구간은 사이드카에 남겨 다음에 다시 한다', () async {
      sessionDir.createSync(recursive: true);
      _writePcm(pcmOf('a'), ms: 3000);
      File(jsonOf('a')).writeAsStringSync(
        const SessionSidecar(
          sessionId: 'a',
          pending: [
            SessionTakeMark(
              startFileMs: 200,
              endFileMs: 1200,
              songPosAtStartMs: 9000,
            ),
            SessionTakeMark(
              startFileMs: 1500,
              endFileMs: 2700,
              songPosAtStartMs: 20000,
            ),
          ],
        ).encode(),
      );
      // 두 번째 조각이 갈 자리를 폴더로 막아 쓰기를 실패시킨다.
      Directory(h0(outDir, 'recovered_a_1.wav.part')).createSync();

      final h = make();
      final recovered = await h.recording.recoverStaleSessions();
      expect(recovered.single.fileName, 'recovered_a_0.wav');
      expect(File(pcmOf('a')).existsSync(), isTrue);
      final kept = SessionSidecar.tryDecode(
        File(jsonOf('a')).readAsStringSync(),
      )!;
      // 살린 구간이 다음 부팅에 또 등록되면 안 된다.
      expect(kept.pending.single.startFileMs, 1500);
      expect(kept.openTake, isNull);
    });

    test('지금 열려 있는 세션은 건드리지 않는다', () async {
      final h = make();
      final job = await h.openReady();
      _writePcm(job.outputPath, ms: 1000);
      final before = sessionDir.listSync().length;
      expect(await h.recording.recoverStaleSessions(), isEmpty);
      expect(File(job.outputPath).existsSync(), isTrue);
      expect(sessionDir.listSync().length, before);
    });

    test('세션 폴더가 없어도 조용히 빈 목록', () async {
      final h = make();
      expect(await h.recording.recoverStaleSessions(), isEmpty);
    });
  });
}

/// 폴더 안의 경로를 만든다.
String h0(Directory dir, String name) =>
    '${dir.path}${Platform.pathSeparator}$name';

/// 세션 PCM 경로에서 같은 세션의 다른 파일(.json·.lock) 경로를 만든다.
String _siblingOf(String pcmPath, String extension) =>
    '${pcmPath.substring(0, pcmPath.length - '.pcm'.length)}$extension';

/// 고아 ffmpeg의 대역 — 세션 PCM을 **쥔 채** 계속 이어 쓴다.
///
/// 앱이 죽어도 자식 ffmpeg는 `-t` 상한까지 살아남아 50ms마다 쓴다(실측). 핸들을 쥐고
/// 있는 동안에는 다른 쪽이 그 파일을 지울 수도 없다.
class _Orphan {
  _Orphan(String path) : _file = File(path).openSync(mode: FileMode.append) {
    _timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      _file.writeFromSync(_chunk);
      _file.flushSync();
    });
  }

  final RandomAccessFile _file;
  late final Timer _timer;

  // 50ms 분량의 무음.
  static final Uint8List _chunk = Uint8List(50 * kSessionBytesPerMs);

  /// 쓰기를 멈추고 핸들을 놓는다(프로세스가 끝난 것).
  void stop() {
    _timer.cancel();
    _file.closeSync();
  }
}

/// 이벤트 루프를 한 바퀴 돌린다(마이크로태스크 + Timer.run).
Future<void> _pump() => Future<void>.delayed(const Duration(milliseconds: 2));

/// 조건이 참이 될 때까지 기다린다(고정 sleep 대신 조건 루프). 상한을 넘기면 실패.
Future<void> _waitFor(
  bool Function() condition, {
  Duration cap = const Duration(seconds: 3),
}) async {
  final watch = Stopwatch()..start();
  while (true) {
    var ok = false;
    try {
      ok = condition();
    } on FileSystemException {
      // 이름 바꾸는 순간에 읽으면 잠깐 없을 수 있다 — 다시 본다.
    }
    if (ok) return;
    if (watch.elapsed > cap) fail('조건이 ${cap.inSeconds}초 안에 참이 되지 않았다');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// 합성 PCM의 i번째 샘플 — 위치마다 값이 달라 잘린 자리를 내용으로 확인할 수 있다.
int _pcmSample(int i) => (i % 2000) - 1000;

/// s16le 모노 48k 합성 PCM을 쓴다.
void _writePcm(String path, {required int ms}) {
  final samples = Int16List(ms * 48);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = _pcmSample(i);
  }
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(samples.buffer.asUint8List(), flush: true);
}

/// 컨트롤러 + 가짜 러너 + 손으로 움직이는 시계.
class _Harness {
  _Harness({
    required Directory sessionDir,
    required this.outDir,
    required Duration liveTimeout,
  }) {
    recording = RecordingController(
      pathBuilder: (name) async => outPath(name),
      runner: runner,
      nowUs: () => now,
      sessionDirBuilder: () async => sessionDir,
      // 타이머 없이 테스트가 직접 틱을 부른다.
      sessionWatchdogInterval: null,
      sessionLiveTimeout: liveTimeout,
    );
    recording.onSessionLost = (message, {openTake}) =>
        lost.add((message: message, openTake: openTake));
  }

  final Directory outDir;
  final _ScriptedRunner runner = _ScriptedRunner();
  late final RecordingController recording;
  final List<({String message, TakeStartMark? openTake})> lost = [];

  /// 단조 시계(µs).
  int now = 0;
  bool _disposed = false;

  String outPath(String name) => h0(outDir, name);

  /// 프레임 k의 머리줄 + 레벨 줄을 흘린다. 줄은 그 프레임이 끝나는 순간에 도착한다.
  /// [ptsShiftMs]는 그 앞에서 장치가 흘린 소리(드롭)의 합 — pts도 벽시계도 그만큼 뒤다.
  void feed(
    _ScriptedJob job,
    int k, {
    double rms = -20,
    int base = _tRef,
    int ptsShiftMs = 0,
  }) {
    now = base + (k + 1) * 50000 + ptsShiftMs * 1000;
    job.emit(
      'frame:$k    pts:${k * 2400 + ptsShiftMs * 48}    '
      'pts_time:${(k * 0.05 + ptsShiftMs / 1000).toStringAsFixed(6)}',
    );
    job.emit('lavfi.astats.Overall.RMS_level=${rms.toStringAsFixed(6)}');
  }

  /// 프레임 [from]..[to)를 차례로 흘린다.
  void feedFrames(
    _ScriptedJob job,
    int from,
    int to, {
    double rms = -20,
    int base = _tRef,
    int ptsShiftMs = 0,
  }) {
    for (var k = from; k < to; k++) {
      feed(job, k, rms: rms, base: base, ptsShiftMs: ptsShiftMs);
    }
  }

  /// 세션을 열고 준비(live + 잠금 + 입력 점검)까지 흘린다. 끝났을 때 벽시계는
  /// 기준점 + 1.0초다.
  Future<_ScriptedJob> openReady({double rms = -20}) async {
    final opening = recording.openSession();
    final job = await runner.session(0);
    feedFrames(job, 0, 20, rms: rms);
    expect(await opening, isTrue);
    expect(recording.isSessionReady, isTrue);
    return job;
  }

  /// 세션 파일 [startMs]~[endMs]에 마크 한 쌍을 찍는다(그 사이·뒤의 프레임도 흘린다).
  ({TakeStartMark start, TakeEndMark end}) markSpan(
    _ScriptedJob job, {
    required int startMs,
    required int endMs,
    required int p0,
  }) {
    now = _tRef + startMs * 1000;
    final start = recording.markTakeStart(songPositionMs: p0);
    feedFrames(job, startMs ~/ 50, endMs ~/ 50);
    now = _tRef + endMs * 1000;
    final end = recording.markTakeEnd();
    feedFrames(job, endMs ~/ 50, endMs ~/ 50 + 4);
    expect(start, isNotNull);
    expect(end, isNotNull);
    return (start: start!, end: end!);
  }

  /// 컨트롤러를 폐기한다. 여러 번 불러도 된다.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    recording.dispose();
  }
}

/// 가짜 ffmpeg 하나. 테스트가 줄과 종료를 직접 낸다.
class _ScriptedJob {
  _ScriptedJob(this.arguments);

  final List<String> arguments;

  // 동기 컨트롤러 — emit() 안에서 곧바로 처리돼, 그 순간의 시계 값이 도착 시각이 된다.
  final StreamController<String> _lines = StreamController<String>(sync: true);
  final Completer<int> _done = Completer<int>();
  final List<String> stdin = [];
  bool cancelled = false;

  /// 'q'를 받으면 코드 0으로 끝낼지. 거짓이면 무시한다(먹통 프로세스).
  bool quitOnQ = true;

  String get outputPath => arguments.last;

  late final JobHandle handle = JobHandle(
    lines: _lines.stream,
    exitCode: _done.future,
    cancel: () {
      cancelled = true;
      exit(1);
    },
    writeStdin: (data) {
      stdin.add(data);
      if (data == 'q' && quitOnQ) exit(0);
    },
  );

  /// 줄 하나를 낸다. 끝난 뒤에는 무시한다.
  void emit(String line) {
    if (_lines.isClosed) return;
    _lines.add(line);
  }

  /// 프로세스를 끝낸다. 실제 러너처럼 줄이 다 흐른 뒤에 종료 코드가 난다.
  void exit(int code) {
    if (_done.isCompleted) return;
    unawaited(_lines.close());
    _done.complete(code);
  }
}

/// 장치 목록·도구 조회에는 성공으로 답하고, 나머지 start()는 대본 작업으로 돌려준다.
class _ScriptedRunner implements ProcessRunner {
  /// 고정 세션(s16le)으로 뜬 작업.
  final List<_ScriptedJob> sessions = [];

  /// 그 밖의 작업(테이크 녹음·프로브).
  final List<_ScriptedJob> others = [];

  /// [index]번째 세션 작업이 뜰 때까지 기다린다.
  Future<_ScriptedJob> session(int index) async {
    await _waitFor(() => sessions.length > index);
    return sessions[index];
  }

  @override
  JobHandle start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) {
    if (arguments.contains('-list_devices')) {
      final controller = StreamController<String>();
      controller.add('[in#0 @ 0x1] "마이크(RØDE NT-USB Mini)" (audio)');
      final closed = controller.close();
      return JobHandle(
        lines: controller.stream,
        exitCode: closed.then((_) => 1),
        cancel: () {},
      );
    }
    final job = _ScriptedJob(arguments);
    (arguments.contains('s16le') ? sessions : others).add(job);
    return job.handle;
  }

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async => const ProcessOutput(exitCode: 0, stdout: 'ffmpeg', stderr: '');
}
