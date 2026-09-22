// file: test/widgets/prompter_bottom_bar_test.dart
//
// 홈 조작판(하단 바) — 좁은 창에서도 넘치지 않고, 손잡이로 여닫힌다.
//
// v2.10.0에서 우상단의 [곡 시작]·[곡 추가]·서버 상태 칩을 이 줄로 옮기면서
// 고정 폭 합계가 크게 늘었다. 홈은 3열(내비게이션·목록·조작판)이라 조작판이
// 받는 폭은 창 폭의 일부뿐이다 — 그래서 실제 폭으로 재는 테스트가 필요하다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/controllers/armed_capture_session.dart'
    show ArmedSessionState, armedSessionStatusLabel;
import 'package:singpromfter_app/controllers/capture_session.dart'
    show InputLevelBucket, InputLevelBucketLabel;
import 'package:singpromfter_app/models/prompter_settings.dart';
import 'package:singpromfter_app/widgets/prompter_bottom_bar.dart';
import 'package:singpromfter_app/widgets/prompter_drawer.dart';

import '../fakes/fake_playback.dart';
import '../fakes/semantics_count.dart';

Future<bool> _defaultStartSeparator() async => true;

void main() {
  setUp(mockAudioChannels);

  /// 조작판을 [width]만큼의 폭에 넣고 띄운다.
  /// 홈 화면에서 조작판이 실제로 받는 폭을 흉내내기 위해 Center+SizedBox로 조인다.
  Future<FakePlayback> pumpBar(
    WidgetTester tester, {
    required double width,
    bool drawerOpen = false,
    ValueChanged<bool>? onDrawerChanged,
    // 오버플로 검증은 재생바가 펼쳐진 상태가 대상이다(기본 숨김이므로 명시).
    PrompterSettings settings = const PrompterSettings(playbackBarOpen: true),
    // AI가 꺼지면 화면이 이 두 개를 null로 넘긴다(AiGate) — 그때 조작판에서
    // 'STT 가사 다시 생성' 버튼과 분리 서버 상태 칩이 사라져야 한다.
    VoidCallback? onSttLyrics,
    Future<bool> Function()? onStartSeparator = _defaultStartSeparator,
    bool aiWiring = true,
    bool recordArmed = false,
    bool isRecording = false,
    VoidCallback? onToggleRecordArm,
    String? armedStatusLabel,
    // 같은 트리를 다른 값으로 다시 그릴 때 넘긴다(컨트롤러를 새로 만들지 않게).
    FakePlayback? reuse,
  }) async {
    final fake = reuse ?? buildFakePlayback(song: fakeSong());
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
                settings: settings,
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
                isRecording: isRecording,
                recordArmed: recordArmed,
                onToggleRecordArm: onToggleRecordArm ?? () {},
                armedStatusLabel: armedStatusLabel,
                recordingLevelLabel: '',
                recordingElapsed: Duration.zero,
                onToggleRecording: () {},
                // v2.10.0에서 옮겨 온 두 개 — 이게 있을 때가 가장 넓다.
                onAddSong: () {},
                onStartSeparator: aiWiring ? onStartSeparator : null,
                onSttLyrics: aiWiring ? (onSttLyrics ?? () {}) : null,
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

  testWidgets('드로어를 다 접으면 하단 바가 한 줄 크롬만 남는다 — 가사에 자리를 내준다', (
    tester,
  ) async {
    // v3.0.2까지 손잡이 두 개가 세로로 쌓여 접어도 134px가 남았다 —
    // "숨겼는데 가사 창이 그대로"라는 실사용 불만의 원인.
    final fake = await pumpBar(
      tester,
      width: 720,
      settings: const PrompterSettings(),
    );

    final barHeight = tester.getSize(find.byType(PrompterBottomBar)).height;
    expect(
      barHeight,
      lessThan(90),
      reason: '접힌 하단 바는 손잡이 한 줄(50px)+여백만 남아야 한다 (실측 $barHeight)',
    );

    // 손잡이 두 개가 같은 줄(같은 y)에 나란히 있다.
    final playbackHandle = tester.getCenter(find.text('재생바 열기'));
    final controlsHandle = tester.getCenter(find.text('조작판 열기'));
    expect(playbackHandle.dy, closeTo(controlsHandle.dy, 1));

    await tester.pumpWidget(const SizedBox.shrink());
    fake.dispose();
  });

  testWidgets('재생바는 기본 숨김 — 손잡이만 보인다', (tester) async {
    final fake = await pumpBar(
      tester,
      width: 720,
      settings: const PrompterSettings(),
    );

    expect(find.text('재생바 열기'), findsOneWidget);
    // 접힌 본체는 높이 0 + 히트테스트 차단 — 트리에는 남으므로 hitTestable로 잰다.
    expect(
      find.text('곡 시작').hitTestable(),
      findsNothing,
      reason: '본체는 접혀 있어야 한다',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    fake.dispose();
  });

  testWidgets('재생바 손잡이를 누르면 설정으로 알린다', (tester) async {
    PrompterSettings? got;
    final fake = buildFakePlayback(song: fakeSong());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 720,
              child: PrompterBottomBar(
                song: fakeSong(),
                playing: false,
                audioReady: true,
                hasQueuedSongs: false,
                duration: const Duration(minutes: 3),
                playback: fake.controller,
                settings: const PrompterSettings(),
                drawerOpen: false,
                onDrawerChanged: (_) {},
                onStop: () {},
                onTogglePlayPause: () {},
                onRestart: () {},
                onSkipNext: () {},
                onOpenPrompter: () {},
                onSeek: (_) {},
                onSettingsChanged: (next) => got = next,
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
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('재생바 열기'));
    await tester.pump();

    expect(got?.playbackBarOpen, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    fake.dispose();
  });

  testWidgets('AI가 꺼지면 가사 다시 생성 버튼과 분리 서버 칩이 사라진다', (tester) async {
    final fake = await pumpBar(tester, width: 720, aiWiring: false);

    expect(find.text('가사 다시 생성'), findsNothing);
    expect(find.textContaining('분리 서버'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    fake.dispose();
  });

  testWidgets('AI가 켜져 있으면 가사 다시 생성 버튼이 보인다', (tester) async {
    final fake = await pumpBar(tester, width: 720);

    expect(find.text('가사 다시 생성'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    fake.dispose();
  });

  group('녹음 고정(Alt+R) 표시', () {
    testWidgets('고정을 켜면 글자로 알린다 — 스페이스 동작이 달라지므로', (tester) async {
      final fake = await pumpBar(tester, width: 720, recordArmed: true);
      expect(find.text('● 고정 ON'), findsOneWidget);
      fake.dispose();
    });

    testWidgets('꺼져 있으면 표시가 없다', (tester) async {
      final fake = await pumpBar(tester, width: 720);
      expect(find.text('● 고정 ON'), findsNothing);
      fake.dispose();
    });

    testWidgets('버튼으로도 켤 수 있다 — Alt 키가 안 먹는 환경 대비', (tester) async {
      var toggled = 0;
      final fake = await pumpBar(
        tester,
        width: 720,
        onToggleRecordArm: () => toggled++,
      );
      await tester.tap(
        find.bySemanticsLabel('녹음 고정 켜기 (Alt+R) — 스페이스로 재생과 녹음을 함께'),
      );
      await tester.pump();
      expect(toggled, 1);
      fake.dispose();
    });

    testWidgets('켜지면 버튼 라벨이 끄기로 바뀐다', (tester) async {
      final fake = await pumpBar(tester, width: 720, recordArmed: true);
      expect(find.bySemanticsLabel('녹음 고정 끄기 (Alt+R)'), findsOneWidget);
      fake.dispose();
    });

    testWidgets('녹음이 실제로 도는 중에는 「녹음 중」이 대신 나온다', (tester) async {
      final fake = await pumpBar(
        tester,
        width: 720,
        recordArmed: true,
        isRecording: true,
      );
      // 고정이 켜진 줄 모르는 게 제일 위험하다 — 녹음 중에도 계속 띄운다.
      expect(find.text('● 고정 ON'), findsOneWidget);
      expect(find.text('● 녹음 중'), findsOneWidget);
      fake.dispose();
    });
  });

  group('녹음 고정 — 마이크 상태 문구(armedStatusLabel, v5.16.0)', () {
    const opening = '● 고정 — 마이크 여는 중';
    const ready = '● 고정 ON · 마이크 열림 · 입력 좋음';
    const lost = '● 고정 — 마이크 끊김';

    testWidgets('문구를 주면 「● 고정 ON」 자리에 그 글자가 나온다', (tester) async {
      final fake = await pumpBar(
        tester,
        width: 720,
        recordArmed: true,
        armedStatusLabel: ready,
      );
      expect(find.text(ready), findsOneWidget);
      expect(find.text('● 고정 ON'), findsNothing);
      fake.dispose();
    });

    testWidgets('문구가 없으면 예전 글자 그대로다', (tester) async {
      final fake = await pumpBar(tester, width: 720, recordArmed: true);
      expect(find.text('● 고정 ON'), findsOneWidget);
      fake.dispose();
    });

    testWidgets('고정이 꺼져 있으면 문구를 줘도 안 나온다', (tester) async {
      final fake = await pumpBar(tester, width: 720, armedStatusLabel: ready);
      expect(find.text(ready), findsNothing);
      fake.dispose();
    });

    testWidgets('🔴 문구가 바뀌어도 시맨틱스 노드가 생기거나 사라지지 않는다', (tester) async {
      // 떴다 사라지는 접근성 노드가 엔진 크래시를 냈다(center_alert.dart 머리말).
      // 상태 글자는 같은 Text의 문자열만 바뀌어야 하고, 그 글자 자체는 트리에 없어야 한다.
      final handle = tester.ensureSemantics();
      final fake = await pumpBar(
        tester,
        width: 720,
        recordArmed: true,
        armedStatusLabel: opening,
      );
      final textWidget = tester.widget<Text>(find.text(opening));
      final before = countSemanticsNodes(tester);
      expect(find.bySemanticsLabel(opening), findsNothing);

      await pumpBar(
        tester,
        width: 720,
        recordArmed: true,
        armedStatusLabel: ready,
        reuse: fake,
      );
      expect(find.text(ready), findsOneWidget);
      expect(find.text(opening), findsNothing);
      expect(countSemanticsNodes(tester), before);
      expect(find.bySemanticsLabel(ready), findsNothing);
      // 같은 자리의 같은 위젯 종류다(새 위젯을 끼운 게 아니라 글자만 바뀌었다).
      expect(tester.widget<Text>(find.text(ready)).style, textWidget.style);

      await pumpBar(
        tester,
        width: 720,
        recordArmed: true,
        armedStatusLabel: lost,
        reuse: fake,
      );
      expect(find.text(lost), findsOneWidget);
      expect(countSemanticsNodes(tester), before);

      handle.dispose();
      fake.dispose();
    });

    testWidgets('상태는 고정 버튼의 스크린리더 라벨에 덧붙는다(●와 입력 레벨은 뗀다)', (tester) async {
      final fake = await pumpBar(
        tester,
        width: 720,
        recordArmed: true,
        armedStatusLabel: ready,
      );
      expect(
        find.bySemanticsLabel('녹음 고정 끄기 (Alt+R) — 고정 ON · 마이크 열림'),
        findsOneWidget,
      );
      // 입력 레벨은 라벨 어디에도 없다 — 글자에만 있다.
      expect(find.bySemanticsLabel(RegExp('입력 좋음')), findsNothing);
      expect(find.text(ready), findsOneWidget);
      fake.dispose();
    });

    testWidgets('🔴 입력 레벨이 좋음→작음→없음으로 뒤집혀도 라벨·노드 수는 그대로, 글자만 바뀐다', (
      tester,
    ) async {
      // 레벨 버킷은 최근 2초의 최대값이라 소절 사이마다 뒤집힌다. 그때마다 라벨이
      // 바뀌면 접근성 브리지로 갱신이 나간다 — 크래시가 난 길이다.
      final handle = tester.ensureSemantics();
      const spoken = '녹음 고정 끄기 (Alt+R) — 고정 ON · 마이크 열림';
      FakePlayback? fake;
      int? nodes;
      for (final bucket in InputLevelBucket.values.reversed) {
        final label = armedSessionStatusLabel(
          state: ArmedSessionState.live,
          checked: true,
          bucket: bucket,
        );
        fake = await pumpBar(
          tester,
          width: 720,
          recordArmed: true,
          armedStatusLabel: label,
          reuse: fake,
        );
        // 보이는 글자는 레벨까지 그대로 말한다.
        expect(find.text(label), findsOneWidget);
        expect(label, contains(bucket.label));
        // 스크린리더 라벨은 한 글자도 안 바뀐다.
        expect(find.bySemanticsLabel(spoken), findsOneWidget);
        nodes ??= countSemanticsNodes(tester);
        expect(countSemanticsNodes(tester), nodes, reason: bucket.label);
      }
      handle.dispose();
      fake!.dispose();
    });

    test('armedButtonSemanticsLabel — 문구가 없으면 기본 라벨', () {
      expect(armedButtonSemanticsLabel(null), '녹음 고정 끄기 (Alt+R)');
      expect(armedButtonSemanticsLabel(''), '녹음 고정 끄기 (Alt+R)');
      expect(armedButtonSemanticsLabel(lost), '녹음 고정 끄기 (Alt+R) — 고정 — 마이크 끊김');
    });

    test('armedButtonSemanticsLabel — 세션이 만드는 모든 문구에서 라벨은 세 가지뿐이다', () {
      // 세션의 실제 문구(armedSessionStatusLabel)로 돌린다 — 문구가 바뀌면 여기서 걸린다.
      final labels = <String>{
        for (final state in ArmedSessionState.values)
          if (state != ArmedSessionState.off)
            for (final checked in [false, true])
              for (final bucket in InputLevelBucket.values)
                armedButtonSemanticsLabel(
                  armedSessionStatusLabel(
                    state: state,
                    checked: checked,
                    bucket: bucket,
                  ),
                ),
      };
      expect(labels, {
        '녹음 고정 끄기 (Alt+R) — 고정 — 마이크 여는 중',
        '녹음 고정 끄기 (Alt+R) — 고정 ON · 마이크 열림',
        '녹음 고정 끄기 (Alt+R) — 고정 — 마이크 끊김',
      });
      for (final label in labels) {
        expect(label, isNot(contains('입력')));
      }
    });

    for (final width in [560.0, 640.0]) {
      testWidgets('폭 ${width.toInt()}에서 가장 긴 문구 + 녹음 중 표시가 넘치지 않는다', (
        tester,
      ) async {
        final fake = await pumpBar(
          tester,
          width: width,
          recordArmed: true,
          isRecording: true,
          armedStatusLabel: ready,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        fake.dispose();
      });
    }
  });
}
