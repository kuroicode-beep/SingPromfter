// file: lib/widgets/prompter_current_line.dart
//
// 무대 가사 한 줄의 강조 규칙을 혼자 소유한다.
//
// 목록 모드(_LineTile)와 3줄 창 모드(_highlightLine)가 같은 규칙을 각자
// 다른 상수로 그리고 있었다. 한 글자씩 스윕(v2.8.0)은 평범한 Text와 글자
// metrics가 **완전히 같아야** 스윕이 걸리는 순간 줄이 튀지 않는데, 그건
// TextStyle 주인이 하나일 때만 보장된다.
//
// 강조는 색 하나에 기대지 않는다(v2.7.0 피드백): 큰 화살표 + 밑줄 + 배경 띠
// + 크기 차이 + 색. 색을 못 봐도 구분된다.
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 현재 줄이 아닌 줄의 축소 배율. 모드마다 다르다.
const double listMutedScale = 0.72;
const double windowMutedScale = 0.82;

/// 무대 가사 한 줄의 글자 모양.
/// 스윕 페인터도 이 함수가 준 스타일을 그대로 써야 위치가 어긋나지 않는다.
TextStyle prompterLineStyle({
  required double fontSize,
  required double lineHeight,
  required bool boldText,
  required bool isCurrent,
  required Color mutedColor,
  String? fontFamily,
}) {
  return TextStyle(
    fontSize: fontSize,
    height: lineHeight,
    // 무대 가사는 고가독이 최우선. 글꼴 미지정 시 손글씨(브랜드) 대신
    // 고딕(Malgun)으로 폴백해 저시력 가독성을 지킨다.
    fontFamily: fontFamily ?? AppFonts.legible,
    color: isCurrent ? AppColors.tertiary : mutedColor,
    fontWeight: isCurrent
        ? (boldText ? FontWeight.w800 : FontWeight.w700)
        : FontWeight.w500,
    shadows: isCurrent
        ? const [
            Shadow(color: AppColors.tertiary, blurRadius: 18),
            Shadow(color: AppColors.tertiary, blurRadius: 8),
          ]
        : null,
  );
}

/// 아직 부르지 않은 부분의 스타일. **색과 그림자만** 바꾼다.
///
/// 크기·자간·글꼴·굵기가 달라지면 글자 위치가 어긋나 스윕이 흔들린다.
/// 밝은 쪽이 아니라 어두운 쪽을 파생시키는 이유: 스윕이 없는 곡(싱크 가사가
/// 없거나 끝 시각을 모르는 줄)에서 현재 줄이 v2.7.0과 똑같이 보여야 한다.
/// 아직 부르지 않은 부분의 불투명도.
/// 0.45로 시작했다가 "조금 더 밝게" 피드백을 받아 올렸다. 이보다 높이면
/// 부른 부분과의 대비가 약해져 스윕 경계가 눈에 안 띈다.
const double unsungOpacity = 0.62;

TextStyle prompterUnsungStyle(TextStyle base) {
  return base.copyWith(
    color: (base.color ?? AppColors.tertiary).withValues(alpha: unsungOpacity),
    shadows: const [],
  );
}

/// 무대 가사 한 줄. 목록 모드와 3줄 창 모드가 이 위젯을 함께 쓴다.
class PrompterCurrentLine extends StatelessWidget {
  final String text;
  final bool isCurrent;

  /// 현재 줄 기준 크기. 현재 줄이 아니면 [mutedScale]을 곱한다.
  final double fontSize;
  final double mutedScale;
  final double lineHeight;
  final String? fontFamily;
  final bool boldText;
  final Color mutedColor;

  /// 줄 위아래 바깥 여백. 3줄 창은 0, 목록은 글자 크기 비례.
  final EdgeInsets margin;

  /// 본문이 가로를 꽉 채울지(목록) 줄 길이만큼만 차지할지(3줄 창).
  final bool fillWidth;

  final VoidCallback? onTap;

  /// 현재 줄을 스윕으로 그릴 때 쓰는 대체 렌더러.
  /// null이면 평범한 Text. 스타일 인자는 [prompterLineStyle] 결과 그대로다.
  final Widget Function(TextStyle style)? sweepBuilder;

  const PrompterCurrentLine({
    super.key,
    required this.text,
    required this.isCurrent,
    required this.fontSize,
    required this.mutedScale,
    required this.lineHeight,
    required this.boldText,
    required this.mutedColor,
    this.fontFamily,
    this.margin = EdgeInsets.zero,
    this.fillWidth = true,
    this.onTap,
    this.sweepBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final size = isCurrent ? fontSize : fontSize * mutedScale;
    // 좌우 대칭 거터 — 마커가 붙고 떨어져도 본문이 밀리지 않는다.
    final gutter = fontSize * 1.15;
    final style = prompterLineStyle(
      fontSize: size,
      lineHeight: lineHeight,
      boldText: boldText,
      isCurrent: isCurrent,
      mutedColor: mutedColor,
      fontFamily: fontFamily,
    );

    final body = isCurrent && sweepBuilder != null
        ? sweepBuilder!(style)
        : Text(text, textAlign: TextAlign.center, style: style);

    final content = Container(
      margin: margin,
      padding: EdgeInsets.symmetric(vertical: fontSize * 0.1),
      decoration: isCurrent
          ? BoxDecoration(
              color: AppColors.tertiary.withValues(alpha: 0.12),
              border: const Border(
                bottom: BorderSide(color: AppColors.tertiary, width: 4),
              ),
            )
          : null,
      child: Row(
        mainAxisAlignment: fillWidth
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: gutter,
            child: isCurrent
                ? Icon(
                    Icons.play_arrow_rounded,
                    size: fontSize,
                    color: AppColors.tertiary,
                  )
                : null,
          ),
          if (fillWidth) Expanded(child: body) else Flexible(child: body),
          SizedBox(width: gutter),
        ],
      ),
    );

    // 누를 수 없어도 시맨틱은 붙인다 — 스크린 리더가 현재 줄을 알아야 한다.
    return Semantics(
      selected: isCurrent,
      button: onTap != null,
      label: isCurrent ? '현재 줄: $text' : text,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}
