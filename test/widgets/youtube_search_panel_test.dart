// file: test/widgets/youtube_search_panel_test.dart
//
// 유튜브 검색 패널 — 버튼 2개, 차트 칩, 키 없음 안내, Enter에서만 검색.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/theme/app_theme.dart';
import 'package:singpromfter_app/widgets/youtube_search_panel.dart';

void main() {
  const video = YoutubeVideo(
    videoId: 'v1',
    title: '선물 노래방',
    channelTitle: 'TJ노래방',
    durationText: '3:44',
  );

  Future<void> pump(
    WidgetTester tester, {
    YoutubeSearchViewState state = const YoutubeSearchViewState(),
    ValueChanged<String>? onSearch,
    ValueChanged<YoutubeChartKind>? onChartChanged,
    ValueChanged<YoutubeVideo>? onImport,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: YoutubeSearchPanel(
            state: state,
            onSearch: onSearch ?? (_) {},
            onChartChanged: onChartChanged ?? (_) {},
            onImport: onImport ?? (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('결과 행의 [가져오기] 버튼 하나가 구성 선택을 연다', (tester) async {
    YoutubeVideo? imported;
    await pump(
      tester,
      state: const YoutubeSearchViewState(query: '선물', results: [video]),
      onImport: (v) => imported = v,
    );

    expect(find.text('선물 노래방'), findsOneWidget);
    expect(find.text('3:44'), findsOneWidget);
    // 버튼은 하나다 — 구성(기본/남자키/4번슬롯)은 팝업에서 고른다.
    expect(find.text('4번 슬롯'), findsNothing);

    await tester.tap(find.text('가져오기'));
    expect(imported?.videoId, 'v1');
  });

  testWidgets('검색어가 비어 있으면 차트 칩 4개가 보이고 전환을 알린다', (tester) async {
    YoutubeChartKind? changed;
    await pump(
      tester,
      state: const YoutubeSearchViewState(results: [video]),
      onChartChanged: (k) => changed = k,
    );

    expect(find.text('국내 TOP100'), findsOneWidget);
    expect(find.text('글로벌 TOP100'), findsOneWidget);
    expect(find.text('노래방 인기'), findsOneWidget);
    expect(find.text('연도별·장르'), findsOneWidget);

    await tester.tap(find.text('노래방 인기'));
    expect(changed, YoutubeChartKind.karaoke);
  });

  testWidgets('연도별 차트에서는 연대·장르 칩과 [불러오기]가 보인다', (tester) async {
    int? decade;
    String? genre;
    var loaded = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: YoutubeSearchPanel(
            state: const YoutubeSearchViewState(
              chart: YoutubeChartKind.decade,
            ),
            onSearch: (_) {},
            onChartChanged: (_) {},
            onImport: (_) {},
            onDecadeChanged: (d) => decade = d,
            onGenreChanged: (g) => genre = g,
            onLoadDecadeChart: () => loaded = true,
          ),
        ),
      ),
    );
    await tester.pump();

    // 자동 호출 금지 — 안내 문구가 보인다.
    expect(find.textContaining('불러오기'), findsWidgets);
    await tester.tap(find.text('1990년대'));
    expect(decade, 1990);
    await tester.tap(find.text('발라드'));
    expect(genre, '발라드');
    await tester.tap(find.widgetWithText(FilledButton, '불러오기'));
    expect(loaded, isTrue);
  });

  testWidgets('검색어가 있으면 차트 칩 대신 [차트로] 버튼이 나온다', (tester) async {
    String? searched;
    await pump(
      tester,
      state: const YoutubeSearchViewState(query: '선물', results: [video]),
      onSearch: (q) => searched = q,
    );

    expect(find.text('국내 TOP100'), findsNothing);
    await tester.tap(find.text('차트로'));
    expect(searched, '');
  });

  testWidgets('타이핑만으로는 검색이 실행되지 않는다 — Enter에서만', (tester) async {
    final searches = <String>[];
    await pump(tester, onSearch: searches.add);

    await tester.enterText(find.byType(TextField), '선물');
    await tester.pump();
    expect(searches, isEmpty, reason: 'search.list는 100유닛 — 증분 검색 금지');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(searches, ['선물']);
  });

  testWidgets('검색 버튼으로도 실행된다', (tester) async {
    final searches = <String>[];
    await pump(tester, onSearch: searches.add);
    await tester.enterText(find.byType(TextField), '봄이 와도');
    await tester.tap(find.text('검색'));
    expect(searches, ['봄이 와도']);
  });

  testWidgets('API 키가 없으면 안내 문구가 나오고 입력이 없다', (tester) async {
    await pump(
      tester,
      state: const YoutubeSearchViewState(apiKeyAvailable: false),
    );
    expect(find.textContaining('YOUTUBE_API_KEY'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('실패 상태면 사유를 보여 준다', (tester) async {
    await pump(
      tester,
      state: const YoutubeSearchViewState(
        query: '선물',
        status: YoutubeFetchStatus.failed,
        message: 'API 사용량 한도를 넘었거나 키에 문제가 있습니다.',
      ),
    );
    expect(find.textContaining('한도'), findsOneWidget);
  });

  testWidgets('빈 결과는 "검색 결과가 없습니다"', (tester) async {
    await pump(
      tester,
      state: const YoutubeSearchViewState(query: '없는곡'),
    );
    expect(find.text('검색 결과가 없습니다'), findsOneWidget);
  });
}
