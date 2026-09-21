// file: test/controllers/capture_session_test.dart
//
// 상시 캡처 세션의 순수 부품 테스트.
//
// 🔴 전부 plain test()다. 파일 IO·타이머를 실제로 기다리는 코드는 testWidgets의
// 가짜 시계에서 영영 끝나지 않는다(테스트 하나가 10분 타임아웃).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/controllers/capture_session.dart';
import 'package:singpromfter_app/controllers/recording_controller.dart';

const int _frameUs = 50000;

/// 「도착은 늦어질 수만 있다」를 흉내 내는 지터. 대부분 0~65ms 늦고, 25줄에 한 번은
/// 제때(0.2ms 안) 온다 — 최소값 필터가 기대는 물리적 전제가 바로 이것이다.
int Function(int k) _oneWayJitter(int seed) {
  final rng = math.Random(seed);
  return (k) => k % 25 == 7 ? rng.nextInt(200) : rng.nextInt(65001);
}

/// 세션 줄을 만들어 시계에 먹인다. 돌려주는 값은 마지막 줄의 도착 시각.
///
/// 프레임 k의 머리줄은 그 프레임이 **다 담긴 뒤**에야 나온다 —
/// 도착 = T0 + (pts_k + 프레임 길이) × (1 + ppm) + 지터.
/// [ptsJumpAt]의 프레임은 pts가 그만큼 건너뛴다(드롭).
int _feed(
  CaptureClock clock, {
  required int t0Us,
  required int frames,
  int firstPtsUs = 0,
  int Function(int k)? jitterUs,
  double ppm = 0,
  Map<int, int> ptsJumpAt = const {},
  void Function(int k, int arrivalUs)? onFrame,
}) {
  var pts = firstPtsUs;
  var lastArrival = 0;
  for (var k = 0; k < frames; k++) {
    pts += ptsJumpAt[k] ?? 0;
    final trueEnd = ((pts + _frameUs) * (1 + ppm * 1e-6)).round();
    lastArrival = t0Us + trueEnd + (jitterUs?.call(k) ?? 0);
    clock.addFrame(arrivalUs: lastArrival, ptsUs: pts);
    onFrame?.call(k, lastArrival);
    pts += _frameUs;
  }
  return lastArrival;
}

/// 테스트용 PCM 패턴 — 위치마다 값이 달라 잘린 자리가 어긋나면 바로 드러난다.
Int16List _pattern(int ms, {int fromMs = 0}) {
  final out = Int16List(ms * 48);
  for (var i = 0; i < out.length; i++) {
    final at = i + fromMs * 48;
    out[i] = (at * 7919) % 20001 - 10000;
  }
  return out;
}

Uint8List _bytesOf(Int16List samples) =>
    samples.buffer.asUint8List(samples.offsetInBytes, samples.lengthInBytes);

void main() {
  group('상수 — 설계서 값 고정', () {
    test('트림·가드·시계 상수', () {
      expect(kSessionMaxSeconds, 2700);
      expect(kArmedLeadInMs, 300);
      expect(kStopClickTrimMs, 60);
      expect(kTailFadeMs, 20);
      expect(kStartClickGuardBeforeMs, 40);
      expect(kStartClickGuardAfterMs, 60);
      expect(kGuardRampMs, 5);
      expect(kPlaybackStartLatencyMs, 15);
      expect(kClockLockFrames, 5);
      expect(kClockBucketUs, 1000000);
      expect(kClockBucketCount, 10);
      expect(kTimelineSuspectMs, 40);
      expect(kTakeWaitPollMs, 10);
      expect(kTakeWaitCapMs, 500);
      expect(kSessionBytesPerMs, 96);
      // 첫 간격의 시작 점프 문턱은 pts 흔들림(±2ms)보다만 크다 — 실측 17~36ms를 다 잡는다.
      expect(kClockStartGapSlackUs, 5000);
      expect(kClockGapSlackUs, 20000);
      expect(kSidecarHeartbeatMs, 2000);
      expect(kSidecarAliveSlackMs, 500);
    });

    test('세션 파일 이름', () {
      expect(sessionPcmFileName('s-1'), 's-1.pcm');
      expect(sessionSidecarFileName('s-1'), 's-1.json');
      expect(sessionLockFileName('s-1'), 's-1.lock');
    });
  });

  group('buildSessionCaptureArgs', () {
    List<String> args({double gain = 1.0}) => buildSessionCaptureArgs(
      deviceName: '마이크(RØDE NT-USB Mini)',
      outputPath: 'C:/sessions/a.pcm',
      gain: gain,
    );

    test('dshow 한 입력, 버퍼 50ms가 -i 앞에 온다', () {
      final a = args();
      expect(a.where((e) => e == '-i'), hasLength(1));
      final i = a.indexOf('-i');
      expect(a[i + 1], 'audio=마이크(RØDE NT-USB Mini)');
      expect(a.sublist(i - 2, i), ['-audio_buffer_size', '50']);
      expect(a.sublist(i - 4, i - 2), ['-f', 'dshow']);
    });

    test('raw s16le 모노 48k, 즉시 플러시, 45분 상한', () {
      final a = args();
      expect(a[a.indexOf('-ac') + 1], '1');
      expect(a[a.indexOf('-ar') + 1], '48000');
      expect(a, containsAllInOrder(['-flush_packets', '1']));
      expect(a[a.indexOf('-flush_packets') + 1], '1');
      expect(a[a.indexOf('-t') + 1], '2700');
      expect(a.sublist(a.length - 4), [
        '-f',
        's16le',
        '-y',
        'C:/sessions/a.pcm',
      ]);
    });

    test('-progress는 없다 (515ms 간격이라 쓸모없다)', () {
      expect(args(), isNot(contains('-progress')));
      expect(args(), contains('-nostats'));
    });

    test('필터는 테이크 녹음과 같은 문자열이다 (direct=1 포함)', () {
      for (final gain in [1.0, 1.5]) {
        final session = args(gain: gain);
        final take = buildRecordArgs(
          deviceName: 'mic',
          outputPath: 'o.wav',
          gain: gain,
        );
        final filter = session[session.indexOf('-af') + 1];
        expect(filter, take[take.indexOf('-af') + 1]);
        expect(filter, captureFilterChain(gain));
        expect(filter, endsWith(':file=-:direct=1'));
      }
      expect(args(gain: 1.5)[args().indexOf('-af') + 1], startsWith('volume='));
    });
  });

  group('parseAmetadataFramePtsUs', () {
    test('µs 해상도로 읽는다', () {
      // 3072 / 44100초 = 69659.86µs
      expect(
        parseAmetadataFramePtsUs('frame:3    pts:3072    pts_time:0.0696599'),
        69660,
      );
      expect(parseAmetadataFramePtsUs('frame:0    pts:0       pts_time:0'), 0);
      expect(
        parseAmetadataFramePtsUs('frame:20   pts:48000   pts_time:1'),
        1000000,
      );
      expect(
        parseAmetadataFramePtsUs('frame:1    pts:2400    pts_time:0.05'),
        50000,
      );
    });

    test('pts_time이 유효숫자 6자리로 뭉개져도 pts로 정확히 계산한다', () {
      // 구버전 ffmpeg의 %.6g — 1234.568초가 1234.57로 찍힌다(2ms 오차).
      expect(
        parseAmetadataFramePtsUs('frame:24691 pts:59259264 pts_time:1234.57'),
        1234568000,
      );
    });

    test('시간축을 못 알아내면 pts_time을 쓴다', () {
      expect(
        parseAmetadataFramePtsUs('frame:9 pts:1500000 pts_time:1.5'),
        1500000,
      );
    });

    test('ms 파서와 같은 줄을 같은 값으로 읽는다', () {
      const line = 'frame:3    pts:3072    pts_time:0.0696599';
      expect(
        usToMs(parseAmetadataFramePtsUs(line)!),
        parseAmetadataFramePtsMs(line),
      );
    });

    test('다른 줄은 null', () {
      expect(
        parseAmetadataFramePtsUs('lavfi.astats.Overall.RMS_level=-21.0'),
        isNull,
      );
      expect(parseAmetadataFramePtsUs('out_time=00:00:01.500000'), isNull);
      expect(parseAmetadataFramePtsUs(''), isNull);
    });
  });

  group('CaptureClock — 잠금', () {
    test('표본 5개가 쌓이기 전에는 잠기지 않고 환산을 거절한다', () {
      final clock = CaptureClock();
      expect(clock.isLocked, isFalse);
      expect(clock.fileTimeUsAt(1000000), isNull);
      expect(clock.tRefUs, isNull);

      // 줄 5개 = 표본 4개.
      final last = _feed(clock, t0Us: 3217000, frames: 5);
      expect(clock.sampleCount, 4);
      expect(clock.isLocked, isFalse);
      expect(clock.fileTimeUsAt(last), isNull);

      clock.addFrame(arrivalUs: 3217000 + 6 * _frameUs, ptsUs: 5 * _frameUs);
      expect(clock.sampleCount, 5);
      expect(clock.isLocked, isTrue);
      expect(clock.fileTimeUsAt(3217000 + 200000), 200000);
    });

    test('pts가 제자리거나 뒤로 간 줄은 버린다', () {
      final clock = CaptureClock();
      _feed(clock, t0Us: 1000, frames: 10);
      final before = clock.sampleCount;
      clock.addFrame(arrivalUs: 1000 + 600000, ptsUs: 9 * _frameUs);
      clock.addFrame(arrivalUs: 1000 + 610000, ptsUs: 2 * _frameUs);
      expect(clock.sampleCount, before);
      expect(clock.tRefUs, 1000);
    });

    test('줄로 확인된 파일 길이', () {
      final clock = CaptureClock();
      expect(clock.confirmedFileUs, 0);
      _feed(clock, t0Us: 0, frames: 20);
      expect(clock.confirmedFileUs, 19 * _frameUs);
      expect(clock.nominalFrameUs, _frameUs);
    });
  });

  group('CaptureClock — 지터·드리프트·일괄 도착', () {
    test('한쪽으로만 늦는 지터(0~65ms) 200프레임 → 기준점이 참값 1ms 안', () {
      const t0 = 3217431;
      final clock = CaptureClock();
      final last = _feed(
        clock,
        t0Us: t0,
        frames: 200,
        jitterUs: _oneWayJitter(20260922),
      );
      final ref = clock.tRefUs!;
      // 늦어질 수만 있으니 참값 밑으로는 절대 안 내려간다.
      expect(ref, greaterThanOrEqualTo(t0));
      expect(ref - t0, lessThan(1000));
      expect(
        clock.fileTimeUsAt(t0 + 5000000)! - 5000000,
        inInclusiveRange(-1000, 0),
      );
      expect(clock.fileTimeUsAt(last), isNotNull);
      expect(clock.totalGapUs, 0);
    });

    for (final ppm in [50.0, -50.0]) {
      test('드리프트 ${ppm.round()}ppm을 10분 동안 2ms 안으로 따라간다', () {
        const t0 = 900000;
        final clock = CaptureClock();
        final checks = <int>[];
        var worstNow = 0;
        _feed(
          clock,
          t0Us: t0,
          frames: 12000,
          ppm: ppm,
          jitterUs: _oneWayJitter(7),
          onFrame: (k, arrivalUs) {
            // 10초마다 「지금」을 환산해 참값과 견준다.
            if (k < 200 || k % 200 != 0) return;
            final truth = ((arrivalUs - t0) / (1 + ppm * 1e-6)).round();
            final error = (clock.fileTimeUsAt(arrivalUs)! - truth).abs();
            if (error > worstNow) worstNow = error;
            checks.add(error);
          },
        );
        expect(checks.length, greaterThan(50));
        expect(worstNow, lessThan(2000));

        // 1분 무렵에 찍은 마크를 10분 뒤에 환산해도 2ms 안이다 — 저장 시점의
        // 기준점 하나로 환산했다면 50ppm × 9분 = 27ms가 어긋난다.
        const markWall = t0 + 60000000;
        final truth = (60000000 / (1 + ppm * 1e-6)).round();
        expect((clock.fileTimeUsAt(markWall)! - truth).abs(), lessThan(2000));
      });
    }

    test('한꺼번에 몰려 온 줄(같은 도착 시각)은 최소값을 움직이지 않는다', () {
      const t0 = 5000000;
      final clock = CaptureClock();
      _feed(clock, t0Us: t0, frames: 100, jitterUs: _oneWayJitter(3));
      final before = clock.tRefUs!;
      final fileBefore = clock.fileTimeUsAt(t0 + 2000000);

      // UI 스레드가 600ms 밀렸다가 줄 12개를 한 번에 처리했다. 도착 시각은 전부
      // 마지막 프레임이 다 담긴 시각이다.
      const firstPts = 100 * _frameUs;
      const batchArrival = t0 + firstPts + 12 * _frameUs;
      for (var j = 0; j < 12; j++) {
        clock.addFrame(arrivalUs: batchArrival, ptsUs: firstPts + j * _frameUs);
      }
      expect(clock.tRefUs, before);
      expect(clock.tRefUs, greaterThanOrEqualTo(t0));
      expect(clock.fileTimeUsAt(t0 + 2000000), fileBefore);
      expect(clock.totalGapUs, 0);

      // 그 뒤로 정상 도착이 이어져도 참값 밑으로 내려가지 않는다.
      _feed(clock, t0Us: t0, frames: 40, firstPtsUs: 112 * _frameUs);
      expect(clock.tRefUs, greaterThanOrEqualTo(t0));
      expect(clock.tRefUs! - t0, lessThan(1000));
    });
  });

  group('CaptureClock — 드롭(pts 건너뜀)', () {
    const t0 = 2000000;

    test('150ms 건너뛰면 gap=100ms, 뒤의 파일시각만 그만큼 당겨진다', () {
      final clock = CaptureClock();
      // 40번째 프레임에서 100ms를 잃었다 — pts 간격이 50 → 150ms.
      _feed(clock, t0Us: t0, frames: 80, ptsJumpAt: {40: 100000});
      expect(clock.totalGapUs, 100000);
      // 구멍에 걸친 표본을 버렸으니 기준점은 참값 그대로다
      // (안 버리면 최소값 필터가 T0 − 100ms를 고른다).
      expect(clock.tRefUs, t0);

      // 드롭 **전**의 마크는 영향이 없다.
      expect(clock.gapUsUpTo(t0 + 1000000), 0);
      expect(clock.fileTimeUsAt(t0 + 1000000), 1000000);
      expect(clock.fileTimeUsAt(t0 + 1999000), 1999000);
      // 드롭 **뒤**는 100ms 당겨진다.
      expect(clock.gapUsUpTo(t0 + 3000000), 100000);
      expect(clock.fileTimeUsAt(t0 + 3000000), 2900000);
      // 구멍 안에서 찍은 마크는 구멍이 시작한 자리로 간다.
      expect(clock.fileTimeUsAt(t0 + 2050000), 2000000);
    });

    test('구멍이 둘이면 누적되고, 사이의 마크는 앞의 것만 본다', () {
      final clock = CaptureClock();
      _feed(clock, t0Us: t0, frames: 120, ptsJumpAt: {40: 100000, 80: 250000});
      expect(clock.totalGapUs, 350000);
      expect(clock.fileTimeUsAt(t0 + 1000000), 1000000);
      expect(clock.fileTimeUsAt(t0 + 3000000), 2900000);
      expect(clock.fileTimeUsAt(t0 + 6000000), 5650000);
    });

    test('공칭+20ms 이하의 흔들림은 드롭이 아니다', () {
      final clock = CaptureClock();
      _feed(clock, t0Us: t0, frames: 60, ptsJumpAt: {30: 20000});
      expect(clock.totalGapUs, 0);
    });

    test('첫 간격부터 드롭이어도 가려낸다 (워밍업)', () {
      final clock = CaptureClock();
      _feed(clock, t0Us: t0, frames: 30, ptsJumpAt: {1: 100000});
      expect(clock.totalGapUs, 100000);
      expect(clock.tRefUs, t0);
      expect(clock.nominalFrameUs, _frameUs);
    });

    test('🔴 세션 첫 간격의 18ms 점프는 시작 구멍으로 센다 (문턱 5ms)', () {
      // 실측: Razer 동글은 시작 점프가 17~23ms라 20ms 문턱에 걸쳐 있었다. 놓치면
      // 그 표본이 최소값 필터에 들어가 기준점이 18ms 앞당겨지고(= 파일시각 +18ms),
      // 세션 내내 모든 조각이 파일에서 18ms 늦게 잘린다.
      final clock = CaptureClock();
      _feed(clock, t0Us: t0, frames: 30, ptsJumpAt: {1: 18000});
      expect(clock.totalGapUs, 18000);
      expect(clock.nominalFrameUs, _frameUs);
      expect(clock.tRefUs, t0);
      // 파일에는 그 18ms가 없다 — 파일시각은 pts보다 18ms 앞선다.
      expect(clock.fileTimeUsAt(t0 + 1000000), 1000000 - 18000);
    });

    test('첫 간격이라도 5ms 이하의 흔들림은 구멍이 아니다', () {
      final clock = CaptureClock();
      _feed(clock, t0Us: t0, frames: 30, ptsJumpAt: {1: 4000});
      expect(clock.totalGapUs, 0);
    });

    test('첫 간격이 아니면 18ms는 흔들림이다 (문턱 20ms 그대로)', () {
      final clock = CaptureClock();
      _feed(clock, t0Us: t0, frames: 30, ptsJumpAt: {2: 18000, 12: 18000});
      expect(clock.totalGapUs, 0);
    });

    test('holesInFileRange — 구간 안쪽의 구멍만, 파일 오프셋으로 돌려준다', () {
      final clock = CaptureClock();
      _feed(clock, t0Us: t0, frames: 120, ptsJumpAt: {40: 100000, 80: 250000});
      // 첫 구멍: pts 2.0초 = 파일 2.0초. 둘째: pts 4.1초 = 파일 4.0초(앞 구멍 100ms를 뺀다).
      expect(clock.holesInFileRange(0, 10000000), [
        (fileUs: 2000000, lengthUs: 100000),
        (fileUs: 4000000, lengthUs: 250000),
      ]);
      expect(clock.holesInFileRange(2500000, 10000000), [
        (fileUs: 4000000, lengthUs: 250000),
      ]);
      // 경계에 걸친 구멍은 세지 않는다(조각의 시작·끝 마크가 이미 반영했다).
      expect(clock.holesInFileRange(2000000, 4000000), isEmpty);
      expect(CaptureClock().holesInFileRange(0, 10000000), isEmpty);
    });

    test('장치가 프레임 길이를 정말로 바꾸면 공칭이 따라간다', () {
      final clock = CaptureClock();
      var pts = 0;
      void frame(int lengthUs) {
        clock.addFrame(arrivalUs: t0 + pts + lengthUs, ptsUs: pts);
        pts += lengthUs;
      }

      for (var i = 0; i < 30; i++) {
        frame(50000);
      }
      for (var i = 0; i < 20; i++) {
        frame(100000);
      }
      final settled = clock.totalGapUs;
      for (var i = 0; i < 20; i++) {
        frame(100000);
      }
      expect(clock.nominalFrameUs, 100000);
      // 갇히지 않는다 — 공칭이 바뀐 뒤로는 구멍이 더 쌓이지 않는다.
      expect(clock.totalGapUs, settled);
      expect(settled, lessThanOrEqualTo(8 * 50000));
    });
  });

  group('computeTakeSlice', () {
    test('리드인 300ms, 끝 60ms 트림, 시작 클릭 가드', () {
      final plan = computeTakeSlice(
        startFileMs: 5000,
        endFileMs: 8000,
        songPosAtStartMs: 20000,
        playbackAlreadyRunning: false,
      )!;
      expect(plan.sliceStartMs, 4700);
      expect(plan.sliceEndMs, 7940);
      expect(plan.leadInMs, 300);
      expect(plan.songPositionMs, 20000 - 300 - 15);
      expect(plan.guardFromMs, 260);
      expect(plan.guardToMs, 360);
      expect(plan.durationMs, 3240);
      expect(plan.contentMs, 2940);
      expect(plan.startByte, 4700 * 96);
      expect(plan.endByte, 7940 * 96);
    });

    test('이미 재생 중이던 마크(R 키)는 재생 지연 15ms를 빼지 않는다', () {
      final plan = computeTakeSlice(
        startFileMs: 5000,
        endFileMs: 8000,
        songPosAtStartMs: 20000,
        playbackAlreadyRunning: true,
      )!;
      expect(plan.songPositionMs, 19700);
      expect(plan.songPositionMs + plan.leadInMs, 20000);
    });

    test('불변식 — songPositionMs + leadInMs + L == P0 (속성 테스트)', () {
      final rng = math.Random(99);
      for (var i = 0; i < 2000; i++) {
        final start = rng.nextInt(100000);
        final end = start + 500 + rng.nextInt(20000);
        final p0 = rng.nextBool() ? rng.nextInt(400) : rng.nextInt(300000);
        final running = rng.nextBool();
        final latency = running ? 0 : kPlaybackStartLatencyMs;
        final computed = computeTakeSlice(
          startFileMs: start,
          endFileMs: end,
          songPosAtStartMs: p0,
          playbackAlreadyRunning: running,
        );
        final why = 'start=$start end=$end p0=$p0 running=$running → $computed';
        expect(computed, isNotNull, reason: why);
        final plan = computed!;
        expect(plan.songPositionMs, greaterThanOrEqualTo(0), reason: why);
        expect(plan.leadInMs, inInclusiveRange(0, kArmedLeadInMs), reason: why);
        expect(plan.leadInMs, lessThanOrEqualTo(start), reason: why);
        expect(plan.sliceStartMs, greaterThanOrEqualTo(0), reason: why);
        expect(plan.sliceEndMs, end - kStopClickTrimMs, reason: why);
        if (p0 >= latency) {
          expect(
            plan.songPositionMs + plan.leadInMs + latency,
            p0,
            reason: why,
          );
        }
        // 마크의 곡 좌표는 **언제나** 맞는다(머리를 잘라 맞춘 경우 포함).
        expect(
          plan.songPositionMs + (start - plan.sliceStartMs) + latency,
          p0,
          reason: why,
        );
        expect(plan.guardFromMs, inInclusiveRange(0, plan.durationMs));
        expect(
          plan.guardToMs,
          inInclusiveRange(plan.guardFromMs, plan.durationMs),
        );
      }
    });

    test('클램프 — 세션 시작 직후의 마크는 있는 만큼만 리드인', () {
      final plan = computeTakeSlice(
        startFileMs: 120,
        endFileMs: 3000,
        songPosAtStartMs: 60000,
        playbackAlreadyRunning: false,
      )!;
      expect(plan.sliceStartMs, 0);
      expect(plan.leadInMs, 120);
      expect(plan.songPositionMs, 60000 - 120 - 15);
      expect(plan.guardFromMs, 80);
      expect(plan.guardToMs, 180);

      final tight = computeTakeSlice(
        startFileMs: 20,
        endFileMs: 3000,
        songPosAtStartMs: 60000,
        playbackAlreadyRunning: false,
      )!;
      expect(tight.leadInMs, 20);
      expect(tight.guardFromMs, 0);
      expect(tight.guardToMs, 80);
    });

    test('클램프 — 곡 앞머리에서는 좌표를 눕히지 않고 리드인을 줄인다', () {
      // P0=100: 곡 좌표 0까지 담을 수 있는 리드인은 85ms뿐이다.
      final near = computeTakeSlice(
        startFileMs: 5000,
        endFileMs: 8000,
        songPosAtStartMs: 100,
        playbackAlreadyRunning: false,
      )!;
      expect(near.leadInMs, 85);
      expect(near.songPositionMs, 0);
      expect(near.sliceStartMs, 4915);

      // P0=0(곡 처음에서 스페이스): 조각 t=0을 곡 0에 맞춘다.
      final head = computeTakeSlice(
        startFileMs: 5000,
        endFileMs: 8000,
        songPosAtStartMs: 0,
        playbackAlreadyRunning: false,
      )!;
      expect(head.leadInMs, 0);
      expect(head.songPositionMs, 0);
      expect(head.sliceStartMs, 5015);
      expect(head.guardFromMs, 0);
      expect(head.guardToMs, 45);

      final running = computeTakeSlice(
        startFileMs: 5000,
        endFileMs: 8000,
        songPosAtStartMs: 0,
        playbackAlreadyRunning: true,
      )!;
      expect(running.leadInMs, 0);
      expect(running.sliceStartMs, 5000);
    });

    test('클램프 — 파일이 더 자라지 않으면 끝을 파일 길이로 자른다', () {
      final plan = computeTakeSlice(
        startFileMs: 5000,
        endFileMs: 8000,
        songPosAtStartMs: 20000,
        playbackAlreadyRunning: false,
        fileLengthMs: 7000,
      )!;
      expect(plan.sliceEndMs, 7000);

      // 파일 길이가 넉넉하면 트림한 끝 그대로다.
      final roomy = computeTakeSlice(
        startFileMs: 5000,
        endFileMs: 8000,
        songPosAtStartMs: 20000,
        playbackAlreadyRunning: false,
        fileLengthMs: 9000,
      )!;
      expect(roomy.sliceEndMs, 7940);

      // 마크 뒤로 남은 소리가 없으면 저장할 게 없다.
      expect(
        computeTakeSlice(
          startFileMs: 5000,
          endFileMs: 8000,
          songPosAtStartMs: 20000,
          playbackAlreadyRunning: false,
          fileLengthMs: 5000,
        ),
        isNull,
      );
    });

    test('마크 구간이 500ms 미만이면 null', () {
      TakeSlicePlan? of(int span) => computeTakeSlice(
        startFileMs: 5000,
        endFileMs: 5000 + span,
        songPosAtStartMs: 20000,
        playbackAlreadyRunning: false,
      );
      expect(of(499), isNull);
      expect(of(0), isNull);
      expect(of(-100), isNull);
      final shortest = of(500)!;
      expect(shortest.durationMs, 300 + 500 - 60);
    });

    test('음수 시작점은 0으로 본다', () {
      final plan = computeTakeSlice(
        startFileMs: -30,
        endFileMs: 2000,
        songPosAtStartMs: 20000,
        playbackAlreadyRunning: false,
      )!;
      expect(plan.sliceStartMs, 0);
      expect(plan.leadInMs, 0);
    });
  });

  group('isTimelineSuspect', () {
    test('40ms 넘게 어긋나면 의심', () {
      expect(isTimelineSuspect(openLoopMs: 1000, measuredMs: 1040), isFalse);
      expect(isTimelineSuspect(openLoopMs: 1000, measuredMs: 1041), isTrue);
      expect(isTimelineSuspect(openLoopMs: 1000, measuredMs: 959), isTrue);
      expect(isTimelineSuspect(openLoopMs: 1000, measuredMs: null), isFalse);
    });
  });

  group('buildWavHeader', () {
    test('48k 모노 s16 필드', () {
      final header = buildWavHeader(96000);
      expect(header.length, 44);
      final data = ByteData.sublistView(header);
      String tag(int at) => ascii.decode(header.sublist(at, at + 4));
      expect(tag(0), 'RIFF');
      expect(data.getUint32(4, Endian.little), 36 + 96000);
      expect(tag(8), 'WAVE');
      expect(tag(12), 'fmt ');
      expect(data.getUint32(16, Endian.little), 16);
      expect(data.getUint16(20, Endian.little), 1);
      expect(data.getUint16(22, Endian.little), 1);
      expect(data.getUint32(24, Endian.little), 48000);
      expect(data.getUint32(28, Endian.little), 96000);
      expect(data.getUint16(32, Endian.little), 2);
      expect(data.getUint16(34, Endian.little), 16);
      expect(tag(36), 'data');
      expect(data.getUint32(40, Endian.little), 96000);
    });

    test('스테레오면 블록 크기와 바이트율이 따라간다', () {
      final data = ByteData.sublistView(
        buildWavHeader(0, sampleRate: 44100, channels: 2),
      );
      expect(data.getUint16(22, Endian.little), 2);
      expect(data.getUint32(28, Endian.little), 44100 * 4);
      expect(data.getUint16(32, Endian.little), 4);
    });

    test('음수 크기는 거절한다', () {
      expect(() => buildWavHeader(-1), throwsArgumentError);
    });
  });

  group('shapeTakeEdges', () {
    const plan = TakeSlicePlan(
      sliceStartMs: 4700,
      sliceEndMs: 5700,
      leadInMs: 300,
      songPositionMs: 0,
      guardFromMs: 260,
      guardToMs: 360,
    );
    const guardFrom = 260 * 48;
    const guardTo = 360 * 48;
    const ramp = 5 * 48;
    const total = 1000 * 48;
    const tailFrom = total - 20 * 48;

    test('뮤트 구간의 램프와 끝 페이드가 단조롭다', () {
      final samples = Int16List(total)..fillRange(0, total, 10000);
      shapeTakeEdges(samples, plan);

      // 내려가는 램프 — 구간 안쪽에서 시작해 0으로.
      expect(samples[guardFrom], lessThan(10000));
      for (var i = guardFrom + 1; i < guardFrom + ramp; i++) {
        expect(samples[i], lessThanOrEqualTo(samples[i - 1]));
      }
      expect(samples[guardFrom + ramp - 1], 0);
      // 가운데는 완전 무음.
      for (var i = guardFrom + ramp; i < guardTo - ramp; i++) {
        expect(samples[i], 0);
      }
      // 올라오는 램프.
      expect(samples[guardTo - ramp], 0);
      for (var i = guardTo - ramp + 1; i < guardTo; i++) {
        expect(samples[i], greaterThanOrEqualTo(samples[i - 1]));
      }
      expect(samples[guardTo - 1], inInclusiveRange(9900, 9999));
      // 끝 페이드 — 마지막 샘플은 정확히 0.
      expect(samples[tailFrom], lessThan(10000));
      for (var i = tailFrom + 1; i < total; i++) {
        expect(samples[i], lessThanOrEqualTo(samples[i - 1]));
      }
      expect(samples[total - 1], 0);
    });

    test('구간 밖의 샘플은 한 비트도 건드리지 않는다', () {
      final original = _pattern(1000);
      final samples = Int16List.fromList(original);
      shapeTakeEdges(samples, plan);
      for (var i = 0; i < total; i++) {
        final inGuard = i >= guardFrom && i < guardTo;
        final inTail = i >= tailFrom;
        if (!inGuard && !inTail) {
          expect(samples[i], original[i], reason: 'index $i');
        }
      }
      // 구간 안은 실제로 바뀌었다.
      expect(
        samples.sublist(guardFrom + ramp, guardTo - ramp),
        everyElement(0),
      );
    });

    test('음수 샘플도 크기가 단조롭게 준다', () {
      final samples = Int16List(total)..fillRange(0, total, -8000);
      shapeTakeEdges(samples, plan);
      for (var i = tailFrom + 1; i < total; i++) {
        expect(samples[i].abs(), lessThanOrEqualTo(samples[i - 1].abs()));
      }
      expect(samples[tailFrom - 1], -8000);
    });

    test('구간이 조각 처음에 붙어 있으면 내려가는 램프가 없다', () {
      const headPlan = TakeSlicePlan(
        sliceStartMs: 0,
        sliceEndMs: 1000,
        leadInMs: 0,
        songPositionMs: 0,
        guardFromMs: 0,
        guardToMs: 45,
      );
      final samples = Int16List(total)..fillRange(0, total, 10000);
      shapeTakeEdges(samples, headPlan);
      expect(samples[0], 0);
      expect(samples[45 * 48 - ramp - 1], 0);
      expect(samples[45 * 48], 10000);
    });

    test('짧거나 빈 입력에도 죽지 않는다', () {
      shapeTakeEdges(Int16List(0), plan);
      final tiny = Int16List(100)..fillRange(0, 100, 5000);
      shapeTakeEdges(tiny, plan);
      expect(tiny.last, 0);
    });
  });

  group('maxWindowRmsDbfs', () {
    test('무음은 -100, 풀스케일은 0dB 근처', () {
      expect(maxWindowRmsDbfs(Int16List(0)), isNull);
      expect(maxWindowRmsDbfs(Int16List(4800)), -100);
      expect(isSilentTake(maxWindowRmsDbfs(Int16List(4800))), isTrue);
      final full = Int16List(4800)..fillRange(0, 4800, 32767);
      expect(maxWindowRmsDbfs(full), closeTo(0, 0.01));
    });

    test('진폭 0.1 사인은 약 -23dB, 가장 큰 창을 고른다', () {
      final samples = Int16List(48000);
      for (var i = 24000; i < 48000; i++) {
        samples[i] = (3276.8 * math.sin(2 * math.pi * 440 * i / 48000)).round();
      }
      final db = maxWindowRmsDbfs(samples)!;
      expect(db, closeTo(-23.01, 0.1));
      expect(isSilentTake(db), isFalse);
    });
  });

  group('insertSilence', () {
    test('끼울 것이 없으면 같은 목록을 그대로 돌려준다', () {
      final src = _pattern(50);
      expect(identical(insertSilence(src, const []), src), isTrue);
      // 길이 0 이하·음수 위치·끝 너머의 항목은 버린다(이을 소리가 없다).
      expect(
        identical(
          insertSilence(src, const [
            (atMs: 10, lengthMs: 0),
            (atMs: -5, lengthMs: 20),
            (atMs: 50, lengthMs: 20),
            (atMs: 900, lengthMs: 20),
          ]),
          src,
        ),
        isTrue,
      );
    });

    test('그 자리에 0을 끼우고 뒤의 샘플은 그만큼 밀린다', () {
      final src = _pattern(100);
      final out = insertSilence(src, const [(atMs: 40, lengthMs: 10)]);
      expect(out.length, src.length + 10 * 48);
      expect(out.sublist(0, 40 * 48), src.sublist(0, 40 * 48));
      expect(out.sublist(40 * 48, 50 * 48), everyElement(0));
      expect(out.sublist(50 * 48), src.sublist(40 * 48));
      // 원본은 건드리지 않는다.
      expect(src, _pattern(100));
    });

    test('여럿이면 끼우기 **전** 위치 기준으로 차례로 끼운다(순서 무관)', () {
      final src = _pattern(100);
      final out = insertSilence(src, const [
        (atMs: 60, lengthMs: 5),
        (atMs: 20, lengthMs: 10),
      ]);
      expect(out.length, src.length + 15 * 48);
      expect(out.sublist(0, 20 * 48), src.sublist(0, 20 * 48));
      expect(out.sublist(20 * 48, 30 * 48), everyElement(0));
      expect(out.sublist(30 * 48, 70 * 48), src.sublist(20 * 48, 60 * 48));
      expect(out.sublist(70 * 48, 75 * 48), everyElement(0));
      expect(out.sublist(75 * 48), src.sublist(60 * 48));
    });
  });

  group('writeTakeFromSession — 실제 파일', () {
    late Directory tmp;
    late String sessionPath;
    late String outputPath;
    // 마크 1000~2000ms → 세션 파일 700~1940ms를 자른다.
    final plan = computeTakeSlice(
      startFileMs: 1000,
      endFileMs: 2000,
      songPosAtStartMs: 5000,
      playbackAlreadyRunning: false,
    )!;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sp_capture_session_');
      sessionPath = '${tmp.path}/session.pcm';
      outputPath = '${tmp.path}/take.wav';
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    /// 저장된 WAV의 데이터 부분을 샘플로 읽는다.
    Int16List readWavData(String path) {
      final bytes = File(path).readAsBytesSync();
      final data = ByteData.sublistView(bytes);
      expect(data.getUint32(40, Endian.little), bytes.length - 44);
      expect(data.getUint32(4, Endian.little), bytes.length - 8);
      final out = Int16List((bytes.length - 44) ~/ 2);
      for (var i = 0; i < out.length; i++) {
        out[i] = data.getInt16(44 + i * 2, Endian.little);
      }
      return out;
    }

    /// 가드·끝 페이드 밖이 원본과 같은지 본다.
    void expectUntouchedOutsideEdges(Int16List got, int fromMs) {
      final source = _pattern(got.length ~/ 48, fromMs: fromMs);
      final guardFrom = plan.guardFromMs * 48;
      final guardTo = plan.guardToMs * 48;
      final tailFrom = got.length - kTailFadeMs * 48;
      for (var i = 0; i < got.length; i++) {
        if ((i >= guardFrom && i < guardTo) || i >= tailFrom) continue;
        expect(got[i], source[i], reason: 'index $i');
      }
      expect(got.last, 0);
      expect(got[guardFrom + kGuardRampMs * 48], 0);
    }

    test('계획한 구간을 WAV로 쓴다 — .part는 남지 않고 세션은 그대로다', () async {
      File(sessionPath).writeAsBytesSync(_bytesOf(_pattern(3000)));
      final result = await writeTakeFromSession(
        sessionPath: sessionPath,
        plan: plan,
        outputPath: outputPath,
      );
      expect(result.ok, isTrue, reason: result.message);
      expect(result.truncated, isFalse);
      expect(result.writtenMs, 1240);
      expect(result.peakDbfs, isNotNull);
      expect(isSilentTake(result.peakDbfs), isFalse);
      expect(File(outputPath).lengthSync(), 44 + 1240 * 96);
      expect(File('$outputPath.part').existsSync(), isFalse);
      expect(File(sessionPath).lengthSync(), 3000 * 96);
      expectUntouchedOutsideEdges(readWavData(outputPath), 700);
    });

    test('덜 자란 파일은 끝 바이트가 닿을 때까지 기다린다', () async {
      final writer = File(sessionPath).openSync(mode: FileMode.write);
      writer.writeFromSync(_bytesOf(_pattern(800)));
      writer.flushSync();
      // ffmpeg처럼 50ms씩 이어 쓴다.
      var writtenMs = 800;
      final grower = Timer.periodic(const Duration(milliseconds: 15), (_) {
        if (writtenMs >= 2500) return;
        writer.writeFromSync(_bytesOf(_pattern(50, fromMs: writtenMs)));
        writer.flushSync();
        writtenMs += 50;
      });
      try {
        final result = await writeTakeFromSession(
          sessionPath: sessionPath,
          plan: plan,
          outputPath: outputPath,
          waitCap: const Duration(seconds: 5),
        );
        expect(result.ok, isTrue, reason: result.message);
        expect(result.truncated, isFalse);
        expect(result.writtenMs, 1240);
        expectUntouchedOutsideEdges(readWavData(outputPath), 700);
      } finally {
        grower.cancel();
        writer.closeSync();
      }
    });

    test('상한까지 안 자라면 포기하고 있는 데까지 저장한다', () async {
      File(sessionPath).writeAsBytesSync(_bytesOf(_pattern(1500)));
      final watch = Stopwatch()..start();
      final result = await writeTakeFromSession(
        sessionPath: sessionPath,
        plan: plan,
        outputPath: outputPath,
        waitCap: const Duration(milliseconds: 150),
      );
      watch.stop();
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(140));
      expect(watch.elapsedMilliseconds, lessThan(3000));
      expect(result.ok, isTrue, reason: result.message);
      expect(result.truncated, isTrue);
      expect(result.writtenMs, 1500 - 700);
      expect(result.message, contains('800ms'));
      expect(File(outputPath).lengthSync(), 44 + 800 * 96);
      // 끝 페이드는 **실제로 쓴 끝**에 걸린다.
      expectUntouchedOutsideEdges(readWavData(outputPath), 700);
    });

    test('기본 상한(500ms)에서도 포기한다', () async {
      File(sessionPath).writeAsBytesSync(_bytesOf(_pattern(1500)));
      final watch = Stopwatch()..start();
      final result = await writeTakeFromSession(
        sessionPath: sessionPath,
        plan: plan,
        outputPath: outputPath,
      );
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(490));
      expect(result.truncated, isTrue);
    });

    test('세션 파일이 없으면 실패 — 출력도 .part도 남기지 않는다', () async {
      final result = await writeTakeFromSession(
        sessionPath: sessionPath,
        plan: plan,
        outputPath: outputPath,
      );
      expect(result.ok, isFalse);
      expect(result.message, contains('세션 파일이 없습니다'));
      expect(File(outputPath).existsSync(), isFalse);
      expect(File('$outputPath.part').existsSync(), isFalse);
    });

    test('조각 시작점까지도 안 자랐으면 실패', () async {
      File(sessionPath).writeAsBytesSync(_bytesOf(_pattern(600)));
      final result = await writeTakeFromSession(
        sessionPath: sessionPath,
        plan: plan,
        outputPath: outputPath,
        waitCap: const Duration(milliseconds: 50),
      );
      expect(result.ok, isFalse);
      expect(File(outputPath).existsSync(), isFalse);
      expect(File('$outputPath.part').existsSync(), isFalse);
      expect(File(sessionPath).existsSync(), isTrue);
    });

    test('쓸 수 없는 출력 경로면 실패를 돌려준다(예외로 새지 않는다)', () async {
      File(sessionPath).writeAsBytesSync(_bytesOf(_pattern(3000)));
      final result = await writeTakeFromSession(
        sessionPath: sessionPath,
        plan: plan,
        outputPath: '${tmp.path}/no_such_dir/take.wav',
      );
      expect(result.ok, isFalse);
      expect(result.message, contains('저장하지 못했습니다'));
      expect(File(sessionPath).lengthSync(), 3000 * 96);
    });

    test('🔴 pts 구멍 자리에 무음을 끼운다 — 길이가 늘고 구멍 뒤 소리가 제자리에 놓인다', () async {
      // 조각 도중에 장치가 100ms를 흘렸다. 세션 파일은 그만큼 짧게 이어져 있어서,
      // 그대로 자르면 구멍 뒤의 보컬이 반주보다 100ms 일찍 나오고 길이도 100ms 짧다.
      File(sessionPath).writeAsBytesSync(_bytesOf(_pattern(3000)));
      final result = await writeTakeFromSession(
        sessionPath: sessionPath,
        plan: plan,
        outputPath: outputPath,
        fills: const [(atMs: 800, lengthMs: 100)],
      );
      expect(result.ok, isTrue, reason: result.message);
      expect(result.truncated, isFalse);
      expect(result.filledMs, 100);
      expect(result.writtenMs, 1240 + 100);
      expect(result.message, contains('무음으로 메웠습니다'));
      expect(File(outputPath).lengthSync(), 44 + 1340 * 96);

      final got = readWavData(outputPath);
      final source = _pattern(1240, fromMs: 700);
      final guardTo = plan.guardToMs * 48;
      // 구멍 앞은 원본 그대로.
      expect(got.sublist(guardTo, 800 * 48), source.sublist(guardTo, 800 * 48));
      // 구멍은 무음.
      expect(got.sublist(800 * 48, 900 * 48), everyElement(0));
      // 구멍 뒤는 100ms 밀려 놓인다(끝 페이드 구간은 빼고 본다).
      final tail = kTailFadeMs * 48;
      expect(
        got.sublist(900 * 48, got.length - tail),
        source.sublist(800 * 48, source.length - tail),
      );
      expect(got.last, 0);
    });

    test('끼울 구멍이 없으면 결과가 예전과 같다', () async {
      File(sessionPath).writeAsBytesSync(_bytesOf(_pattern(3000)));
      final result = await writeTakeFromSession(
        sessionPath: sessionPath,
        plan: plan,
        outputPath: outputPath,
        fills: const [],
      );
      expect(result.filledMs, 0);
      expect(result.writtenMs, 1240);
      expect(result.message, '조각을 저장했습니다.');
    });

    test('같은 이름의 출력이 있으면 바꿔 쓴다', () async {
      File(sessionPath).writeAsBytesSync(_bytesOf(_pattern(3000)));
      File(outputPath).writeAsStringSync('old');
      final result = await writeTakeFromSession(
        sessionPath: sessionPath,
        plan: plan,
        outputPath: outputPath,
      );
      expect(result.ok, isTrue, reason: result.message);
      expect(File(outputPath).lengthSync(), 44 + 1240 * 96);
    });

    test('waitUntilBytes — 이미 찼으면 바로, 아니면 상한에서 본 길이를 돌려준다', () async {
      File(sessionPath).writeAsBytesSync(Uint8List(1000));
      final file = await File(sessionPath).open();
      try {
        final quick = Stopwatch()..start();
        expect(await waitUntilBytes(file, 1000), 1000);
        expect(quick.elapsedMilliseconds, lessThan(200));

        final slow = Stopwatch()..start();
        expect(
          await waitUntilBytes(
            file,
            5000,
            cap: const Duration(milliseconds: 120),
          ),
          1000,
        );
        expect(slow.elapsedMilliseconds, greaterThanOrEqualTo(110));
      } finally {
        await file.close();
      }
    });
  });

  group('isSessionStalled', () {
    test('프로세스 종료는 그 자체로 멈춤', () {
      expect(
        isSessionStalled(processExited: true, rmsGapMs: 0, stagnantTicks: 0),
        isTrue,
      );
    });

    test('살아 있으면 레벨 공백과 파일 정체가 둘 다 보여야 한다', () {
      bool stalled(int gap, int ticks) => isSessionStalled(
        processExited: false,
        rmsGapMs: gap,
        stagnantTicks: ticks,
      );
      expect(stalled(600, 2), isTrue);
      expect(stalled(5000, 1), isFalse); // UI가 밀렸을 뿐 파일은 자란다
      expect(stalled(599, 9), isFalse);
      expect(stalled(0, 0), isFalse);
    });
  });

  group('SessionSidecar', () {
    const open = SessionTakeMark(
      startFileMs: 9000,
      songPosAtStartMs: 61000,
      playbackAlreadyRunning: true,
      context: {'songId': 's1', 'slot': 'mr', 'pitch': -2, 'tempo': 1.0},
    );
    const done = SessionTakeMark(
      startFileMs: 1000,
      endFileMs: 3500,
      songPosAtStartMs: 20000,
      context: {'songId': 's1', 'activeAudioPath': 'C:/a b/반주.mp3'},
    );
    const sidecar = SessionSidecar(
      sessionId: 'sess-1',
      deviceName: '마이크(RØDE NT-USB Mini)',
      gain: 1.5,
      startedAtIso: '2026-09-22T21:00:00.000',
      openTake: open,
      pending: [done],
    );

    test('JSON 왕복', () {
      final back = SessionSidecar.tryDecode(sidecar.encode())!;
      expect(back.sessionId, 'sess-1');
      expect(back.deviceName, '마이크(RØDE NT-USB Mini)');
      expect(back.gain, 1.5);
      expect(back.startedAtIso, '2026-09-22T21:00:00.000');
      expect(back.openTake!.startFileMs, 9000);
      expect(back.openTake!.endFileMs, isNull);
      expect(back.openTake!.isOpen, isTrue);
      expect(back.openTake!.songPosAtStartMs, 61000);
      expect(back.openTake!.playbackAlreadyRunning, isTrue);
      expect(back.openTake!.context['pitch'], -2);
      expect(back.pending, hasLength(1));
      expect(back.pending.single.endFileMs, 3500);
      expect(back.pending.single.playbackAlreadyRunning, isFalse);
      expect(back.pending.single.context['activeAudioPath'], 'C:/a b/반주.mp3');
      expect(back.hasUnsaved, isTrue);
    });

    test('빠진 필드는 기본값으로 읽는다', () {
      final empty = SessionSidecar.fromJson(const {});
      expect(empty.sessionId, '');
      expect(empty.deviceName, '');
      expect(empty.gain, 1.0);
      expect(empty.openTake, isNull);
      expect(empty.pending, isEmpty);
      expect(empty.hasUnsaved, isFalse);

      final partial = SessionSidecar.tryDecode(
        '{"sessionId":"x","openTake":{"startFileMs":1200}}',
      )!;
      expect(partial.openTake!.startFileMs, 1200);
      expect(partial.openTake!.songPosAtStartMs, 0);
      expect(partial.openTake!.playbackAlreadyRunning, isFalse);
      expect(partial.openTake!.context, isEmpty);
    });

    test('형이 틀린 값·쓰레기 항목에도 죽지 않는다', () {
      final odd = SessionSidecar.tryDecode(
        '{"sessionId":7,"gain":"loud","deviceName":null,'
        '"openTake":"nope","pending":[1,null,{"endFileMs":5},'
        '{"startFileMs":1000.0,"endFileMs":2500.4,"context":[1,2]}]}',
      )!;
      expect(odd.sessionId, '');
      expect(odd.gain, 1.0);
      expect(odd.openTake, isNull);
      // 시작점이 없는 항목은 자를 수 없으니 버린다.
      expect(odd.pending, hasLength(1));
      expect(odd.pending.single.startFileMs, 1000);
      expect(odd.pending.single.endFileMs, 2500);
      expect(odd.pending.single.context, isEmpty);

      expect(SessionSidecar.tryDecode('{"pending":"x"}')!.pending, isEmpty);
      expect(SessionSidecar.tryDecode('{"gain":-3}')!.gain, 1.0);
    });

    test('깨진 JSON·맵이 아닌 JSON은 null', () {
      expect(SessionSidecar.tryDecode('{"sessionId":"x","pend'), isNull);
      expect(SessionSidecar.tryDecode(''), isNull);
      expect(SessionSidecar.tryDecode('[1,2]'), isNull);
    });

    test('복구 구간 — 열린 조각의 끝은 파일 길이로 닫는다', () {
      final spans = sidecar.spansToRecover(12345);
      expect(spans, hasLength(2));
      expect(spans[0].startFileMs, 1000);
      expect(spans[0].endFileMs, 3500);
      expect(spans[1].startFileMs, 9000);
      expect(spans[1].endFileMs, 12345);
      expect(spans[1].context['songId'], 's1');
      expect(spans[1].playbackAlreadyRunning, isTrue);
    });

    test('🔴 생존 표시 — 열린 조각의 끝을 「마지막 생존 + 여유」로 묶는다', () {
      // 앱이 죽어도 고아 ffmpeg는 -t 상한(45분)까지 계속 쓴다. 끝을 파일 길이로
      // 닫으면 머리 몇 초만 노래인 45분짜리 「복구됨」 테이크가 나온다.
      const alive = SessionSidecar(
        sessionId: 'sess-2',
        openTake: open,
        pending: [done],
        aliveFileMs: 11000,
      );
      final spans = alive.spansToRecover(2700000);
      expect(spans, hasLength(2));
      expect(
        spans[1].endFileMs,
        11000 + kSidecarHeartbeatMs + kSidecarAliveSlackMs,
      );
      // 끝이 찍힌 구간은 그대로다.
      expect(spans[0].endFileMs, 3500);
      // 세션이 먼저 죽어 파일이 더 짧으면 파일 길이.
      expect(alive.spansToRecover(12000)[1].endFileMs, 12000);

      // JSON 왕복·copyWith에 살아남는다.
      expect(SessionSidecar.tryDecode(alive.encode())!.aliveFileMs, 11000);
      expect(alive.copyWith(clearOpenTake: true).aliveFileMs, 11000);
      // 옛 사이드카에는 키가 없다 — null로 읽고, 끝은 예전처럼 파일 길이다.
      final old = SessionSidecar.tryDecode(sidecar.encode())!;
      expect(old.aliveFileMs, isNull);
      expect(old.spansToRecover(2700000)[1].endFileMs, 2700000);
      expect(
        (jsonDecode(sidecar.encode()) as Map<String, Object?>).containsKey(
          'aliveFileMs',
        ),
        isFalse,
      );
    });

    test('copyWith — 열린 조각을 비우고 대기 구간을 바꾼다', () {
      final closed = sidecar.copyWith(
        clearOpenTake: true,
        pending: [done, open.closedAt(9900)],
      );
      expect(closed.openTake, isNull);
      expect(closed.pending, hasLength(2));
      expect(closed.pending.last.endFileMs, 9900);
      expect(closed.sessionId, 'sess-1');
      expect(sidecar.copyWith().openTake, same(open));

      final drained = closed.copyWith(pending: const []);
      expect(drained.hasUnsaved, isFalse);
    });

    test('JSON 형태 — 열린 조각에는 endFileMs 키가 없다', () {
      final json = jsonDecode(sidecar.encode()) as Map<String, Object?>;
      final openJson = json['openTake']! as Map<String, Object?>;
      expect(openJson.containsKey('endFileMs'), isFalse);
      expect(openJson['startFileMs'], 9000);
      expect(json['pending']! as List<Object?>, hasLength(1));
    });
  });

  group('inputLevelBucket', () {
    test('없음 / 작음 / 좋음', () {
      expect(inputLevelBucket(null), InputLevelBucket.none);
      expect(inputLevelBucket(double.nan), InputLevelBucket.none);
      expect(inputLevelBucket(-100), InputLevelBucket.none);
      expect(inputLevelBucket(kSilentTakeDbfs - 0.1), InputLevelBucket.none);
      expect(inputLevelBucket(kSilentTakeDbfs), InputLevelBucket.low);
      expect(inputLevelBucket(-60), InputLevelBucket.low);
      expect(inputLevelBucket(-45.1), InputLevelBucket.low);
      expect(inputLevelBucket(-45), InputLevelBucket.good);
      expect(inputLevelBucket(-12), InputLevelBucket.good);
    });

    test('한국어 문구 — 색이 아니라 말로', () {
      expect(InputLevelBucket.none.label, '입력 없음');
      expect(InputLevelBucket.low.label, '입력 작음');
      expect(InputLevelBucket.good.label, '입력 좋음');
    });
  });
}
