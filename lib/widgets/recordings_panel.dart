// file: lib/widgets/recordings_panel.dart
//
// 녹음 보관함 — 테이크 목록, 코멘트, 별점, 재생/삭제.
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/recording_take.dart';
import '../theme/app_theme.dart';
import '../utils/key_label.dart';

class RecordingsPanel extends StatelessWidget {
  final List<RecordingTake> takes;
  final String query;
  final RecordingFilterMode filterMode;
  final String? playingTakeId;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<RecordingFilterMode> onFilterModeChanged;
  final ValueChanged<RecordingTake> onPlay;
  final ValueChanged<RecordingTake> onStopPlay;
  final ValueChanged<RecordingTake> onEditComment;
  final void Function(RecordingTake take, int rating) onRate;
  final ValueChanged<RecordingTake> onToggleKeep;
  final ValueChanged<RecordingTake> onDelete;
  final ValueChanged<RecordingTake> onMix;
  final ValueChanged<RecordingTake> onPlayMix;

  /// v3.0.0 음정 코치 — 채점과 AI 보정.
  final ValueChanged<RecordingTake> onAnalyze;
  final ValueChanged<RecordingTake> onCorrect;

  /// v3.20.0 플레이어 — 재생 중 테이크의 위치/길이와 시크.
  final Duration playingPosition;
  final Duration playingDuration;
  final ValueChanged<Duration>? onSeek;

  const RecordingsPanel({
    super.key,
    required this.takes,
    required this.query,
    required this.filterMode,
    required this.playingTakeId,
    required this.onQueryChanged,
    required this.onFilterModeChanged,
    required this.onPlay,
    required this.onStopPlay,
    required this.onEditComment,
    required this.onRate,
    required this.onToggleKeep,
    required this.onDelete,
    required this.onMix,
    required this.onPlayMix,
    required this.onAnalyze,
    required this.onCorrect,
    this.playingPosition = Duration.zero,
    this.playingDuration = Duration.zero,
    this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text('녹음 보관함', style: AppTypography.screenTitle),
              const Spacer(),
              Text('${takes.length}개', style: AppTypography.monoMuted),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _SearchField(query: query, onChanged: onQueryChanged),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: RecordingFilterMode.values.map((mode) {
              final selected = filterMode == mode;
              return Semantics(
                button: true,
                selected: selected,
                label: mode.label,
                child: FilterChip(
                  label: Text(mode.label, style: AppTypography.body),
                  selected: selected,
                  showCheckmark: true,
                  onSelected: (_) => onFilterModeChanged(mode),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  visualDensity: VisualDensity.standard,
                ),
              );
            }).toList(growable: false),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: takes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      query.trim().isEmpty
                          ? '아직 녹음이 없습니다.\n곡을 재생하면서 녹음 버튼을 눌러 보세요.'
                          : '검색 결과가 없습니다',
                      style: AppTypography.bodyMuted,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: takes.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, thickness: 1),
                  itemBuilder: (_, index) {
                    final take = takes[index];
                    final isPlaying = playingTakeId == take.id;
                    return _TakeRow(
                      take: take,
                      playing: isPlaying,
                      playingPosition: isPlaying ? playingPosition : null,
                      playingDuration: isPlaying ? playingDuration : null,
                      onSeek: isPlaying ? onSeek : null,
                      onPlay: () => onPlay(take),
                      onStopPlay: () => onStopPlay(take),
                      onEditComment: () => onEditComment(take),
                      onRate: (rating) => onRate(take, rating),
                      onToggleKeep: () => onToggleKeep(take),
                      onDelete: () => onDelete(take),
                      onMix: () => onMix(take),
                      onPlayMix: () => onPlayMix(take),
                      onAnalyze: () => onAnalyze(take),
                      onCorrect: () => onCorrect(take),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// 재생 중 테이크의 플레이어 줄 — 시크 슬라이더 + mm:ss / mm:ss.
class _TakePlayerBar extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration>? onSeek;

  const _TakePlayerBar({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(600).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = duration.inMilliseconds;
    final value = totalMs <= 0
        ? 0.0
        : (position.inMilliseconds / totalMs).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.elevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      child: Row(
        children: [
          Text(_fmt(position), style: AppTypography.mono),
          Expanded(
            child: Semantics(
              slider: true,
              label: '재생 위치',
              child: Slider(
                value: value,
                onChanged: totalMs <= 0 || onSeek == null
                    ? null
                    : (v) => onSeek!(
                        Duration(milliseconds: (v * totalMs).round()),
                      ),
              ),
            ),
          ),
          Text(_fmt(duration), style: AppTypography.monoMuted),
        ],
      ),
    );
  }
}

class _SearchField extends StatefulWidget {
  final String query;
  final ValueChanged<String> onChanged;

  const _SearchField({required this.query, required this.onChanged});

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query,
  );

  @override
  void didUpdateWidget(covariant _SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
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
      label: '녹음 검색',
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        style: AppTypography.body,
        decoration: const InputDecoration(
          isDense: true,
          hintText: '곡 제목·코멘트로 검색',
          prefixIcon: Icon(Icons.search, color: AppColors.textMuted),
        ),
      ),
    );
  }
}

class _TakeRow extends StatelessWidget {
  final RecordingTake take;
  final bool playing;

  /// 재생 중일 때만 채워진다 — 플레이어 줄(시크바)용.
  final Duration? playingPosition;
  final Duration? playingDuration;
  final ValueChanged<Duration>? onSeek;
  final VoidCallback onPlay;
  final VoidCallback onStopPlay;
  final VoidCallback onEditComment;
  final ValueChanged<int> onRate;
  final VoidCallback onToggleKeep;
  final VoidCallback onDelete;
  final VoidCallback onMix;
  final VoidCallback onPlayMix;
  final VoidCallback onAnalyze;
  final VoidCallback onCorrect;

  const _TakeRow({
    required this.take,
    required this.playing,
    this.playingPosition,
    this.playingDuration,
    this.onSeek,
    required this.onPlay,
    required this.onStopPlay,
    required this.onEditComment,
    required this.onRate,
    required this.onToggleKeep,
    required this.onDelete,
    required this.onMix,
    required this.onPlayMix,
    required this.onAnalyze,
    required this.onCorrect,
  });

  static String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  static String _formatDate(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final meta =
        '${_formatDuration(take.duration)} · '
        '${formatKeyLabel(take.pitchSemitones)}';

    return Semantics(
      label:
          '${take.songTitle}, $meta, '
          '${take.isRated ? '${take.rating}점' : '미평가'}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    take.songTitle.isEmpty ? '(제목 없음)' : take.songTitle,
                    style: AppTypography.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (take.isCorrected)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text('AI 보정본', style: AppTypography.emphasis),
                  ),
                if (take.isKeep)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    // 색만이 아니라 텍스트로도 상태를 알린다.
                    child: Text('보관', style: AppTypography.emphasis),
                  ),
                Text(_formatDate(take.recordedAt), style: AppTypography.monoMuted),
              ],
            ),
            const SizedBox(height: 4),
            Text(meta, style: AppTypography.monoMuted),
            if (take.hasComment) ...[
              const SizedBox(height: 6),
              Text(take.comment, style: AppTypography.bodyMuted),
            ],
            const SizedBox(height: 8),
            _StarRating(rating: take.rating, onRate: onRate),
            // 재생 중이면 플레이어 줄 — 시크바 + 위치/길이.
            if (playing) ...[
              const SizedBox(height: 6),
              _TakePlayerBar(
                position: playingPosition ?? Duration.zero,
                duration: (playingDuration ?? Duration.zero) > Duration.zero
                    ? playingDuration!
                    : take.duration,
                onSeek: onSeek,
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: playing ? onStopPlay : onPlay,
                  icon: Icon(playing ? Icons.stop : Icons.play_arrow),
                  label: Text(playing ? '정지' : '듣기'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(96, AppConstants.minTouchTarget),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onEditComment,
                  icon: const Icon(Icons.edit_note),
                  label: const Text('코멘트'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(110, AppConstants.minTouchTarget),
                    side: const BorderSide(
                      color: AppColors.borderStrong,
                      width: 2,
                    ),
                  ),
                ),
                OutlinedButton(
                  onPressed: onToggleKeep,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(88, AppConstants.minTouchTarget),
                    side: const BorderSide(
                      color: AppColors.borderStrong,
                      width: 2,
                    ),
                  ),
                  child: Text(take.isKeep ? '보관 해제' : '보관'),
                ),
                OutlinedButton.icon(
                  onPressed: onAnalyze,
                  icon: const Icon(Icons.music_note),
                  label: const Text('음정 체크'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(120, AppConstants.minTouchTarget),
                    side: const BorderSide(
                      color: AppColors.borderStrong,
                      width: 2,
                    ),
                  ),
                ),
                if (!take.isCorrected)
                  OutlinedButton.icon(
                    onPressed: onCorrect,
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('AI 보정'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(110, AppConstants.minTouchTarget),
                      side: const BorderSide(
                        color: AppColors.borderStrong,
                        width: 2,
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: onMix,
                  icon: const Icon(Icons.merge_type),
                  label: Text(take.hasMix ? '다시 합치기' : '반주와 합치기'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(130, AppConstants.minTouchTarget),
                    side: const BorderSide(
                      color: AppColors.borderStrong,
                      width: 2,
                    ),
                  ),
                ),
                if (take.hasMix)
                  OutlinedButton.icon(
                    onPressed: onPlayMix,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('합친 곡 듣기'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(120, AppConstants.minTouchTarget),
                      side: const BorderSide(
                        color: AppColors.borderStrong,
                        width: 2,
                      ),
                    ),
                  ),
                OutlinedButton(
                  onPressed: onDelete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    minimumSize: const Size(80, AppConstants.minTouchTarget),
                    side: const BorderSide(color: AppColors.danger, width: 2),
                  ),
                  child: const Text('삭제'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StarRating extends StatelessWidget {
  final int rating;
  final ValueChanged<int> onRate;

  const _StarRating({required this.rating, required this.onRate});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= 5; i++)
          Semantics(
            button: true,
            selected: rating >= i,
            label: '$i점 주기',
            child: IconButton(
              icon: Icon(rating >= i ? Icons.star : Icons.star_border),
              color: rating >= i ? AppColors.tertiary : AppColors.textMuted,
              tooltip: '$i점',
              constraints: const BoxConstraints(
                minWidth: AppConstants.minTouchTarget,
                minHeight: AppConstants.minTouchTarget,
              ),
              // 같은 별을 다시 누르면 평가를 취소한다.
              onPressed: () => onRate(rating == i ? 0 : i),
            ),
          ),
        const SizedBox(width: 8),
        Text(
          rating == 0 ? '미평가' : '$rating점',
          style: AppTypography.monoMuted,
        ),
      ],
    );
  }
}
