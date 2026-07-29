// file: lib/widgets/youtube_search_panel.dart
//
// 곡 검색 탭의 유튜브 쪽 — 검색어가 있으면 검색 결과, 비어 있으면 인기 차트
// (인기곡 / 노래방 인기)를 보여 준다. 결과 행마다 [가져오기](새 곡, 기본
// 3슬롯)와 [4번 슬롯](기존 곡에 노래방 반주) 두 버튼이 붙는다.
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
enum YoutubeChartKind { popular, karaoke }

extension YoutubeChartKindInfo on YoutubeChartKind {
  String get label => switch (this) {
    YoutubeChartKind.popular => '인기곡',
    YoutubeChartKind.karaoke => '노래방 인기',
  };
}

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

  const YoutubeSearchViewState({
    this.query = '',
    this.status = YoutubeFetchStatus.ok,
    this.results = const [],
    this.loading = false,
    this.chart = YoutubeChartKind.popular,
    this.apiKeyAvailable = true,
    this.message,
  });
}

class YoutubeSearchPanel extends StatefulWidget {
  final YoutubeSearchViewState state;

  /// Enter/검색 버튼에서만 불린다. 빈 문자열이면 차트 모드로 돌아간다.
  final ValueChanged<String> onSearch;
  final ValueChanged<YoutubeChartKind> onChartChanged;

  /// [가져오기] — 새 곡으로 등록(기본 3슬롯 파이프라인).
  final ValueChanged<YoutubeVideo> onImport;

  /// [4번 슬롯] — 기존 곡을 골라 노래방 반주로 붙인다.
  final ValueChanged<YoutubeVideo> onKaraokeImport;

  const YoutubeSearchPanel({
    super.key,
    required this.state,
    required this.onSearch,
    required this.onChartChanged,
    required this.onImport,
    required this.onKaraokeImport,
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
          if (chartMode)
            Wrap(
              spacing: 8,
              children: [
                for (final kind in YoutubeChartKind.values)
                  _ChartChip(
                    label: kind.label,
                    selected: state.chart == kind,
                    onTap: () => widget.onChartChanged(kind),
                  ),
              ],
            ),
          if (chartMode) const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(child: _buildBody(state)),
          const SizedBox(height: 6),
          Text(
            '저작권 안내: 내려받은 음원은 본인 연습 용도로만 사용하세요.',
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
      return Center(
        child: Text('검색 결과가 없습니다', style: AppTypography.bodyMuted),
      );
    }
    return ListView.separated(
      itemCount: state.results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _VideoRow(
        video: state.results[index],
        onImport: () => widget.onImport(state.results[index]),
        onKaraokeImport: () => widget.onKaraokeImport(state.results[index]),
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
  final VoidCallback onKaraokeImport;

  const _VideoRow({
    required this.video,
    required this.onImport,
    required this.onKaraokeImport,
  });

  @override
  Widget build(BuildContext context) {
    final thumbnail = video.thumbnailUrl;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
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
                Text(
                  video.title,
                  style: AppTypography.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
          const SizedBox(width: 8),
          Semantics(
            label: '${video.title} 새 곡으로 가져오기',
            child: OutlinedButton(
              onPressed: onImport,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(84, AppConstants.minTouchTarget),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text('가져오기'),
            ),
          ),
          const SizedBox(width: 6),
          Semantics(
            label: '${video.title} 기존 곡의 4번 노래방 슬롯으로 가져오기',
            child: FilledButton(
              onPressed: onKaraokeImport,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: AppColors.onPrimaryContainer,
                minimumSize: const Size(84, AppConstants.minTouchTarget),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text('4번 슬롯'),
            ),
          ),
        ],
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
