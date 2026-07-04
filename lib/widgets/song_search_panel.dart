// file: lib/widgets/song_search_panel.dart
//
// desktop_2 시안 기준 곡 검색 화면. SongFilterService로 목록을 필터링한다.
import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/song_filter_service.dart';
import '../theme/app_theme.dart';

class SongSearchPanel extends StatefulWidget {
  final List<Song> songs;
  final String searchQuery;
  final SongListFilterMode filterMode;
  final ValueChanged<String> onSearchQueryChanged;
  final ValueChanged<SongListFilterMode> onFilterModeChanged;
  final ValueChanged<Song> onStart;
  final ValueChanged<Song> onReserve;
  final VoidCallback onReserveAll;

  const SongSearchPanel({
    super.key,
    required this.songs,
    required this.searchQuery,
    required this.filterMode,
    required this.onSearchQueryChanged,
    required this.onFilterModeChanged,
    required this.onStart,
    required this.onReserve,
    required this.onReserveAll,
  });

  @override
  State<SongSearchPanel> createState() => _SongSearchPanelState();
}

class _SongSearchPanelState extends State<SongSearchPanel> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.searchQuery);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant SongSearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery &&
        _controller.text != widget.searchQuery) {
      _controller.text = widget.searchQuery;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = SongFilterService.filter(
      widget.songs,
      query: widget.searchQuery,
      mode: widget.filterMode,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('곡 검색', style: AppTypography.screenTitle),
              const SizedBox(height: 16),
              Text('검색어', style: AppTypography.bodyMuted),
              const SizedBox(height: 6),
              Focus(
                onFocusChange: (_) => setState(() {}),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: AppTypography.body,
                  decoration: InputDecoration(
                    hintText: '제목 또는 초성으로 검색',
                    hintStyle: AppTypography.bodyMuted,
                    prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
                    suffixIcon: widget.searchQuery.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _controller.clear();
                              widget.onSearchQueryChanged('');
                            },
                            icon: const Icon(Icons.clear),
                            tooltip: '검색어 지우기',
                          ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppShapes.controlRadius,
                      borderSide: BorderSide(
                        color: _focusNode.hasFocus
                            ? AppColors.secondary
                            : AppColors.outline,
                        width: _focusNode.hasFocus ? 2 : 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: AppShapes.controlRadius,
                      borderSide: const BorderSide(
                        color: AppColors.secondary,
                        width: 2,
                      ),
                    ),
                  ),
                  onChanged: widget.onSearchQueryChanged,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FilterChip(
                label: '전체',
                selected: widget.filterMode == SongListFilterMode.all,
                onSelected: () =>
                    widget.onFilterModeChanged(SongListFilterMode.all),
              ),
              _FilterChip(
                label: '즐겨찾기',
                selected: widget.filterMode == SongListFilterMode.favorites,
                onSelected: () =>
                    widget.onFilterModeChanged(SongListFilterMode.favorites),
              ),
              _FilterChip(
                label: '반주 있음',
                selected: widget.filterMode == SongListFilterMode.withBackingTrack,
                onSelected: () => widget.onFilterModeChanged(
                  SongListFilterMode.withBackingTrack,
                ),
              ),
              _FilterChip(
                label: '최근 등록',
                selected: widget.filterMode == SongListFilterMode.recent,
                onSelected: () =>
                    widget.onFilterModeChanged(SongListFilterMode.recent),
              ),
              Text(
                '${results.length}/${widget.songs.length}곡',
                style: AppTypography.bodyMuted,
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1),
        Expanded(
          child: results.isEmpty
              ? Center(
                  child: Text(
                    '검색 결과가 없습니다',
                    style: AppTypography.bodyMuted,
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                        itemCount: results.length,
                        separatorBuilder: (_, index) =>
                            const Divider(height: 1, thickness: 1),
                        itemBuilder: (_, index) {
                          final song = results[index];
                          return _SongSearchResultRow(
                            index: index + 1,
                            song: song,
                            onReserve: () => widget.onReserve(song),
                            onStart: () => widget.onStart(song),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: widget.onReserveAll,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.tertiary,
                            foregroundColor: AppColors.background,
                            minimumSize: const Size.fromHeight(50),
                          ),
                          child: Text(
                            '검색 결과 전체 예약 (${results.length}곡)',
                            style: AppTypography.body.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label, style: AppTypography.body),
      selected: selected,
      onSelected: (_) => onSelected(),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );
  }
}

class _SongSearchResultRow extends StatelessWidget {
  final int index;
  final Song song;
  final VoidCallback onReserve;
  final VoidCallback onStart;

  const _SongSearchResultRow({
    required this.index,
    required this.song,
    required this.onReserve,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final trackCount = song.backingTracks.length;
    final trackSummary = trackCount == 0 ? '가사 전용' : '반주 $trackCount개';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              index.toString().padLeft(2, '0'),
              style: AppTypography.bodyMuted.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelStrong,
                ),
                const SizedBox(height: 2),
                Text(
                  song.artist.trim().isEmpty ? trackSummary : song.artist,
                  style: AppTypography.bodyMuted,
                ),
                if (song.artist.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(trackSummary, style: AppTypography.bodyMuted),
                ],
              ],
            ),
          ),
          OutlinedButton(
            onPressed: onReserve,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.tertiary,
              side: const BorderSide(color: AppColors.tertiary),
              minimumSize: const Size(72, 50),
            ),
            child: const Text('예약'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onStart,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryContainer,
              foregroundColor: AppColors.onPrimaryContainer,
              minimumSize: const Size(72, 50),
            ),
            child: const Text('시작'),
          ),
        ],
      ),
    );
  }
}
