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

  /// 이 플랫폼에 아예 없는 화면 — 목록에서 뺀다. '(꺼짐)' 라벨을 붙이는
  /// [disabled]와 다르다: 저건 설정에서 켤 수 있고 이건 켤 방법이 없다.
  /// 켤 수 없는 탭이 자리만 지키면 사용자는 켜는 방법을 찾아 헤맨다.
  /// null이면 플랫폼 기본값([unavailableDestinations])을 쓴다.
  final Set<AppDestination>? unavailable;

  const AppTopNavBar({
    super.key,
    required this.destination,
    required this.onDestinationChanged,
    this.disabled = const {},
    this.onDisabledTap,
    this.unavailable,
  });

  @override
  Widget build(BuildContext context) {
    final hidden = unavailable ?? unavailableDestinations;
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
            const Icon(
              Icons.mic_external_on,
              color: AppColors.primary,
              size: 26,
            ),
            const SizedBox(width: 8),
            Text('SingPromfter', style: AppTypography.listTitle),
            const SizedBox(width: 16),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  // 목적지 목록을 순회해 만든다 — 화면이 늘어도 여기는 그대로다.
                  children: AppDestination.values
                      .where((d) => !hidden.contains(d))
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
    // 비활성 상태는 투명도가 아니라 글자로 알린다 — '작곡(꺼짐)'처럼 라벨에
    // 병기해야 저시력에서도 탭의 존재가 보인다(투명도 0.4만 쓰던 초판은
    // 어두운 배경에서 탭이 사라져 보였다). 흐림은 보조 신호로만 약하게.
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Semantics(
        label: enabled ? label : '$label (로컬AI 꺼짐 — 설정에서 켜기)',
        button: true,
        selected: selected,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.75,
          child: TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              minimumSize: const Size(72, AppConstants.minTouchTarget),
              backgroundColor: selected
                  ? AppColors.selectedSurface
                  : Colors.transparent,
              foregroundColor: selected
                  ? AppColors.primary
                  : AppColors.onSurfaceVariant,
              shape: RoundedRectangleBorder(
                borderRadius: AppShapes.controlRadius,
              ),
              side: selected
                  ? const BorderSide(
                      color: AppColors.primaryContainer,
                      width: 2,
                    )
                  : BorderSide.none,
            ),
            child: Text(
              enabled ? label : '$label(꺼짐)',
              style: AppTypography.body.copyWith(
                color: selected
                    ? AppColors.primary
                    : AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
