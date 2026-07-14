// file: lib/widgets/song_list_panel.dart
//
// 등록된 곡 목록을 표시하는 패널.
import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/song_filter_service.dart';
import '../theme/app_theme.dart';
import 'song_tile.dart';

class SongListPanel extends StatelessWidget {
  final List<Song> songs;
  final Song? selectedSong;
  final int? selectedTrackSlot;
  final SongListFilterMode filterMode;
  final bool showSearchControls;
  final String? listTitle;
  final void Function(Song song, int slot) onSelectTrack;
  final ValueChanged<Song> onSelect;
  final ValueChanged<Song> onStart;
  final ValueChanged<Song> onReserve;
  final ValueChanged<Song> onEdit;
  final ValueChanged<Song> onDelete;
  final ValueChanged<Song> onToggleFavorite;

  const SongListPanel({
    super.key,
    required this.songs,
    required this.selectedSong,
    required this.selectedTrackSlot,
    this.filterMode = SongListFilterMode.all,
    this.showSearchControls = false,
    this.listTitle,
    required this.onSelectTrack,
    required this.onSelect,
    required this.onStart,
    required this.onReserve,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return const Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.queue_music, size: 56, color: AppColors.border),
                  SizedBox(height: 14),
                  Text(
                    '등록된 곡이 없습니다',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 18,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '상단의 곡 등록으로 추가해 주세요',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (showSearchControls) {
      return _SongListFilterPanel(
        songs: songs,
        selectedSong: selectedSong,
        selectedTrackSlot: selectedTrackSlot,
        initialFilterMode: filterMode,
        onSelectTrack: onSelectTrack,
        onSelect: onSelect,
        onStart: onStart,
        onReserve: onReserve,
        onEdit: onEdit,
        onDelete: onDelete,
        onToggleFavorite: onToggleFavorite,
      );
    }

    final filteredSongs = SongFilterService.filter(songs, mode: filterMode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (listTitle != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Text(listTitle!, style: AppTypography.listTitle),
                const Spacer(),
                Text(
                  '${filteredSongs.length}/${songs.length}곡',
                  style: AppTypography.bodyMuted,
                ),
              ],
            ),
          ),
        Expanded(
          child: filteredSongs.isEmpty
              ? Center(
                  child: Text(
                    filterMode == SongListFilterMode.favorites
                        ? '즐겨찾기 곡이 없습니다'
                        : '표시할 곡이 없습니다',
                    style: AppTypography.bodyMuted,
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, listTitle == null ? 12 : 8),
                  itemCount: filteredSongs.length,
                  separatorBuilder: (_, index) =>
                      const Divider(height: 1, thickness: 1),
                  itemBuilder: (_, i) {
                    final song = filteredSongs[i];
                    final selected = selectedSong?.id == song.id;
                    return SongTile(
                      song: song,
                      selected: selected,
                      selectedTrackSlot:
                          selected ? selectedTrackSlot : null,
                      onSelectTrack: (slot) => onSelectTrack(song, slot),
                      onSelect: () => onSelect(song),
                      onStart: () => onStart(song),
                      onReserve: () => onReserve(song),
                      onEdit: () => onEdit(song),
                      onDelete: () => onDelete(song),
                      onToggleFavorite: () => onToggleFavorite(song),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SongListFilterPanel extends StatefulWidget {
  final List<Song> songs;
  final Song? selectedSong;
  final int? selectedTrackSlot;
  final SongListFilterMode initialFilterMode;
  final void Function(Song song, int slot) onSelectTrack;
  final ValueChanged<Song> onSelect;
  final ValueChanged<Song> onStart;
  final ValueChanged<Song> onReserve;
  final ValueChanged<Song> onEdit;
  final ValueChanged<Song> onDelete;
  final ValueChanged<Song> onToggleFavorite;

  const _SongListFilterPanel({
    required this.songs,
    required this.selectedSong,
    required this.selectedTrackSlot,
    required this.initialFilterMode,
    required this.onSelectTrack,
    required this.onSelect,
    required this.onStart,
    required this.onReserve,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  @override
  State<_SongListFilterPanel> createState() => _SongListFilterPanelState();
}

class _SongListFilterPanelState extends State<_SongListFilterPanel> {
  final _searchController = TextEditingController();
  late SongListFilterMode _filterMode;

  @override
  void initState() {
    super.initState();
    _filterMode = widget.initialFilterMode;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredSongs = SongFilterService.filter(
      widget.songs,
      query: _searchController.text,
      mode: _filterMode,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _searchController,
            minLines: 1,
            style: AppTypography.body,
            decoration: InputDecoration(
              hintText: '곡 제목 검색...',
              hintStyle: AppTypography.bodyMuted,
              prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => setState(_searchController.clear),
                      icon: const Icon(Icons.clear),
                      tooltip: '검색어 지우기',
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              FilterChip(
                label: Text('전체', style: AppTypography.body),
                selected: _filterMode == SongListFilterMode.all,
                onSelected: (_) =>
                    setState(() => _filterMode = SongListFilterMode.all),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                visualDensity: VisualDensity.standard,
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text('즐겨찾기', style: AppTypography.body),
                selected: _filterMode == SongListFilterMode.favorites,
                onSelected: (_) =>
                    setState(() => _filterMode = SongListFilterMode.favorites),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                visualDensity: VisualDensity.standard,
              ),
              const Spacer(),
              Text(
                '${filteredSongs.length}/${widget.songs.length}곡',
                style: AppTypography.bodyMuted,
              ),
            ],
          ),
        ),
        Expanded(
          child: filteredSongs.isEmpty
              ? Center(
                  child: Text(
                    '검색 결과가 없습니다',
                    style: AppTypography.bodyMuted,
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  itemCount: filteredSongs.length,
                  separatorBuilder: (_, index) =>
                      const Divider(height: 1, thickness: 1),
                  itemBuilder: (_, i) {
                    final song = filteredSongs[i];
                    final selected = widget.selectedSong?.id == song.id;
                    return SongTile(
                      song: song,
                      selected: selected,
                      selectedTrackSlot: selected
                          ? widget.selectedTrackSlot
                          : null,
                      onSelectTrack: (slot) => widget.onSelectTrack(song, slot),
                      onSelect: () => widget.onSelect(song),
                      onStart: () => widget.onStart(song),
                      onReserve: () => widget.onReserve(song),
                      onEdit: () => widget.onEdit(song),
                      onDelete: () => widget.onDelete(song),
                      onToggleFavorite: () => widget.onToggleFavorite(song),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
