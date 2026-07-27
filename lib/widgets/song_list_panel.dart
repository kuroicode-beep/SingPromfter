// file: lib/widgets/song_list_panel.dart
//
// 등록된 곡 목록을 표시하는 패널. 검색·필터는 제어형이라 화면을 전환해도
// 상태가 유지된다.
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/song.dart';
import '../services/song_filter_service.dart';
import '../theme/app_theme.dart';
import 'song_tile.dart';

class SongListPanel extends StatelessWidget {
  final List<Song> songs;
  final Song? selectedSong;
  final int? selectedTrackSlot;
  final SongListFilterMode filterMode;

  /// 목록 위에 검색창을 표시할지.
  final bool showSearchControls;

  /// 필터 칩을 표시할지. (즐겨찾기 화면처럼 모드가 고정된 곳은 false)
  final bool showFilterChips;

  final String query;
  final ValueChanged<String>? onQueryChanged;
  final ValueChanged<SongListFilterMode>? onFilterModeChanged;
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
    this.showFilterChips = false,
    this.query = '',
    this.onQueryChanged,
    this.onFilterModeChanged,
    this.listTitle,
    required this.onSelectTrack,
    required this.onSelect,
    required this.onStart,
    required this.onReserve,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  static const _chips = <(String, SongListFilterMode)>[
    ('전체', SongListFilterMode.all),
    ('즐겨찾기', SongListFilterMode.favorites),
    ('반주 있음', SongListFilterMode.withBackingTrack),
    ('최근 등록', SongListFilterMode.recent),
  ];

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
                    style: TextStyle(color: AppColors.textMuted, fontSize: 18),
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

    final filteredSongs = SongFilterService.filter(
      songs,
      query: showSearchControls ? query : '',
      mode: filterMode,
    );

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
        if (showSearchControls) _buildSearchField(),
        if (showSearchControls && showFilterChips) _buildFilterChips(),
        Expanded(
          child: filteredSongs.isEmpty
              ? Center(
                  child: Text(
                    _emptyMessage(),
                    style: AppTypography.bodyMuted,
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    0,
                    12,
                    listTitle == null ? 12 : 8,
                  ),
                  itemCount: filteredSongs.length,
                  separatorBuilder: (_, index) =>
                      const Divider(height: 1, thickness: 1),
                  itemBuilder: (_, i) {
                    final song = filteredSongs[i];
                    final selected = selectedSong?.id == song.id;
                    return SongTile(
                      song: song,
                      selected: selected,
                      selectedTrackSlot: selected ? selectedTrackSlot : null,
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

  String _emptyMessage() {
    if (query.trim().isNotEmpty) return '검색 결과가 없습니다';
    if (filterMode == SongListFilterMode.favorites) return '즐겨찾기 곡이 없습니다';
    return '표시할 곡이 없습니다';
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: _SongSearchField(
        query: query,
        onQueryChanged: onQueryChanged,
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _chips.map((entry) {
          final selected = filterMode == entry.$2;
          return Semantics(
            button: true,
            selected: selected,
            label: entry.$1,
            child: FilterChip(
              label: Text(entry.$1, style: AppTypography.body),
              selected: selected,
              showCheckmark: true,
              onSelected: (_) => onFilterModeChanged?.call(entry.$2),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              visualDensity: VisualDensity.standard,
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

/// 검색 입력창. 외부 값(query)과 동기화하되 컨트롤러를 유지해
/// 입력 중 포커스·커서가 끊기지 않게 한다.
class _SongSearchField extends StatefulWidget {
  final String query;
  final ValueChanged<String>? onQueryChanged;

  const _SongSearchField({required this.query, this.onQueryChanged});

  @override
  State<_SongSearchField> createState() => _SongSearchFieldState();
}

class _SongSearchFieldState extends State<_SongSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query,
  );

  @override
  void didUpdateWidget(covariant _SongSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 외부에서 값이 바뀐 경우(예: 지우기 버튼)만 반영한다.
    if (widget.query != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: '곡 검색',
      child: TextField(
        controller: _controller,
        onChanged: widget.onQueryChanged,
        style: AppTypography.body,
        decoration: InputDecoration(
          isDense: true,
          hintText: '제목·가수·초성으로 검색',
          hintStyle: AppTypography.bodyMuted,
          prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
          suffixIcon: widget.query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: '검색어 지우기',
                  constraints: const BoxConstraints(
                    minWidth: AppConstants.minTouchTarget,
                    minHeight: AppConstants.minTouchTarget,
                  ),
                  onPressed: () => widget.onQueryChanged?.call(''),
                ),
        ),
      ),
    );
  }
}
