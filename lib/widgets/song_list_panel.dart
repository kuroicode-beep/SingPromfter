// file: lib/widgets/song_list_panel.dart
//
// 등록된 곡 목록을 표시하는 패널. 검색·필터는 제어형이라 화면을 전환해도
// 상태가 유지된다.
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/song.dart';
import '../services/song_filter_service.dart';
import '../services/song_sort_service.dart';
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
  final SongSortMode sortMode;
  final Map<String, int> practiceCounts;

  /// 곡별 현재 키(원곡 대비 반음). 0이면 목록에 표시하지 않는다.
  final Map<String, int> pitchBySongId;
  final ValueChanged<SongSortMode>? onSortModeChanged;
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
    this.sortMode = SongSortMode.title,
    this.practiceCounts = const {},
    this.pitchBySongId = const {},
    this.onSortModeChanged,
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
                  Icon(Icons.queue_music, size: 40, color: AppColors.border),
                  SizedBox(height: 10),
                  Text('등록된 곡이 없습니다', style: AppTypography.body),
                  SizedBox(height: 6),
                  Text(
                    '상단 [곡 추가]에 유튜브 링크를 붙여넣으면\n반주와 가사까지 자동으로 준비됩니다',
                    style: AppTypography.caption,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final filteredSongs = SongSortService.sort(
      SongFilterService.filter(
        songs,
        query: showSearchControls ? query : '',
        mode: filterMode,
      ),
      mode: sortMode,
      practiceCounts: practiceCounts,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (listTitle != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 4, 2),
            child: Row(
              children: [
                Text(listTitle!, style: AppTypography.listTitle),
                const SizedBox(width: 8),
                // 정렬은 전용 줄을 쓰지 않고 제목줄에 얹는다 — 목록을 한 줄 더 번다.
                if (showSearchControls && onSortModeChanged != null)
                  Expanded(child: _buildSortDropdown()),
                const Spacer(),
                Text(
                  '${filteredSongs.length}/${songs.length}곡',
                  style: AppTypography.monoMuted,
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
                  padding: const EdgeInsets.only(bottom: 8),
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
                      pitchSemitones: pitchBySongId[song.id] ?? 0,
                      practiceCount: practiceCounts[song.id] ?? 0,
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
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: _SongSearchField(
        query: query,
        onQueryChanged: onQueryChanged,
      ),
    );
  }


  Widget _buildSortDropdown() {
    return Semantics(
      label: '정렬 방식',
      child: DropdownButton<SongSortMode>(
        isExpanded: true,
        isDense: true,
        underline: const SizedBox.shrink(),
        value: sortMode,
        dropdownColor: AppColors.surface,
        style: AppTypography.caption,
        iconSize: 16,
        items: SongSortMode.values
            .map(
              (mode) => DropdownMenuItem(
                value: mode,
                child: Text(mode.label, style: AppTypography.caption),
              ),
            )
            .toList(growable: false),
        onChanged: (mode) {
          if (mode != null) onSortModeChanged?.call(mode);
        },
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: _chips.map((entry) {
          return _FilterChipSmall(
            label: entry.$1,
            selected: filterMode == entry.$2,
            onTap: () => onFilterModeChanged?.call(entry.$2),
          );
        }).toList(growable: false),
      ),
    );
  }
}

/// 목록 필터 칩. Material FilterChip은 최소 높이가 커서 직접 그린다.
/// 선택 상태는 색만이 아니라 체크 표시로도 알린다.
class _FilterChipSmall extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChipSmall({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: AppShapes.controlRadius,
        onTap: onTap,
        child: Container(
          height: AppConstants.denseTouchTarget,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryContainer : AppColors.elevated,
            borderRadius: AppShapes.controlRadius,
            border: Border.all(
              color: selected ? AppColors.primaryContainer : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected)
                const Padding(
                  padding: EdgeInsets.only(right: 3),
                  child: Icon(
                    Icons.check,
                    size: 13,
                    color: AppColors.onPrimaryContainer,
                  ),
                ),
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  color: selected
                      ? AppColors.onPrimaryContainer
                      : AppColors.onSurface,
                ),
              ),
            ],
          ),
        ),
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
          hintStyle: AppTypography.caption,
          prefixIcon: const Icon(
            Icons.search,
            size: 16,
            color: AppColors.textMuted,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 30,
            minHeight: 30,
          ),
          suffixIcon: widget.query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  tooltip: '검색어 지우기',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: AppConstants.minTouchTarget,
                    minHeight: AppConstants.denseTouchTarget,
                  ),
                  onPressed: () => widget.onQueryChanged?.call(''),
                ),
        ),
      ),
    );
  }
}
