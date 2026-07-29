import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/widgets/prompter_stage_metrics.dart';

// 무대 영역 배분 — EQ 미터가 가사·하단 바와 겹치지 않음을 수식으로 고정한다.
// (v2.5.0에서는 고정 좌표라 하단 바가 미터를 덮어 막대가 보이지 않았다)
void main() {
  const stages = <String, Size>{
    'HD 1280x720': Size(1280, 720),
    'FHD 1920x1080': Size(1920, 1080),
    '4K 3840x2160': Size(3840, 2160),
    '작은 창 800x480': Size(800, 480),
    '아주 작은 창 640x360': Size(640, 360),
  };

  group('EQ 밴드와 미터', () {
    test('미터는 항상 밴드 안에 들어간다', () {
      stages.forEach((name, stage) {
        final band = PrompterStageMetrics.bandHeight(stage, showEq: true);
        final meter = PrompterStageMetrics.meterSize(stage, showEq: true);
        expect(
          meter.height + PrompterStageMetrics.meterInsetVertical * 2,
          lessThanOrEqualTo(band + 0.001),
          reason: name,
        );
      });
    });

    test('미터가 무대 폭을 넘지 않는다', () {
      stages.forEach((name, stage) {
        final meter = PrompterStageMetrics.meterSize(stage, showEq: true);
        expect(
          meter.width + PrompterStageMetrics.meterInsetLeft * 2,
          lessThanOrEqualTo(stage.width + 0.001),
          reason: name,
        );
      });
    });

    test('밴드가 무대의 1/4을 넘지 않는다 — 가사가 과도하게 좁아지지 않게', () {
      stages.forEach((name, stage) {
        final band = PrompterStageMetrics.bandHeight(stage, showEq: true);
        expect(band, lessThanOrEqualTo(stage.height * 0.25), reason: name);
      });
    });

    test('미터 폭은 상·하한 안에 있다', () {
      stages.forEach((name, stage) {
        final meter = PrompterStageMetrics.meterSize(stage, showEq: true);
        expect(
          meter.width,
          lessThanOrEqualTo(PrompterStageMetrics.meterMaxWidth),
          reason: name,
        );
        // 무대가 아주 좁으면 폭 상한보다 무대 폭이 먼저 걸린다.
        final roomy =
            stage.width - PrompterStageMetrics.meterInsetLeft * 2 >=
            PrompterStageMetrics.meterMinWidth;
        if (roomy) {
          expect(
            meter.width,
            greaterThanOrEqualTo(PrompterStageMetrics.meterMinWidth),
            reason: name,
          );
        }
      });
    });

    test('4K에서는 상한(160)에 걸린다', () {
      final band = PrompterStageMetrics.bandHeight(
        const Size(3840, 2160),
        showEq: true,
      );
      expect(band, PrompterStageMetrics.bandMaxHeight);
    });

    test('아주 낮은 창에서는 하한(56)에 걸린다', () {
      // 300 * 0.16 = 48 → 하한으로 올라간다. (360이면 57.6이라 아직 안 걸린다)
      final band = PrompterStageMetrics.bandHeight(
        const Size(640, 300),
        showEq: true,
      );
      expect(band, PrompterStageMetrics.bandMinHeight);
    });

    test('끄면 밴드도 미터도 0 — 가사가 공간을 전부 회수한다', () {
      stages.forEach((name, stage) {
        expect(
          PrompterStageMetrics.bandHeight(stage, showEq: false),
          0,
          reason: name,
        );
        expect(
          PrompterStageMetrics.meterSize(stage, showEq: false),
          Size.zero,
          reason: name,
        );
      });
    });

    test('높이 0인 퇴화 제약에서도 예외 없이 0을 준다', () {
      expect(
        PrompterStageMetrics.bandHeight(Size.zero, showEq: true),
        0,
      );
      expect(
        PrompterStageMetrics.meterSize(Size.zero, showEq: true),
        Size.zero,
      );
    });
  });

  // 드로어가 여닫히는 동안 밴드가 흔들리면 가사 줄이 통째로 재레이아웃된다.
  group('stableStage', () {
    test('접힌 드로어 높이를 빼 준다', () {
      const stage = Size(1920, 1080);
      expect(
        PrompterStageMetrics.stableStage(stage, hiddenDrawerHeight: 132).height,
        948,
      );
    });

    test('애니메이션 내내 밴드 높이가 상수다', () {
      // 드로어가 접힐수록 무대는 커지고 hidden은 줄어든다 — 합은 늘 같다.
      const openStageHeight = 948.0;
      double bandAt(double progress) {
        final hidden = PrompterStageMetrics.stageDrawerHeight * (1 - progress);
        final stage = Size(1920, openStageHeight + hidden);
        return PrompterStageMetrics.bandHeight(
          PrompterStageMetrics.stableStage(stage, hiddenDrawerHeight: hidden),
          showEq: true,
        );
      }

      final expected = bandAt(1);
      for (final p in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        expect(bandAt(p), closeTo(expected, 0.001), reason: 'progress=$p');
      }
    });

    test('폭은 건드리지 않는다', () {
      expect(
        PrompterStageMetrics.stableStage(
          const Size(1280, 720),
          hiddenDrawerHeight: 132,
        ).width,
        1280,
      );
    });

    test('드로어가 무대보다 크면 0으로 막는다', () {
      expect(
        PrompterStageMetrics.stableStage(
          const Size(1280, 100),
          hiddenDrawerHeight: 400,
        ).height,
        0,
      );
    });
  });
}
