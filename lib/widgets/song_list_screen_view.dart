// file: lib/widgets/song_list_screen_view.dart
//
// SongListScreen의 네비 레일·반응형 3열 홈·검색/설정 화면을 렌더링한다.
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/app_destination.dart';
import '../models/song.dart';
import '../theme/app_theme.dart';
import 'app_nav_rail.dart';
import 'home_now_playing_bar.dart';

class SongListScreenView extends StatelessWidget {
  final bool loading;
  final AppDestination destination;
  final ValueChanged<AppDestination> onDestinationChanged;
  final VoidCallback onAddSong;
  final Song? selectedSong;
  final int? selectedTrackSlot;
  final bool playing;
  final VoidCallback? onStartPrompter;
  final Widget homeSongListPanel;
  final Widget favoritesSongListPanel;
  final Widget prompterPanel;
  final Widget queuePanel;
  final Widget searchPanel;
  final Widget settingsPanel;

  const SongListScreenView({
    super.key,
    required this.loading,
    required this.destination,
    required this.onDestinationChanged,
    required this.onAddSong,
    required this.selectedSong,
    required this.selectedTrackSlot,
    required this.playing,
    required this.onStartPrompter,
    required this.homeSongListPanel,
    required this.favoritesSongListPanel,
    required this.prompterPanel,
    required this.queuePanel,
    required this.searchPanel,
    required this.settingsPanel,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final expanded =
                  MediaQuery.sizeOf(context).width >=
                  AppConstants.wideLayoutBreakpoint;
              return AppNavRail(
                destination: destination,
                expanded: expanded,
                onDestinationChanged: onDestinationChanged,
                onAddSong: onAddSong,
              );
            },
          ),
          Expanded(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final wide =
                          constraints.maxWidth >=
                          AppConstants.wideLayoutBreakpoint;
                      return _buildDestinationBody(wide);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDestinationBody(bool wide) {
    switch (destination) {
      case AppDestination.search:
        return searchPanel;
      case AppDestination.settings:
        return settingsPanel;
      case AppDestination.favorites:
        return _buildHomeBody(wide, favoritesSongListPanel);
      case AppDestination.home:
        return _buildHomeBody(wide, homeSongListPanel);
    }
  }

  Widget _buildHomeBody(bool wide, Widget songListPanel) {
    final nowPlayingBar = HomeNowPlayingBar(
      song: selectedSong,
      selectedTrackSlot: selectedTrackSlot,
      playing: playing,
      onStartPrompter: onStartPrompter,
    );

    if (wide) {
      return Column(
        children: [
          nowPlayingBar,
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: AppConstants.homeSongListWidth,
                  child: songListPanel,
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: prompterPanel,
                ),
                const VerticalDivider(width: 1, thickness: 1),
                SizedBox(
                  width: AppConstants.homeQueueWidth,
                  child: queuePanel,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          nowPlayingBar,
          Material(
            color: AppColors.surfaceContainer,
            child: TabBar(
              labelStyle: AppTypography.body.copyWith(fontWeight: FontWeight.w700),
              unselectedLabelStyle: AppTypography.body,
              indicatorColor: AppColors.primaryContainer,
              tabs: const [
                Tab(text: '곡 목록'),
                Tab(text: '프롬pter'),
                Tab(text: '예약 큐'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                songListPanel,
                prompterPanel,
                queuePanel,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
