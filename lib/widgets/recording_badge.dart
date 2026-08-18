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
        if (!value) return const SizedBox.shrink();
        return Semantics(
          label: '녹음 중 — R로 중지',
          child: Tooltip(
            message: '녹음 중 — R로 중지',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
