// file: lib/widgets/search_hub_panel.dart
//
// 곡 검색 탭의 최상위 — [내 곡 | 유튜브] 전환만 담당하는 조립 위젯.
// 기존 SongSearchPanel은 손대지 않고 위에 한 겹 얹는다(기존 테스트 보존).
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../theme/app_theme.dart';

/// 검색 대상.
enum SearchSource { mySongs, youtube }

extension SearchSourceInfo on SearchSource {
  String get label => switch (this) {
    SearchSource.mySongs => '내 곡',
    SearchSource.youtube => '유튜브',
  };
}

class SearchHubPanel extends StatelessWidget {
  final SearchSource source;
  final ValueChanged<SearchSource> onSourceChanged;
  final Widget mySongsPanel;
  final Widget youtubePanel;

  const SearchHubPanel({
    super.key,
    required this.source,
    required this.onSourceChanged,
    required this.mySongsPanel,
    required this.youtubePanel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<SearchSource>(
              segments: [
                for (final s in SearchSource.values)
                  ButtonSegment(
                    value: s,
                    label: Text(s.label, style: AppTypography.body),
                  ),
              ],
              selected: {source},
              onSelectionChanged: (selection) =>
                  onSourceChanged(selection.first),
              style: ButtonStyle(
                minimumSize: WidgetStateProperty.all(
                  const Size(0, AppConstants.minTouchTarget),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: switch (source) {
            SearchSource.mySongs => mySongsPanel,
            SearchSource.youtube => youtubePanel,
          },
        ),
      ],
    );
  }
}
