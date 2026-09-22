// file: test/utils/recording_latency_test.dart
//
// 녹음 지연 보정의 순수 부품 — 범위·버튼 한 걸음·표시 글자·부호·R 녹음 좌표 계획.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/utils/recording_latency.dart';

void main() {
  group('clampRecordingLatencyMs', () {
    test('−300…+300으로 묶고 반올림한다', () {
      expect(clampRecordingLatencyMs(0), 0);
      expect(clampRecordingLatencyMs(35), 35);
      expect(clampRecordingLatencyMs(-20), -20);
      expect(clampRecordingLatencyMs(300), 300);
      expect(clampRecordingLatencyMs(301), 300);
      expect(clampRecordingLatencyMs(9999), 300);
      expect(clampRecordingLatencyMs(-300), -300);
      expect(clampRecordingLatencyMs(-301), -300);
      expect(clampRecordingLatencyMs(34.6), 35);
      expect(clampRecordingLatencyMs(double.infinity), 300);
      expect(clampRecordingLatencyMs(double.negativeInfinity), -300);
    });

    test('숫자가 아니면 0 — 옛 설정·깨진 값을 던지지 않고 흡수한다', () {
      expect(clampRecordingLatencyMs(null), 0);
      expect(clampRecordingLatencyMs('120'), 0);
      expect(clampRecordingLatencyMs(true), 0);
      expect(clampRecordingLatencyMs(double.nan), 0);
      expect(clampRecordingLatencyMs(const <String, Object?>{}), 0);
    });
  });

  group('stepRecordingLatencyMs — ± 버튼 한 번', () {
    test('5ms씩 움직인다', () {
      expect(stepRecordingLatencyMs(0, 1), 5);
      expect(stepRecordingLatencyMs(0, -1), -5);
      expect(stepRecordingLatencyMs(35, 1), 40);
      expect(stepRecordingLatencyMs(35, -1), 30);
      expect(stepRecordingLatencyMs(-35, 1), -30);
      expect(stepRecordingLatencyMs(-35, -1), -40);
      expect(kRecordingLatencyStepMs, 5);
    });

    test('격자 밖의 값(손으로 고친 설정)은 가까운 격자로 붙는다', () {
      expect(stepRecordingLatencyMs(33, 1), 35);
      expect(stepRecordingLatencyMs(33, -1), 30);
      expect(stepRecordingLatencyMs(-33, 1), -30);
      expect(stepRecordingLatencyMs(-33, -1), -35);
    });

    test('범위 끝에서 멈춘다', () {
      expect(stepRecordingLatencyMs(300, 1), 300);
      expect(stepRecordingLatencyMs(298, 1), 300);
      expect(stepRecordingLatencyMs(-300, -1), -300);
      expect(stepRecordingLatencyMs(9999, -1), 295);
    });

    test('방향 0은 값을 그대로 둔다(범위만 맞춘다)', () {
      expect(stepRecordingLatencyMs(33, 0), 33);
      expect(stepRecordingLatencyMs(9999, 0), 300);
    });

    test('0에서 +60번이면 최대, 거기서 −120번이면 최소다', () {
      var value = 0;
      for (var i = 0; i < 60; i++) {
        value = stepRecordingLatencyMs(value, 1);
      }
      expect(value, kRecordingLatencyMaxMs);
      for (var i = 0; i < 120; i++) {
        value = stepRecordingLatencyMs(value, -1);
      }
      expect(value, kRecordingLatencyMinMs);
    });
  });

  group('표시 글자 — 색이 아니라 말로', () {
    test('formatRecordingLatencyMs', () {
      expect(formatRecordingLatencyMs(0), '0 ms (보정 없음)');
      expect(formatRecordingLatencyMs(35), '+35 ms');
      expect(formatRecordingLatencyMs(-20), '−20 ms');
      // 버튼이 더 먹지 않는 이유를 글자로 말한다.
      expect(formatRecordingLatencyMs(300), '+300 ms (최대)');
      expect(formatRecordingLatencyMs(-300), '−300 ms (최소)');
      expect(formatRecordingLatencyMs(9999), '+300 ms (최대)');
    });

    test('recordingLatencySemanticsLabel — 기호를 말로 푼다', () {
      expect(recordingLatencySemanticsLabel(0), '0 밀리초, 보정 없음');
      expect(recordingLatencySemanticsLabel(35), '플러스 35 밀리초');
      expect(recordingLatencySemanticsLabel(-20), '마이너스 20 밀리초');
      expect(recordingLatencySemanticsLabel(300), '플러스 300 밀리초, 최대');
      expect(recordingLatencySemanticsLabel(-300), '마이너스 300 밀리초, 최소');
    });
  });

  group('compensateSongPositionMs — 부호가 사는 단 한 곳', () {
    test('양수 보정은 좌표를 앞당기고 음수 보정은 늦춘다', () {
      expect(compensateSongPositionMs(60000, 120), 59880);
      expect(compensateSongPositionMs(60000, -50), 60050);
      expect(compensateSongPositionMs(60000, 0), 60000);
    });

    test('0 밑으로 내려갈 수 있다 — 눕히는 것은 이 함수의 일이 아니다', () {
      expect(compensateSongPositionMs(100, 120), -20);
    });

    test('범위 밖 보정값은 묶어서 쓴다', () {
      expect(compensateSongPositionMs(60000, 9999), 59700);
      expect(compensateSongPositionMs(60000, -9999), 60300);
    });
  });

  group('planRecordedTakeTiming — R 녹음의 좌표', () {
    test('보정 0이면 v5.16.0과 똑같다 — anchor 그대로, 음수는 0', () {
      final mid = planRecordedTakeTiming(
        anchorMs: 20000,
        fallbackPositionMs: 19500,
        durationMs: 8000,
        latencyMs: 0,
      );
      expect(mid.songPositionMs, 20000);
      expect(mid.headTrimMs, 0);
      expect(mid.durationMs, 8000);
      expect(mid.latencyAppliedMs, 0);

      // 재생보다 R을 먼저 누른 녹음 — 예전처럼 0에 눕히고 파일은 건드리지 않는다.
      final early = planRecordedTakeTiming(
        anchorMs: -3000,
        fallbackPositionMs: 0,
        durationMs: 8000,
        latencyMs: 0,
      );
      expect(early.songPositionMs, 0);
      expect(early.headTrimMs, 0);
      expect(early.durationMs, 8000);
      expect(early.latencyAppliedMs, 0);
    });

    test('양수 보정은 좌표를 그만큼 앞당기고, 적용값을 남긴다', () {
      final plan = planRecordedTakeTiming(
        anchorMs: 20000,
        fallbackPositionMs: 19500,
        durationMs: 8000,
        latencyMs: 120,
      );
      expect(plan.songPositionMs, 19880);
      expect(plan.headTrimMs, 0);
      expect(plan.durationMs, 8000);
      expect(plan.latencyAppliedMs, 120);
    });

    test('음수 보정은 좌표를 늦춘다', () {
      final plan = planRecordedTakeTiming(
        anchorMs: 20000,
        fallbackPositionMs: 19500,
        durationMs: 8000,
        latencyMs: -40,
      );
      expect(plan.songPositionMs, 20040);
      expect(plan.latencyAppliedMs, -40);

      // 보정 전에는 0 밑이던 좌표가 음수 보정으로 0 위로 올라오면 그대로 쓴다.
      final lifted = planRecordedTakeTiming(
        anchorMs: -30,
        fallbackPositionMs: 0,
        durationMs: 8000,
        latencyMs: -50,
      );
      expect(lifted.songPositionMs, 20);
      expect(lifted.headTrimMs, 0);
      expect(lifted.latencyAppliedMs, -50);
    });

    test('🔴 곡 첫머리 — 0에 눕히지 않고 모자란 만큼 머리를 자른다', () {
      final plan = planRecordedTakeTiming(
        anchorMs: 80,
        fallbackPositionMs: 0,
        durationMs: 8000,
        latencyMs: 120,
      );
      expect(plan.songPositionMs, 0);
      expect(plan.headTrimMs, 40);
      expect(plan.durationMs, 7960);
      expect(plan.latencyAppliedMs, 120);
    });

    test('자르고 남는 게 0.5초 미만이면 자르지 않고, 옮겨진 만큼만 적는다', () {
      final plan = planRecordedTakeTiming(
        anchorMs: 80,
        fallbackPositionMs: 0,
        durationMs: 530,
        latencyMs: 120,
      );
      expect(plan.songPositionMs, 0);
      expect(plan.headTrimMs, 0);
      expect(plan.durationMs, 530);
      expect(plan.latencyAppliedMs, 80);
    });

    test('파일 가공에 실패해 다시 부르면(canTrimHead: false) 옛 방식으로 물러난다', () {
      final plan = planRecordedTakeTiming(
        anchorMs: 80,
        fallbackPositionMs: 0,
        durationMs: 8000,
        latencyMs: 120,
        canTrimHead: false,
      );
      expect(plan.songPositionMs, 0);
      expect(plan.headTrimMs, 0);
      expect(plan.durationMs, 8000);
      expect(plan.latencyAppliedMs, 80);
    });

    test('anchor가 음수인 녹음은 보정이 있어도 자르지 않는다 — 일부러 먼저 부른 소리일 수 있다', () {
      final plan = planRecordedTakeTiming(
        anchorMs: -3000,
        fallbackPositionMs: 0,
        durationMs: 60000,
        latencyMs: 120,
      );
      expect(plan.songPositionMs, 0);
      expect(plan.headTrimMs, 0);
      expect(plan.durationMs, 60000);
      expect(plan.latencyAppliedMs, 0);
    });

    test('좌표를 못 쟀으면(멈춘 채 녹음) 누른 자리를 그대로 쓰고 보정하지 않는다', () {
      final plan = planRecordedTakeTiming(
        anchorMs: null,
        fallbackPositionMs: 45000,
        durationMs: 8000,
        latencyMs: 120,
      );
      expect(plan.songPositionMs, 45000);
      expect(plan.headTrimMs, 0);
      expect(plan.latencyAppliedMs, 0);

      final negative = planRecordedTakeTiming(
        anchorMs: null,
        fallbackPositionMs: -5,
        durationMs: 8000,
        latencyMs: 120,
      );
      expect(negative.songPositionMs, 0);
    });

    test('불변식 (속성 테스트) — 좌표는 0 이상, 머리를 자르면 계약이 정확히 선다', () {
      final rng = math.Random(517);
      for (var i = 0; i < 3000; i++) {
        final anchor = rng.nextInt(1200) - 400;
        final latency = rng.nextInt(801) - 400;
        final duration = 400 + rng.nextInt(5000);
        final plan = planRecordedTakeTiming(
          anchorMs: anchor,
          fallbackPositionMs: 0,
          durationMs: duration,
          latencyMs: latency,
        );
        final why =
            'anchor=$anchor latency=$latency duration=$duration → $plan';
        final clamped = clampRecordingLatencyMs(latency);
        expect(plan.songPositionMs, greaterThanOrEqualTo(0), reason: why);
        expect(plan.headTrimMs, inInclusiveRange(0, 300), reason: why);
        expect(plan.durationMs, duration - plan.headTrimMs, reason: why);
        if (plan.headTrimMs > 0) {
          expect(
            plan.durationMs,
            greaterThanOrEqualTo(kMinimumTrimmedTakeMs),
            reason: why,
          );
        }
        // 보정이 온전히 구워졌으면: (자른 뒤) 파일 t=0의 참 좌표 == 저장된 좌표.
        if (plan.latencyAppliedMs == clamped && (anchor >= 0 || clamped < 0)) {
          expect(
            plan.songPositionMs,
            anchor - clamped + plan.headTrimMs,
            reason: why,
          );
        }
        // 보정 0이면 옛 동작과 바이트 단위로 같다.
        final legacy = planRecordedTakeTiming(
          anchorMs: anchor,
          fallbackPositionMs: 0,
          durationMs: duration,
          latencyMs: 0,
        );
        expect(legacy.songPositionMs, anchor < 0 ? 0 : anchor, reason: why);
        expect(legacy.headTrimMs, 0, reason: why);
        expect(legacy.latencyAppliedMs, 0, reason: why);
      }
    });
  });
}
