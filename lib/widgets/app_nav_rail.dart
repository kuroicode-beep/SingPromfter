// file: lib/widgets/app_nav_rail.dart
//
// 좌측 고정 네비게이션 레일. 앱 섹션 전환과 곡 등록 진입을 제공한다.
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/app_destination.dart';
import '../theme/app_theme.dart';

class AppNavRail extends StatelessWidget {
  final AppDestination destination;
  final bool expanded;
  final ValueChanged<AppDestination> onDestinationChanged;
  final VoidCallback onAddSong;

  const AppNavRail({
    super.key,
    required this.destination,
    required this.expanded,
    required this.onDestinationChanged,
    required this.onAddSong,
  });

  @override
  Widget build(BuildContext context) {
    final width = expanded
        ? AppConstants.navRailExpandedWidth
        : AppConstants.navRailCollapsedWidth;

    return Material(
      color: AppColors.surfaceContainer,
      child: Container(
        width: width,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: AppColors.outline)),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  expanded ? 16 : 8,
                  16,
                  expanded ? 16 : 8,
                  12,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.mic_external_on,
                      color: AppColors.primary,
                      size: 28,
                    ),
                    if (expanded) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'SingPromfter',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.listTitle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1),
              _NavItem(
                expanded: expanded,
                destination: AppDestination.home,
                selected: destination == AppDestination.home,
                icon: Icons.home_outlined,
                selectedIcon: Icons.home,
                label: '홈',
                onTap: () => onDestinationChanged(AppDestination.home),
              ),
              _NavItem(
                expanded: expanded,
                destination: AppDestination.search,
                selected: destination == AppDestination.search,
                icon: Icons.search,
                selectedIcon: Icons.search,
                label: '곡 검색',
                onTap: () => onDestinationChanged(AppDestination.search),
              ),
              _NavItem(
                expanded: expanded,
                destination: AppDestination.favorites,
                selected: destination == AppDestination.favorites,
                icon: Icons.star_outline,
                selectedIcon: Icons.star,
                label: '즐겨찾기',
                onTap: () => onDestinationChanged(AppDestination.favorites),
              ),
              _NavItem(
                expanded: expanded,
                destination: AppDestination.settings,
                selected: destination == AppDestination.settings,
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings,
                label: '설정',
                onTap: () => onDestinationChanged(AppDestination.settings),
              ),
              const Spacer(),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  expanded ? 12 : 8,
                  8,
                  expanded ? 12 : 8,
                  16,
                ),
                child: expanded
                    ? FilledButton.icon(
                        onPressed: onAddSong,
                        icon: const Icon(Icons.library_add),
                        label: const Text('곡 등록'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryContainer,
                          foregroundColor: AppColors.onPrimaryContainer,
                          minimumSize: const Size(double.infinity, 50),
                        ),
                      )
                    : FilledButton(
                        onPressed: onAddSong,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryContainer,
                          foregroundColor: AppColors.onPrimaryContainer,
                          minimumSize: const Size(50, 50),
                          padding: EdgeInsets.zero,
                        ),
                        child: const Icon(Icons.library_add),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final bool expanded;
  final AppDestination destination;
  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;

  const _NavItem({
    required this.expanded,
    required this.destination,
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 50),
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: selected ? AppColors.selectedSurface : Colors.transparent,
              borderRadius: AppShapes.controlRadius,
              border: selected
                  ? const Border(
                      left: BorderSide(
                        color: AppColors.primaryContainer,
                        width: 3,
                      ),
                    )
                  : null,
            ),
            padding: EdgeInsets.fromLTRB(expanded ? 14 : 0, 10, 12, 10),
            child: Row(
              mainAxisAlignment:
                  expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  color: selected ? AppColors.primary : AppColors.onSurfaceVariant,
                  size: 24,
                ),
                if (expanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: AppTypography.body.copyWith(
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected
                            ? AppColors.onSurface
                            : AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
