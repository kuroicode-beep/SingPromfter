// file: lib/widgets/recording_badge.dart
//
// 녹음 중(R) 상태 배지 — 프롬프터 우하단에 띄운다.
// 싱크 잠금 배지와 같은 문법: 색이 아니라 ● 모양으로 알리고, 녹음이
// 아니면 아무것도 없다. v5.6.0에서 글자를 빼고 아이콘만 남겼다 —
// 가사를 가리지 않으려는 실사용 요청. 대신 아이콘을 키우고 스크린리더
// 라벨(Semantics)과 호버 안내(Tooltip)를 남겨 인지 수단을 잃지 않는다.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 배지의 스크린리더 라벨·호버 안내.
///
/// 「스페이스」가 들어간 이유: 녹음 고정(Alt+R) 중에는 스페이스가 조각을 끝낸다.
/// R만 적혀 있으면 고정 모드에서 멈추는 법을 잘못 알려 주게 된다.
const String kRecordingBadgeLabel = '녹음 중 — R 또는 스페이스로 중지';

class RecordingBadge extends StatelessWidget {
  final ValueListenable<bool> recording;

  const RecordingBadge({super.key, required this.recording});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: recording,
      builder: (context, value, _) {
        // 🔴 노드를 만들었다 지우지 않는다 — 항상 같은 노드를 두고 라벨만 바꾼다.
        // 켜질 때 생기고 꺼질 때 사라지는 접근성 노드가 Flutter 엔진 크래시를
        // 냈다(2026-09-22, center_alert.dart 머리말 참고).
        return Semantics(
          container: true,
          label: value ? kRecordingBadgeLabel : '',
          child: !value
              // 🔴 크기 0(SizedBox.shrink)이면 안 된다. 빈 사각형의 시맨틱스 노드는
              // 「안 보임」으로 트리에서 빠진다 — 그러면 위의 Semantics를 상시로 둬도
              // 녹음을 켜고 끌 때마다 노드가 생겼다 사라진다(테스트로 확인: 4↔5개).
              // 고정 모드에서는 스페이스마다 이 배지가 뒤집히므로 1px짜리 빈 상자로
              // 노드를 붙들어 둔다. 눈에는 안 보인다.
              ? const SizedBox(width: 1, height: 1)
              : Tooltip(
                  message: kRecordingBadgeLabel,
                  // 툴팁도 자체 노드를 만들지 않게 한다(라벨은 위에서 준다).
                  excludeFromSemantics: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.elevated.withValues(alpha: 0.92),
                      border: Border.all(color: AppColors.danger, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.fiber_manual_record,
                      size: 34,
                      color: AppColors.danger,
                    ),
                  ),
                ),
        );
      },
    );
  }
}
