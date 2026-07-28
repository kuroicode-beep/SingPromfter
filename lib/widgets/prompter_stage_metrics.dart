// file: lib/widgets/prompter_stage_metrics.dart
//
// 무대(전체화면 프롬프터) 영역 배분 계산. 순수 함수만 둔다.
//
// v2.6.0 이전에는 EQ 미터를 Stack에 고정 좌표로 얹어 두고 하단 바 높이를
// 상수로 어림잡았는데, 실제로는 하단 바가 미터를 덮어 막대가 보이지 않았다.
// 이제 미터가 쓸 "밴드" 높이를 여기서 계산해 가사 뷰포트를 그만큼 줄인다 —
// 겹침 여부를 눈대중이 아니라 수식으로 보장하고 테스트로 고정한다.
import 'dart:ui' show Size;

class PrompterStageMetrics {
  PrompterStageMetrics._();

  /// EQ 밴드(미터가 차지하는 하단 띠) 높이 한계.
  static const double bandMinHeight = 56;
  static const double bandMaxHeight = 160;
  static const double bandHeightRatio = 0.16;

  /// 밴드 안에서 미터가 쓰는 여백.
  static const double meterInsetLeft = 16;
  static const double meterInsetVertical = 8;

  static const double meterMinWidth = 180;
  static const double meterMaxWidth = 520;
  static const double meterWidthRatio = 0.30;

  /// 가사 뷰포트가 비워 줘야 하는 하단 띠 높이. 미터를 끄면 0.
  static double bandHeight(Size stage, {required bool showEq}) {
    if (!showEq) return 0;
    if (stage.height <= 0) return 0;
    return (stage.height * bandHeightRatio).clamp(
      bandMinHeight,
      bandMaxHeight,
    );
  }

  /// 밴드 안에 들어가는 미터 크기. 밴드보다 커지지 않는다.
  static Size meterSize(Size stage, {required bool showEq}) {
    final band = bandHeight(stage, showEq: showEq);
    if (band <= 0) return Size.zero;
    final height = band - meterInsetVertical * 2;
    if (height <= 0) return Size.zero;
    final maxWidth = stage.width - meterInsetLeft * 2;
    if (maxWidth <= 0) return Size.zero;
    final width = (stage.width * meterWidthRatio)
        .clamp(meterMinWidth, meterMaxWidth)
        .clamp(0.0, maxWidth);
    return Size(width, height);
  }
}
