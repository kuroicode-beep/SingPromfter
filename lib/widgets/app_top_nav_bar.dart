// file: lib/widgets/app_top_nav_bar.dart
//
// 상단 로고·탭·곡 등록 버튼을 한 줄로 제공하는 메인 네비게이션 바.
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/app_destination.dart';
import '../theme/app_theme.dart';

class AppTopNavBar extends StatelessWidget {
  final AppDestination destination;
  final ValueChanged<AppDestination> onDestinationChanged;

  /// 비활성 탭 — 보이되 흐리게, 눌러도 이동하지 않는다(누르면 안내 콜백).
  /// 로컬AI가 꺼졌을 때 작곡 탭이 여기에 들어간다.
  final Set<AppDestination> disabled;
  final ValueChanged<AppDestination>? onDisabledTap;

  const AppTopNavBar({
    super.key,
    required this.destination,
    required this.onDestinationChanged,
    this.disabled = const {},
    this.onDisabledTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainer,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.outline)),
        ),
        child: Row(
          children: [
            const Icon(Icons.mic_external_on, color: AppColors.primary, size: 26),
            const SizedBox(width: 8),
            Text('SingPromfter', style: AppTypography.listTitle),
            const SizedBox(width: 16),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  // 목적지 목록을 순회해 만든다 — 화면이 늘어도 여기는 그대로다.
                  children: AppDestination.values
                      .map(
                        (d) => _TopNavTab(
                          label: d.label,
                          selected: destination == d,
                          enabled: !disabled.contains(d),
                          onTap: disabled.contains(d)
                              ? () => onDisabledTap?.call(d)
                              : () => onDestinationChanged(d),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
            // 곡 추가는 v2.10.0에서 조작판(하단)으로 이동 — 시선과 손이
            // 머무는 곳으로. 상단은 탭 이동만 남긴다.
          ],
        ),
      ),
    );
  }
}

class _TopNavTab extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _TopNavTab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    // 비활성은 흐림(0.4)으로 표시하되, 탭 자체는 눌러져 안내 스낵바가 뜬다 —
    // "왜 안 되는지"를 색이 아니라 글자로도 알려주기 위해서다.
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Semantics(
        label: enabled ? label : '$label (로컬AI 꺼짐 — 사용 불가)',
        button: true,
        selected: selected,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.4,
          child: TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              minimumSize: const Size(72, AppConstants.minTouchTarget),
              backgroundColor:
                  selected ? AppColors.selectedSurface : Colors.transparent,
              foregroundColor:
                  selected ? AppColors.primary : AppColors.onSurfaceVariant,
              shape:
                  RoundedRectangleBorder(borderRadius: AppShapes.controlRadius),
              side: selected
                  ? const BorderSide(color: AppColors.primaryContainer, width: 2)
                  : BorderSide.none,
            ),
            child: Text(
              label,
              style: AppTypography.body.copyWith(
                color:
                    selected ? AppColors.primary : AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
