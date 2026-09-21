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
          label: value ? '녹음 중 — R로 중지' : '',
          child: !value
              ? const SizedBox.shrink()
              : Tooltip(
                  message: '녹음 중 — R로 중지',
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
