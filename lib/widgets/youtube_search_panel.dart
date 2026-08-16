// file: lib/widgets/youtube_search_panel.dart
//
// 곡 검색 탭의 유튜브 쪽 — 검색어가 있으면 검색 결과, 비어 있으면 인기 차트
// (인기곡 / 노래방 인기)를 보여 준다. 결과 행의 [가져오기] 버튼 하나가
// 구성 팝업(기본/남자키/4번슬롯)을 연다 — YoutubeImportDialog.
//
// 검색은 Enter/버튼에서만 실행한다 — search.list가 1회 100유닛이라
// 타이핑 즉시 검색은 하루 한도를 몇 분 만에 소진한다.
//
// 상태는 화면(State)이 소유하고 여기는 controlled로 그린다. 이 패널은
// 목적지를 오갈 때 재생성되므로 자체 상태로는 결과·차트 캐시를 못 지킨다.
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../services/youtube_data_client.dart';
import '../theme/app_theme.dart';

// 이 패널의 공개 API(YoutubeSearchViewState·콜백)가 쓰는 타입들 —
// 호출부가 클라이언트를 따로 import하지 않아도 되게 함께 내보낸다.
export '../services/youtube_data_client.dart'
    show YoutubeVideo, YoutubeFetchStatus;

/// 검색어가 비었을 때 보여 줄 차트.
enum YoutubeChartKind { domestic, global, karaoke, decade }

extension YoutubeChartKindInfo on YoutubeChartKind {
  String get label => switch (this) {
    YoutubeChartKind.domestic => '국내 TOP100',
    YoutubeChartKind.global => '글로벌 TOP100',
    YoutubeChartKind.karaoke => '노래방 인기',
    YoutubeChartKind.decade => '연도별·장르',
  };
}

/// 연도별 차트의 연대 선택지.
const youtubeDecades = [1980, 1990, 2000, 2010, 2020];

/// 연도별 차트의 장르 선택지 — '전체'는 장르 없이 연대만.
const youtubeGenres = ['전체', '발라드', '댄스', '트로트', '힙합', 'R&B'];

/// 화면(State)이 소유한 유튜브 검색 상태 묶음 — props 폭발을 막는 값 객체.
@immutable
class YoutubeSearchViewState {
  final String query;
  final YoutubeFetchStatus status;
  final List<YoutubeVideo> results;
  final bool loading;
  final YoutubeChartKind chart;
  final bool apiKeyAvailable;

  /// failed일 때 사용자에게 보여 줄 사유.
  final String? message;

  /// 노래방 자동 검색의 대상 곡 제목 — 있으면 배너로 안내하고
  /// [가져오기]가 그 곡 4번 슬롯으로 직행한다.
  final String? karaokeTargetTitle;

  /// 연도별 차트의 현재 연대·장르.
  final int decade;
  final String genre;

  const YoutubeSearchViewState({
    this.query = '',
    this.status = YoutubeFetchStatus.ok,
    this.results = const [],
    this.loading = false,
    this.chart = YoutubeChartKind.domestic,
    this.apiKeyAvailable = true,
    this.message,
    this.karaokeTargetTitle,
    this.decade = 2020,
    this.genre = '전체',
  });
}

class YoutubeSearchPanel extends StatefulWidget {
  final YoutubeSearchViewState state;

  /// Enter/검색 버튼에서만 불린다. 빈 문자열이면 차트 모드로 돌아간다.
  final ValueChanged<String> onSearch;
  final ValueChanged<YoutubeChartKind> onChartChanged;

  /// [가져오기] — 팝업으로 구성(기본/남자키/4번슬롯)을 골라 가져온다.
  final ValueChanged<YoutubeVideo> onImport;

  /// 노래방 자동 검색 배너의 [취소].
  final VoidCallback? onCancelKaraokeTarget;

  /// 연도별 차트 — 연대/장르 선택과 [불러오기](검색 100유닛이라 명시 버튼).
  final ValueChanged<int>? onDecadeChanged;
  final ValueChanged<String>? onGenreChanged;
  final VoidCallback? onLoadDecadeChart;

  /// [미리듣기] — 유튜브 링크를 기본 브라우저 새 창으로 연다.
  final ValueChanged<YoutubeVideo>? onPreview;

  const YoutubeSearchPanel({
    super.key,
    required this.state,
    required this.onSearch,
    required this.onChartChanged,
    required this.onImport,
    this.onCancelKaraokeTarget,
    this.onDecadeChanged,
    this.onGenreChanged,
    this.onLoadDecadeChart,
    this.onPreview,
  });

  @override
  State<YoutubeSearchPanel> createState() => _YoutubeSearchPanelState();
}

class _YoutubeSearchPanelState extends State<YoutubeSearchPanel> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.state.query,
  );

  @override
  void didUpdateWidget(covariant YoutubeSearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.query != oldWidget.state.query &&
        widget.state.query != _controller.text) {
      _controller.text = widget.state.query;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => widget.onSearch(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    if (!state.apiKeyAvailable) return _buildMissingKey();

    final chartMode = state.query.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.karaokeTargetTitle != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.selectedSurface,
                borderRadius: AppShapes.controlRadius,
                border: Border.all(color: AppColors.primary, width: 2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.mic_external_on,
                      size: 20, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "'${state.karaokeTargetTitle}' 4번 슬롯에 넣을 노래방 반주를 골라 주세요.",
                      style: AppTypography.body,
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onCancelKaraokeTarget,
                    style: TextButton.styleFrom(
                      minimumSize:
                          const Size(72, AppConstants.minTouchTarget),
                    ),
                    child: const Text('취소'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    hintText: '유튜브에서 노래 검색 (Enter)',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(84, AppConstants.minTouchTarget),
                ),
                child: const Text('검색'),
              ),
              if (!chartMode) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    _controller.clear();
                    widget.onSearch('');
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(84, AppConstants.minTouchTarget),
                  ),
                  child: const Text('차트로'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (chartMode) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in YoutubeChartKind.values)
                  _ChartChip(
                    label: kind.label,
                    selected: state.chart == kind,
                    onTap: () => widget.onChartChanged(kind),
                  ),
              ],
            ),
            if (state.chart == YoutubeChartKind.decade) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final decade in youtubeDecades)
                    _ChartChip(
                      label: '$decade년대',
                      selected: state.decade == decade,
                      onTap: () => widget.onDecadeChanged?.call(decade),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final genre in youtubeGenres)
                    _ChartChip(
                      label: genre,
                      selected: state.genre == genre,
                      onTap: () => widget.onGenreChanged?.call(genre),
                    ),
                  FilledButton.icon(
                    onPressed: widget.onLoadDecadeChart,
                    icon: const Icon(Icons.download),
                    label: const Text('불러오기'),
                    style: FilledButton.styleFrom(
                      minimumSize:
                          const Size(110, AppConstants.minTouchTarget),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
          ],
          const Divider(height: 1),
          Expanded(child: _buildBody(state)),
          const SizedBox(height: 6),
          Text(
            state.chart == YoutubeChartKind.karaoke || !chartMode
                ? '저작권 안내: 내려받은 음원은 본인 연습 용도로만 사용하세요.'
                : '유튜브 인기 음악(mostPopular) 기반 목록입니다 · '
                    '내려받은 음원은 본인 연습 용도로만 사용하세요.',
            style: AppTypography.bodyMuted,
          ),
        ],
      ),
    );
  }

  Widget _buildMissingKey() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.key_off, size: 40, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              'YOUTUBE_API_KEY 환경 변수가 없어 유튜브 검색을 쓸 수 없습니다.\n'
              '키를 설정하고 앱을 다시 시작해 주세요.',
              textAlign: TextAlign.center,
              style: AppTypography.body,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(YoutubeSearchViewState state) {
    if (state.loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (state.status == YoutubeFetchStatus.failed) {
      return Center(
        child: Text(
          state.message ?? '목록을 가져오지 못했습니다.',
          style: AppTypography.body,
          textAlign: TextAlign.center,
        ),
      );
    }
    if (state.results.isEmpty) {
      // 연도별 차트는 검색 100유닛이라 자동으로 부르지 않는다 — 안내만.
      final decadePrompt = state.query.trim().isEmpty &&
          state.chart == YoutubeChartKind.decade;
      return Center(
        child: Text(
          decadePrompt
              ? '연대와 장르를 고르고 [불러오기]를 눌러 주세요.'
              : '검색 결과가 없습니다',
          style: AppTypography.bodyMuted,
        ),
      );
    }
    return ListView.separated(
      itemCount: state.results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _VideoRow(
        video: state.results[index],
        rank: state.query.trim().isEmpty &&
                (state.chart == YoutubeChartKind.domestic ||
                    state.chart == YoutubeChartKind.global)
            ? index + 1
            : null,
        onImport: () => widget.onImport(state.results[index]),
        onPreview: widget.onPreview == null
            ? null
            : () => widget.onPreview!(state.results[index]),
      ),
    );
  }
}

/// 차트 전환 칩 — 선택 상태를 색과 함께 체크 아이콘(텍스트 외 형태)으로도 알린다.
class _ChartChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChartChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label 차트${selected ? ', 선택됨' : ''}',
      child: Material(
        color: selected ? AppColors.primaryContainer : AppColors.surfaceContainer,
        borderRadius: AppShapes.controlRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppShapes.controlRadius,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppConstants.minTouchTarget,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  const Icon(Icons.check, size: 18),
                  const SizedBox(width: 6),
                ],
                Text(label, style: AppTypography.body),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoRow extends StatelessWidget {
  final YoutubeVideo video;
  final VoidCallback onImport;

  /// TOP100 차트에서의 순위(1부터). 검색·기타 차트는 null.
  final int? rank;

  /// [미리듣기] — 브라우저 새 창으로 열기.
  final VoidCallback? onPreview;

  const _VideoRow({
    required this.video,
    required this.onImport,
    this.rank,
    this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final thumbnail = video.thumbnailUrl;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          if (rank != null)
            SizedBox(
              width: 36,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: AppTypography.mono,
              ),
            ),
          SizedBox(
            width: 80,
            height: 45,
            child: thumbnail == null
                ? const _ThumbFallback()
                : Image.network(
                    thumbnail,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _ThumbFallback(),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        video.title,
                        style: AppTypography.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 가져오기·미리듣기 — 제목 바로 뒤에 작은 아이콘 두 개를
                    // 나란히(v5.4.0 이동 → v5.5.0 축소·병렬). 시각 40px이지만
                    // 히트 영역은 Material padded로 48px을 유지한다.
                    _RowIconButton(
                      icon: Icons.download,
                      tooltip: '가져오기',
                      semanticLabel: '${video.title} 가져오기 — 구성 선택 창 열기',
                      filled: true,
                      onTap: onImport,
                    ),
                    if (onPreview != null) ...[
                      const SizedBox(width: 4),
                      _RowIconButton(
                        icon: Icons.open_in_new,
                        tooltip: '미리듣기',
                        semanticLabel:
                            '${video.title} 미리듣기 — 브라우저 새 창으로 열기',
                        filled: false,
                        onTap: onPreview!,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        video.channelTitle,
                        style: AppTypography.bodyMuted,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (video.durationText != null) ...[
                      const SizedBox(width: 8),
                      Text(video.durationText!, style: AppTypography.mono),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 결과 행의 컴팩트 아이콘 버튼 — 제목 옆에 나란히 놓기 위해 시각 크기를
/// 40px로 줄이되, 히트 영역은 MaterialTapTargetSize.padded로 48px을 지킨다.
class _RowIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final String semanticLabel;
  final bool filled;
  final VoidCallback onTap;

  const _RowIconButton({
    required this.icon,
    required this.tooltip,
    required this.semanticLabel,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, size: 20),
          style: IconButton.styleFrom(
            backgroundColor:
                filled ? AppColors.primaryContainer : AppColors.surfaceContainer,
            foregroundColor:
                filled ? AppColors.onPrimaryContainer : AppColors.onSurfaceVariant,
            minimumSize: const Size(40, 40),
            fixedSize: const Size(40, 40),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
        ),
      ),
    );
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surfaceContainer,
      child: Icon(Icons.music_note, color: AppColors.textMuted),
    );
  }
}
