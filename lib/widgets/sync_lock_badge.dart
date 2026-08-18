// file: lib/widgets/sync_lock_badge.dart
//
// 싱크 잠금(L) 상태 배지 — 프롬프터 우측 끝에 작은 자물쇠 하나로 띄운다.
// "L이 눌렸는지 확인이 어렵다"는 실사용 요청에서 시작했지만, 자물쇠+글자
// 배지는 덩치가 커서 가사를 가린다는 피드백이 뒤따랐다. 그래서 글자를
// 걷어내고 아이콘만 남긴다 — 저시력 기준은 색이 아닌 모양(자물쇠)과
// 테두리가 지키고, 뜻은 툴팁/스크린리더 라벨이 말한다.
// 잠금이 아니면 아무것도 없다.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SyncLockBadge extends StatelessWidget {
  final ValueListenable<bool> locked;

  const SyncLockBadge({super.key, required this.locked});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: locked,
      builder: (context, value, _) {
        if (!value) return const SizedBox.shrink();
        return Semantics(
          label: '싱크 잠금 중 — L로 해제',
          child: Tooltip(
            message: '싱크 잠금 중 — L로 해제',
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.elevated.withValues(alpha: 0.92),
                border: Border.all(color: AppColors.tertiary, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.lock,
                size: 22,
                color: AppColors.tertiary,
              ),
            ),
          ),
        );
      },
    );
  }
}
