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
  final VoidCallback onAddSong;

  const AppTopNavBar({
    super.key,
    required this.destination,
    required this.onDestinationChanged,
    required this.onAddSong,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainer,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
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
                  children: [
                    _TopNavTab(
                      label: '홈',
                      selected: destination == AppDestination.home,
                      onTap: () => onDestinationChanged(AppDestination.home),
                    ),
                    _TopNavTab(
                      label: '곡 검색',
                      selected: destination == AppDestination.search,
                      onTap: () => onDestinationChanged(AppDestination.search),
                    ),
                    _TopNavTab(
                      label: '즐겨찾기',
                      selected: destination == AppDestination.favorites,
                      onTap: () =>
                          onDestinationChanged(AppDestination.favorites),
                    ),
                    _TopNavTab(
                      label: '설정',
                      selected: destination == AppDestination.settings,
                      onTap: () =>
                          onDestinationChanged(AppDestination.settings),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onAddSong,
              icon: const Icon(Icons.library_add),
              label: const Text('곡 등록'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: AppColors.onPrimaryContainer,
                minimumSize: const Size(112, AppConstants.minTouchTarget),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopNavTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TopNavTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Semantics(
        label: label,
        button: true,
        selected: selected,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            minimumSize: const Size(72, AppConstants.minTouchTarget),
            backgroundColor:
                selected ? AppColors.selectedSurface : Colors.transparent,
            foregroundColor:
                selected ? AppColors.primary : AppColors.onSurfaceVariant,
            shape: RoundedRectangleBorder(borderRadius: AppShapes.controlRadius),
            side: selected
                ? const BorderSide(color: AppColors.primaryContainer, width: 2)
                : BorderSide.none,
          ),
          child: Text(
            label,
            style: AppTypography.body.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
