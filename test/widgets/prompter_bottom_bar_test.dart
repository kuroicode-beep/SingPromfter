// file: test/widgets/prompter_bottom_bar_test.dart
//
// 홈 조작판(하단 바) — 좁은 창에서도 넘치지 않고, 손잡이로 여닫힌다.
//
// v2.10.0에서 우상단의 [곡 시작]·[곡 추가]·서버 상태 칩을 이 줄로 옮기면서
// 고정 폭 합계가 크게 늘었다. 홈은 3열(내비게이션·목록·조작판)이라 조작판이
// 받는 폭은 창 폭의 일부뿐이다 — 그래서 실제 폭으로 재는 테스트가 필요하다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/prompter_settings.dart';
import 'package:singpromfter_app/widgets/prompter_bottom_bar.dart';
import 'package:singpromfter_app/widgets/prompter_drawer.dart';

import '../fakes/fake_playback.dart';

void main() {
  setUp(mockAudioChannels);

  /// 조작판을 [width]만큼의 폭에 넣고 띄운다.
  /// 홈 화면에서 조작판이 실제로 받는 폭을 흉내내기 위해 Center+SizedBox로 조인다.
  Future<FakePlayback> pumpBar(
    WidgetTester tester, {
    required double width,
    bool drawerOpen = false,
    ValueChanged<bool>? onDrawerChanged,
  }) async {
    final fake = buildFakePlayback(song: fakeSong());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: PrompterBottomBar(
                song: fakeSong(),
                playing: false,
                audioReady: true,
                hasQueuedSongs: false,
                duration: const Duration(minutes: 3),
                playback: fake.controller,
                settings: const PrompterSettings(),
                drawerOpen: drawerOpen,
                onDrawerChanged: onDrawerChanged ?? (_) {},
                onStop: () {},
                onTogglePlayPause: () {},
                onRestart: () {},
                onSkipNext: () {},
                onOpenPrompter: () {},
                onSeek: (_) {},
                onSettingsChanged: (_) {},
                onMessage: (_) {},
                hasSyncedLyrics: false,
                lyricsOffsetMs: 0,
                onFetchSyncedLyrics: () {},
                onImportLrcFile: () {},
                onAdjustLyricsOffset: (_) {},
                pitchSemitones: 0,
                onAdjustPitch: (_) {},
                tempoScale: 1.0,
                onAdjustTempo: (_) {},
                isRecording: false,
                recordingLevelLabel: '',
                recordingElapsed: Duration.zero,
                onToggleRecording: () {},
                // v2.10.0에서 옮겨 온 두 개 — 이게 있을 때가 가장 넓다.
                onAddSong: () {},
                onStartSeparator: () async => true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  // 홈 3열에서 조작판이 실제로 받는 폭대. 1280 창에서도 조작판은 600 남짓이다.
  for (final width in [560.0, 640.0, 720.0]) {
    testWidgets('폭 ${width.toInt()}에서 조작판 줄이 넘치지 않는다', (tester) async {
      final fake = await pumpBar(tester, width: width);

      // 오버플로는 FlutterError로 잡힌다 — 조용히 잘린 채 배포되지 않게.
      expect(
        tester.takeException(),
        isNull,
        reason: '조작판 첫 줄이 폭 $width에서 넘쳤다',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      fake.dispose();
    });
  }

  testWidgets('펼친 조작판은 받은 높이 몫을 넘지 않는다 — 가사 뷰를 밀어내지 않게', (
    tester,
  ) async {
    // 홈 패널을 흉내낸다: 위는 가사 자리(Expanded), 아래가 조작판.
    // 상한이 없던 v2.10.0에서는 조작판이 514px를 먹어 가사가 사라지고
    // 좁은 창에서는 아래가 잘렸다.
    const panelHeight = 560.0;
    final fake = buildFakePlayback(song: fakeSong());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 720,
              height: panelHeight,
              child: Column(
                children: [
                  const Expanded(
                    child: ColoredBox(
                      key: Key('가사자리'),
                      color: Colors.black,
                    ),
                  ),
                  PrompterBottomBar(
                    song: fakeSong(),
                    playing: false,
                    audioReady: true,
                    hasQueuedSongs: false,
                    duration: const Duration(minutes: 3),
                    playback: fake.controller,
                    settings: const PrompterSettings(),
                    drawerOpen: true,
                    onDrawerChanged: (_) {},
                    maxDrawerBodyHeight: drawerBodyBudget(panelHeight),
                    onStop: () {},
                    onTogglePlayPause: () {},
                    onRestart: () {},
                    onSkipNext: () {},
                    onOpenPrompter: () {},
                    onSeek: (_) {},
                    onSettingsChanged: (_) {},
                    onMessage: (_) {},
                    hasSyncedLyrics: false,
                    lyricsOffsetMs: 0,
                    onFetchSyncedLyrics: () {},
                    onImportLrcFile: () {},
                    onAdjustLyricsOffset: (_) {},
                    pitchSemitones: 0,
                    onAdjustPitch: (_) {},
                    tempoScale: 1.0,
                    onAdjustTempo: (_) {},
                    isRecording: false,
                    recordingLevelLabel: '',
                    recordingElapsed: Duration.zero,
                    onToggleRecording: () {},
                    onAddSong: () {},
                    onStartSeparator: () async => true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '조작판을 펼쳤더니 세로로 넘쳤다');

    // 가사 자리가 살아 있어야 한다 — 0이면 화면이 망가진 것과 같다.
    final lyricsHeight = tester.getSize(find.byKey(const Key('가사자리'))).height;
    expect(lyricsHeight, greaterThan(panelHeight * 0.25));

    await tester.pumpWidget(const SizedBox.shrink());
    fake.dispose();
  });

  testWidgets('손잡이를 누르면 열림 상태를 알린다', (tester) async {
    bool? reported;
    final fake = await pumpBar(
      tester,
      width: 720,
      onDrawerChanged: (v) => reported = v,
    );

    await tester.tap(find.text('조작판 열기'));
    await tester.pump();
    expect(reported, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    fake.dispose();
  });

  testWidgets('열린 조작판은 키·싱크 줄을 실제로 보여 준다', (tester) async {
    final fake = await pumpBar(tester, width: 720, drawerOpen: true);

    expect(find.text('조작판 닫기'), findsOneWidget);
    expect(find.textContaining('키'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    fake.dispose();
  });
}
