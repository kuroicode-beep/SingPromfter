// file: lib/widgets/song_tile.dart
//
// 곡 목록의 한 행. v2.5.0에서 카드형 → 고밀도 행으로 바꿨다.
//
// 링크 기반 시스템에서는 곡마다 가수·싱크 가사·반주 슬롯·키·연습 횟수가
// 자동으로 채워진다. 한 화면에 더 많은 곡과 그 상태를 함께 보여주는 것이
// 큰 카드보다 실제로 쓸모가 크다고 판단해, 제목 아래 한 줄에 상태를 모았다.
// 상태는 색이 아니라 글자로 적는다.
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/song.dart';
import '../theme/app_theme.dart';
import '../utils/key_label.dart';

class SongTile extends StatelessWidget {
  final Song song;
  final bool selected;
  final int? selectedTrackSlot;

  /// 원곡 대비 반음. 0이면 표시하지 않는다.
  final int pitchSemitones;

  /// 누적 연습 횟수. 0이면 표시하지 않는다.
  final int practiceCount;

  final void Function(int slot)? onSelectTrack;
  final VoidCallback? onAddTrack;
  final VoidCallback onSelect;
  final VoidCallback onStart;
  final VoidCallback onReserve;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;

  const SongTile({
    super.key,
    required this.song,
    required this.selected,
    this.selectedTrackSlot,
    this.pitchSemitones = 0,
    this.practiceCount = 0,
    this.onSelectTrack,
    this.onAddTrack,
    required this.onSelect,
    required this.onStart,
    required this.onReserve,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  /// 제목 아래 한 줄 요약. 가수 → 반주 → 가사 → 키 → 연습 순.
  String _metaLine() {
    final parts = <String>[];
    final artist = song.artist.trim();
    if (artist.isNotEmpty) parts.add(artist);

    final trackCount = song.backingTracks.length;
    parts.add(trackCount == 0 ? '반주 없음' : '반주 $trackCount');

    if ((song.lrcFileName ?? '').isNotEmpty) parts.add('싱크가사');
    if (pitchSemitones != 0) parts.add(formatKeyLabel(pitchSemitones));
    if (practiceCount > 0) parts.add('$practiceCount회');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final meta = _metaLine();
    return Semantics(
      selected: selected,
      label: '${song.title}, $meta${selected ? ', 선택됨' : ''}',
      child: Material(
        color: selected ? AppColors.selectedSurface : Colors.transparent,
        child: InkWell(
          onTap: onSelect,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: selected ? AppColors.primary : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(3, 4, 4, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _IconBtn(
                      icon: song.isFavorite ? Icons.star : Icons.star_border,
                      color: song.isFavorite
                          ? AppColors.accent
                          : AppColors.textMuted,
                      tooltip: song.isFavorite ? '즐겨찾기 해제' : '즐겨찾기 추가',
                      onTap: onToggleFavorite,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.body.copyWith(
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.onSurface,
                            ),
                          ),
                          Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption,
                          ),
                        ],
                      ),
                    ),
                    if (selected) ...[
                      _IconBtn(
                        icon: Icons.edit_outlined,
                        tooltip: '곡 정보 수정',
                        onTap: onEdit,
                      ),
                      _IconBtn(
                        icon: Icons.delete_outline,
                        tooltip: '곡 삭제',
                        onTap: onDelete,
                      ),
                    ],
                    _IconBtn(
                      icon: Icons.playlist_add,
                      color: AppColors.tertiary,
                      tooltip: '예약 큐에 추가',
                      onTap: onReserve,
                    ),
                    _IconBtn(
                      icon: Icons.play_arrow,
                      color: AppColors.primary,
                      tooltip: '이 곡으로 무대 열기',
                      onTap: onStart,
                    ),
                  ],
                ),
                // 선택한 곡에서만 슬롯 줄을 편다. 반주가 하나여도
                // '반주 추가'로 노래방 버전 등을 붙일 수 있어야 한다.
                if (selected && (onSelectTrack != null || onAddTrack != null))
                  Padding(
                    padding: const EdgeInsets.only(left: 26, top: 3),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (song.backingTracks.length > 1 &&
                            onSelectTrack != null)
                          for (final track in song.backingTracks)
                            _SlotChip(
                              label: track.label.trim().isEmpty
                                  ? '반주${track.slot}'
                                  : track.label,
                              selected: selectedTrackSlot == track.slot,
                              onTap: () => onSelectTrack!(track.slot),
                            ),
                        if (onAddTrack != null &&
                            song.backingTracks.length <
                                AppConstants.maxBackingTrackSlots)
                          _SlotChip(
                            label: '+ 반주',
                            selected: false,
                            onTap: onAddTrack!,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 목록 행에 들어가는 압축 아이콘 버튼.
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final String tooltip;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: SizedBox(
            width: AppConstants.denseTouchTarget,
            height: AppConstants.denseTouchTarget,
            child: Icon(icon, size: 17, color: color ?? AppColors.textMuted),
          ),
        ),
      ),
    );
  }
}

/// 반주 슬롯 선택 칩. 선택 상태를 체크 표시로도 알린다(색만으로 구분 금지).
class _SlotChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SlotChip({
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
