// file: lib/widgets/song_list_screen_view.dart
//
// SongListScreen의 반응형 레이아웃과 곡 등록 버튼을 렌더링한다.
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../theme/app_theme.dart';

class SongListScreenView extends StatelessWidget {
  final bool loading;
  final Widget songListPanel;
  final Widget prompterPanel;
  final VoidCallback onAddSong;
  final VoidCallback onBatchRegister;
  final VoidCallback onExportBackup;
  final VoidCallback onImportBackup;

  const SongListScreenView({
    super.key,
    required this.loading,
    required this.songListPanel,
    required this.prompterPanel,
    required this.onAddSong,
    required this.onBatchRegister,
    required this.onExportBackup,
    required this.onImportBackup,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SingPromfter'),
        actions: [
          IconButton(
            onPressed: onBatchRegister,
            icon: const Icon(Icons.playlist_add),
            tooltip: '일괄 등록',
          ),
          IconButton(
            onPressed: onExportBackup,
            icon: const Icon(Icons.archive_outlined),
            tooltip: '백업 내보내기',
          ),
          IconButton(
            onPressed: onImportBackup,
            icon: const Icon(Icons.unarchive_outlined),
            tooltip: '백업 가져오기',
          ),
        ],
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : LayoutBuilder(
              builder: (_, constraints) {
                final wide =
                    constraints.maxWidth >= AppConstants.wideLayoutBreakpoint;
                if (wide) {
                  return Row(
                    children: [
                      SizedBox(width: 360, child: songListPanel),
                      const VerticalDivider(width: 1),
                      Expanded(child: prompterPanel),
                    ],
                  );
                }

                return Column(
                  children: [
                    Expanded(flex: 5, child: songListPanel),
                    const Divider(height: 1),
                    Expanded(flex: 6, child: prompterPanel),
                  ],
                );
              },
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(top: 8, right: 4),
        child: FloatingActionButton.extended(
          onPressed: onAddSong,
          icon: const Icon(Icons.library_add, size: 18),
          label: const Text('곡 등록'),
          extendedPadding: const EdgeInsets.symmetric(horizontal: 14),
        ),
      ),
    );
  }
}
