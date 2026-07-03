// file: lib/widgets/song_list_panel.dart
//
// 등록된 곡 목록과 하단 저작권 문구를 표시하는 패널.
import 'package:flutter/material.dart';

import '../models/song.dart';
import '../theme/app_theme.dart';
import 'song_tile.dart';

class SongListPanel extends StatelessWidget {
  final List<Song> songs;
  final Song? selectedSong;
  final int? selectedTrackSlot;
  final void Function(Song song, int slot) onSelectTrack;
  final ValueChanged<Song> onSelect;
  final ValueChanged<Song> onPlayNow;
  final ValueChanged<Song> onReserve;
  final ValueChanged<Song> onEdit;
  final ValueChanged<Song> onDelete;
  final ValueChanged<Song> onToggleFavorite;

  const SongListPanel({
    super.key,
    required this.songs,
    required this.selectedSong,
    required this.selectedTrackSlot,
    required this.onSelectTrack,
    required this.onSelect,
    required this.onPlayNow,
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
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '하단 버튼으로 곡을 추가해 주세요',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
          _SongListFooter(),
        ],
      );
    }

    return _SongListFilterPanel(
      songs: songs,
      selectedSong: selectedSong,
      selectedTrackSlot: selectedTrackSlot,
      onSelectTrack: onSelectTrack,
      onSelect: onSelect,
      onPlayNow: onPlayNow,
      onReserve: onReserve,
      onEdit: onEdit,
      onDelete: onDelete,
      onToggleFavorite: onToggleFavorite,
    );
  }
}

class _SongListFilterPanel extends StatefulWidget {
  final List<Song> songs;
  final Song? selectedSong;
  final int? selectedTrackSlot;
  final void Function(Song song, int slot) onSelectTrack;
  final ValueChanged<Song> onSelect;
  final ValueChanged<Song> onPlayNow;
  final ValueChanged<Song> onReserve;
  final ValueChanged<Song> onEdit;
  final ValueChanged<Song> onDelete;
  final ValueChanged<Song> onToggleFavorite;

  const _SongListFilterPanel({
    required this.songs,
    required this.selectedSong,
    required this.selectedTrackSlot,
    required this.onSelectTrack,
    required this.onSelect,
    required this.onPlayNow,
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
  bool _showFavoritesOnly = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredSongs = _filteredSongs;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _searchController,
            minLines: 1,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
            decoration: InputDecoration(
              hintText: '곡 제목 검색...',
              hintStyle: const TextStyle(color: AppColors.textMuted),
              prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => setState(_searchController.clear),
                      icon: const Icon(Icons.clear),
                      tooltip: '검색어 지우기',
                    ),
              filled: true,
              fillColor: AppColors.elevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
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
                label: const Text('전체'),
                selected: !_showFavoritesOnly,
                onSelected: (_) => setState(() => _showFavoritesOnly = false),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('즐겨찾기'),
                selected: _showFavoritesOnly,
                onSelected: (_) => setState(() => _showFavoritesOnly = true),
              ),
              const Spacer(),
              Text(
                '${filteredSongs.length}/${widget.songs.length}곡',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filteredSongs.isEmpty
              ? const Center(
                  child: Text(
                    '검색 결과가 없습니다',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 16),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 124),
                  itemCount: filteredSongs.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 8),
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
                      onPlayNow: () => widget.onPlayNow(song),
                      onReserve: () => widget.onReserve(song),
                      onEdit: () => widget.onEdit(song),
                      onDelete: () => widget.onDelete(song),
                      onToggleFavorite: () => widget.onToggleFavorite(song),
                    );
                  },
                ),
        ),
        const _SongListFooter(),
      ],
    );
  }

  List<Song> get _filteredSongs {
    final query = _searchController.text.trim();
    return widget.songs
        .where((song) {
          if (_showFavoritesOnly && !song.isFavorite) return false;
          if (query.isEmpty) return true;
          return _matchesTitle(song.title, query);
        })
        .toList(growable: false);
  }

  bool _matchesTitle(String title, String query) {
    final normalizedTitle = title.toLowerCase();
    final normalizedQuery = query.toLowerCase();
    return normalizedTitle.contains(normalizedQuery) ||
        _koreanInitials(title).contains(normalizedQuery);
  }

  String _koreanInitials(String value) {
    const initials = [
      'ㄱ',
      'ㄲ',
      'ㄴ',
      'ㄷ',
      'ㄸ',
      'ㄹ',
      'ㅁ',
      'ㅂ',
      'ㅃ',
      'ㅅ',
      'ㅆ',
      'ㅇ',
      'ㅈ',
      'ㅉ',
      'ㅊ',
      'ㅋ',
      'ㅌ',
      'ㅍ',
      'ㅎ',
    ];
    final buffer = StringBuffer();
    for (final codeUnit in value.runes) {
      if (codeUnit >= 0xAC00 && codeUnit <= 0xD7A3) {
        buffer.write(initials[(codeUnit - 0xAC00) ~/ 588]);
      } else {
        buffer.write(String.fromCharCode(codeUnit).toLowerCase());
      }
    }
    return buffer.toString();
  }
}

class _SongListFooter extends StatelessWidget {
  const _SongListFooter();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Text(
        'Copyright SVIL. Powered by 디또 2026/03/10',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.2),
      ),
    );
  }
}
