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

class SongListPanel extends StatefulWidget {
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
  final ValueChanged<Song>? onAddTrack;
  final ValueChanged<Song> onSelect;
  final ValueChanged<Song> onStart;
  final ValueChanged<Song> onReserve;
  final ValueChanged<Song> onEdit;
  final ValueChanged<Song> onDelete;
  final ValueChanged<Song> onToggleFavorite;

  /// 드래그로 순서를 바꿨을 때. 보이는 목록의 id 순서와 출발/도착(보정)
  /// 인덱스를 넘긴다 — 필터 중에도 호출부가 전체 순서에 반영할 수 있게.
  /// null이면 손잡이를 그리지 않는다.
  final void Function(List<String> visibleIds, int oldIndex, int newIndex)?
  onReorder;

  /// 폴더 표시 순서(설정). 여기 있는 이름은 곡이 없어도 폴더로 보인다.
  final List<String> folderOrder;

  /// 펼쳐 둔 폴더(설정). [onToggleFolder]가 있을 때만 쓰이는 제어형 값 —
  /// 없으면 패널이 스스로 상태를 든다(즐겨찾기 화면 등).
  final Set<String> expandedFolders;
  final ValueChanged<String>? onToggleFolder;

  /// 제목줄 [새 폴더] 버튼. null이면 그리지 않는다.
  final VoidCallback? onCreateFolder;

  /// 폴더를 위(-1)/아래(+1)로 옮긴다. 현재 표시 순서 전체를 함께 넘겨
  /// 호출부가 그대로 저장할 수 있게 한다. null이면 ▲▼을 그리지 않는다.
  final void Function(List<String> displayOrder, String name, int delta)?
  onMoveFolder;

  /// 곡을 드래그해 폴더에 떨어뜨렸을 때. folder가 ''이면 폴더에서 꺼낸다.
  /// null이면 드래그 손잡이를 그리지 않는다.
  final void Function(String songId, String folder)? onMoveSongToFolder;

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
    this.onAddTrack,
    required this.onSelect,
    required this.onStart,
    required this.onReserve,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleFavorite,
    this.onReorder,
    this.folderOrder = const [],
    this.expandedFolders = const {},
    this.onToggleFolder,
    this.onCreateFolder,
    this.onMoveFolder,
    this.onMoveSongToFolder,
  });

  @override
  State<SongListPanel> createState() => _SongListPanelState();
}

class _SongListPanelState extends State<SongListPanel> {
  /// 펼쳐진 폴더 이름들(비제어형 폴백). 기본은 전부 닫힘.
  final Set<String> _localExpanded = {};

  /// 드래그 중인 곡. 폴더 헤더가 받을 준비를 하고, 폴더 소속 곡이면
  /// 맨 위에 '폴더에서 꺼내기' 놓기 자리가 나타난다.
  Song? _draggingSong;

  /// 제어형이면 설정값을, 아니면 로컬 상태를 쓴다.
  Set<String> get _expanded =>
      widget.onToggleFolder != null ? widget.expandedFolders : _localExpanded;

  void _toggleFolder(String name) {
    final external = widget.onToggleFolder;
    if (external != null) {
      external(name);
      return;
    }
    setState(() {
      _localExpanded.contains(name)
          ? _localExpanded.remove(name)
          : _localExpanded.add(name);
    });
  }

  static const _chips = <(String, SongListFilterMode)>[
    ('전체', SongListFilterMode.all),
    ('즐겨찾기', SongListFilterMode.favorites),
    ('반주 있음', SongListFilterMode.withBackingTrack),
    ('최근 등록', SongListFilterMode.recent),
  ];

  List<Song> get songs => widget.songs;
  String get query => widget.query;
  SongListFilterMode get filterMode => widget.filterMode;
  bool get showSearchControls => widget.showSearchControls;

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
      mode: widget.sortMode,
      practiceCounts: widget.practiceCounts,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.listTitle != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 4, 2),
            child: Row(
              children: [
                Text(widget.listTitle!, style: AppTypography.listTitle),
                const SizedBox(width: 8),
                // 정렬은 전용 줄을 쓰지 않고 제목줄에 얹는다 — 목록을 한 줄 더 번다.
                if (showSearchControls && widget.onSortModeChanged != null)
                  Expanded(child: _buildSortDropdown()),
                const Spacer(),
                Text(
                  '${filteredSongs.length}/${songs.length}곡',
                  style: AppTypography.monoMuted,
                ),
                if (widget.onCreateFolder != null)
                  IconButton(
                    onPressed: widget.onCreateFolder,
                    icon: const Icon(Icons.create_new_folder_outlined, size: 22),
                    tooltip: '새 폴더',
                    constraints: const BoxConstraints(
                      minWidth: AppConstants.minTouchTarget,
                      minHeight: AppConstants.denseTouchTarget,
                    ),
                  ),
              ],
            ),
          ),
        if (showSearchControls) _buildSearchField(),
        if (showSearchControls && widget.showFilterChips) _buildFilterChips(),
        Expanded(
          child: filteredSongs.isEmpty
              ? Center(
                  child: Text(
                    _emptyMessage(),
                    style: AppTypography.bodyMuted,
                    textAlign: TextAlign.center,
                  ),
                )
              : _buildList(filteredSongs),
        ),
      ],
    );
  }

  Widget _tileFor(Song song) {
    final selected = widget.selectedSong?.id == song.id;
    return SongTile(
      song: song,
      selected: selected,
      selectedTrackSlot: selected ? widget.selectedTrackSlot : null,
      pitchSemitones: widget.pitchBySongId[song.id] ?? 0,
      practiceCount: widget.practiceCounts[song.id] ?? 0,
      onSelectTrack: (slot) => widget.onSelectTrack(song, slot),
      onAddTrack: widget.onAddTrack == null
          ? null
          : () => widget.onAddTrack!(song),
      onSelect: () => widget.onSelect(song),
      onStart: () => widget.onStart(song),
      onReserve: () => widget.onReserve(song),
      onEdit: () => widget.onEdit(song),
      onDelete: () => widget.onDelete(song),
      onToggleFavorite: () => widget.onToggleFavorite(song),
    );
  }

  /// 예약 큐와 같은 드래그 재정렬 목록. onReorder가 없으면 평범한 목록.
  /// 폴더가 하나라도 있으면 1단계 트리로 보여 준다(검색 중에는 평평하게 —
  /// 닫힌 폴더에 결과가 숨지 않도록).
  Widget _buildList(List<Song> filteredSongs) {
    Widget tileFor(Song song) => _tileFor(song);

    // 설정에 등록된 폴더(빈 폴더 포함)를 먼저, 곡에만 적힌 폴더를 뒤에.
    final fromSongs = Song.folderNames(filteredSongs);
    final folders = <String>[
      ...widget.folderOrder,
      ...fromSongs.where((f) => !widget.folderOrder.contains(f)),
    ];
    if (folders.isNotEmpty && query.trim().isEmpty) {
      return _buildFolderTree(filteredSongs, folders);
    }

    final reorder = widget.onReorder;
    if (reorder == null) {
      return ListView.separated(
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: filteredSongs.length,
        separatorBuilder: (_, index) => const Divider(height: 1, thickness: 1),
        itemBuilder: (_, i) => tileFor(filteredSongs[i]),
      );
    }

    return ReorderableListView(
      padding: const EdgeInsets.only(bottom: 8),
      buildDefaultDragHandles: false,
      // onReorderItem은 항목 제거를 반영한 **보정된** newIndex를 준다 —
      // applyVisibleReorder가 같은 규약을 쓰므로 그대로 넘긴다.
      onReorderItem: (oldIndex, newIndex) => reorder(
        filteredSongs.map((s) => s.id).toList(growable: false),
        oldIndex,
        newIndex,
      ),
      children: [
        for (var i = 0; i < filteredSongs.length; i++)
          Column(
            key: ValueKey(filteredSongs[i].id),
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 예약 큐와 같은 손잡이. 저시력: 아이콘만으로도 위치가
                  // 일정해 찾기 쉽도록 모든 줄의 왼쪽 고정.
                  ReorderableDragStartListener(
                    index: i,
                    child: Semantics(
                      label: '${filteredSongs[i].title} 순서 바꾸기 손잡이',
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.drag_handle,
                          size: 22,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: tileFor(filteredSongs[i])),
                ],
              ),
              if (i < filteredSongs.length - 1)
                const Divider(height: 1, thickness: 1),
            ],
          ),
      ],
    );
  }

  /// 1단계 폴더 트리 — 폴더 없는 곡 먼저, 그 밑에 폴더들(기본 닫힘, 토글).
  Widget _buildFolderTree(List<Song> filteredSongs, List<String> folders) {
    final loose = filteredSongs
        .where((s) => s.folder.isEmpty)
        .toList(growable: false);
    final byFolder = <String, List<Song>>{
      for (final name in folders)
        name: filteredSongs
            .where((s) => s.folder == name)
            .toList(growable: false),
    };

    final rows = <Widget>[];
    // 폴더 소속 곡을 끌고 있으면 맨 위에 '꺼내기' 놓기 자리가 생긴다.
    if (_draggingSong != null && _draggingSong!.folder.isNotEmpty) {
      rows.add(_unfolderDropBar());
    }
    for (final song in loose) {
      if (rows.isNotEmpty) {
        rows.add(const Divider(height: 1, thickness: 1));
      }
      rows.add(_draggableTile(song));
    }
    final moveFolder = widget.onMoveFolder;
    for (var f = 0; f < folders.length; f++) {
      final name = folders[f];
      final members = byFolder[name] ?? const <Song>[];
      final open = _expanded.contains(name);
      if (rows.isNotEmpty) {
        rows.add(const Divider(height: 1, thickness: 1));
      }
      rows.add(
        _folderDropTarget(
          name,
          _FolderHeader(
            name: name,
            count: members.length,
            open: open,
            onTap: () => _toggleFolder(name),
            onMoveUp: moveFolder == null || f == 0
                ? null
                : () => moveFolder(folders, name, -1),
            onMoveDown: moveFolder == null || f == folders.length - 1
                ? null
                : () => moveFolder(folders, name, 1),
          ),
        ),
      );
      if (open) {
        if (members.isEmpty) {
          rows.add(const Divider(height: 1, thickness: 1));
          rows.add(
            const Padding(
              padding: EdgeInsets.fromLTRB(36, 10, 8, 10),
              child: Text(
                '비어 있는 폴더 — 곡을 끌어다 놓거나 곡 수정에서 지정해 담습니다',
                style: AppTypography.bodyMuted,
              ),
            ),
          );
        }
        for (final song in members) {
          rows.add(const Divider(height: 1, thickness: 1));
          // 폴더 소속임이 보이도록 들여쓴다.
          rows.add(
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: _draggableTile(song),
            ),
          );
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: rows,
    );
  }

  /// 곡 타일 + 왼쪽 드래그 손잡이. 손잡이만 드래그를 받아 타일의
  /// 버튼·탭과 충돌하지 않는다(재정렬 손잡이와 같은 문법).
  Widget _draggableTile(Song song) {
    final move = widget.onMoveSongToFolder;
    if (move == null) return _tileFor(song);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Draggable<String>(
          data: song.id,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          onDragStarted: () => setState(() => _draggingSong = song),
          onDragEnd: (_) => setState(() => _draggingSong = null),
          feedback: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                song.title,
                style: AppTypography.body.copyWith(
                  color: AppColors.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          child: Semantics(
            label: '${song.title} 폴더로 끌기 손잡이',
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.drag_indicator,
                size: 22,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ),
        Expanded(child: _tileFor(song)),
      ],
    );
  }

  /// 폴더 헤더를 놓기 자리로 감싼다. 위에 곡이 올라와 있으면 테두리로 알린다.
  Widget _folderDropTarget(String name, Widget header) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          _draggingSong != null && _draggingSong!.folder != name,
      onAcceptWithDetails: (details) {
        widget.onMoveSongToFolder?.call(details.data, name);
        setState(() => _draggingSong = null);
      },
      builder: (context, candidates, rejected) => Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: candidates.isNotEmpty
                ? AppColors.primary
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: header,
      ),
    );
  }

  /// 드래그 중에만 맨 위에 나타나는 '폴더에서 꺼내기' 놓기 자리.
  Widget _unfolderDropBar() {
    return DragTarget<String>(
      onAcceptWithDetails: (details) {
        widget.onMoveSongToFolder?.call(details.data, '');
        setState(() => _draggingSong = null);
      },
      builder: (context, candidates, rejected) => Container(
        height: AppConstants.minTouchTarget,
        margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: candidates.isNotEmpty
              ? AppColors.primaryContainer
              : AppColors.elevated,
          borderRadius: AppShapes.controlRadius,
          border: Border.all(
            color: candidates.isNotEmpty
                ? AppColors.primary
                : AppColors.borderStrong,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_off_outlined,
              size: 20,
              color: candidates.isNotEmpty
                  ? AppColors.onPrimaryContainer
                  : AppColors.onSurface,
            ),
            const SizedBox(width: 8),
            Text(
              '여기에 놓으면 폴더에서 꺼냅니다',
              style: AppTypography.body.copyWith(
                color: candidates.isNotEmpty
                    ? AppColors.onPrimaryContainer
                    : AppColors.onSurface,
              ),
            ),
          ],
        ),
      ),
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
        onQueryChanged: widget.onQueryChanged,
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
        value: widget.sortMode,
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
          if (mode != null) widget.onSortModeChanged?.call(mode);
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
            onTap: () => widget.onFilterModeChanged?.call(entry.$2),
          );
        }).toList(growable: false),
      ),
    );
  }
}

/// 폴더 줄. 누르면 펼치고 다시 누르면 닫는다.
/// 상태는 화살표 방향 + "펼침/닫힘" 시맨틱으로 알린다(색에만 의존하지 않음).
class _FolderHeader extends StatelessWidget {
  final String name;
  final int count;
  final bool open;
  final VoidCallback onTap;

  /// 순서 이동. 맨 위/맨 아래 폴더는 해당 방향이 null(흐리게)이다.
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _FolderHeader({
    required this.name,
    required this.count,
    required this.open,
    required this.onTap,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    final showMove = onMoveUp != null || onMoveDown != null;
    return Semantics(
      button: true,
      expanded: open,
      label: '폴더 $name, $count곡',
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppConstants.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: AppColors.surface,
          child: Row(
            children: [
              Icon(
                open ? Icons.folder_open : Icons.folder,
                size: 22,
                color: AppColors.textPrimary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (showMove) ...[
                IconButton(
                  onPressed: onMoveUp,
                  icon: const Icon(Icons.arrow_upward, size: 20),
                  tooltip: '폴더 위로',
                  constraints: const BoxConstraints(
                    minWidth: AppConstants.denseTouchTarget,
                    minHeight: AppConstants.denseTouchTarget,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: onMoveDown,
                  icon: const Icon(Icons.arrow_downward, size: 20),
                  tooltip: '폴더 아래로',
                  constraints: const BoxConstraints(
                    minWidth: AppConstants.denseTouchTarget,
                    minHeight: AppConstants.denseTouchTarget,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
              Text('$count곡', style: AppTypography.monoMuted),
              const SizedBox(width: 4),
              Icon(
                open ? Icons.expand_less : Icons.expand_more,
                size: 24,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
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
