import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/controllers/playback_controller.dart';
import 'package:singpromfter_app/screens/prompter_screen.dart';
import 'package:singpromfter_app/models/timed_lyrics.dart';
import 'package:singpromfter_app/widgets/prompter_eq_meter.dart';

import '../fakes/fake_playback.dart';

// 전체화면 프롬프터(무대) 회귀 테스트.
//
// v2.8.2까지 이 화면은 위젯 테스트가 0건이었다 — 드로어 상태가 widget 값에
// 얼어붙어 손잡이를 눌러도 꿈쩍하지 않는 버그가 테스트 없이 지나간 이유다.
// FakePlayback(test/fakes)으로 그 공백을 메운다.
void main() {
  setUp(mockAudioChannels);

  Future<void> pumpStage(
    WidgetTester tester, {
    required PrompterScreenArgs args,
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: args.build()));
    await tester.pump();
  }

  testWidgets('드로어는 닫힌 채 시작하고 손잡이로 열린다 (v2.8.2 얼음 버그 회귀)', (
    tester,
  ) async {
    final fake = buildFakePlayback(song: fakeSong());
    final playback = fake.controller;
    bool? reported;
    await pumpStage(
      tester,
      args: PrompterScreenArgs(
        playback: playback,
        controlsDrawerOpen: false,
        onControlsDrawerChanged: (open) => reported = open,
      ),
    );

    // 닫힘 상태 — 손잡이는 "열기"를 말한다.
    expect(find.text('조작판 열기'), findsOneWidget);

    await tester.tap(find.text('조작판 열기'));
    await tester.pumpAndSettle();

    // 화면이 실제로 열렸고(라벨 반전) 설정 콜백도 불렸다.
    // 얼음 버그에서는 콜백만 불리고 화면은 그대로였다.
    expect(find.text('조작판 닫기'), findsOneWidget);
    expect(reported, isTrue);

    await tester.tap(find.text('조작판 닫기'));
    await tester.pumpAndSettle();
    expect(find.text('조작판 열기'), findsOneWidget);
    expect(reported, isFalse);

    // flutter_test의 timersPending 검사는 addTearDown보다 먼저 돈다 —
    // 트리를 내리고 본문 안에서 정리해야 한다.
    await tester.pumpWidget(const SizedBox.shrink());
    fake.dispose();
  });

  testWidgets('EQ 미터는 드로어가 닫혀 있어도 보인다', (tester) async {
    final fake = buildFakePlayback(song: fakeSong());
    final playback = fake.controller;
    await pumpStage(
      tester,
      args: PrompterScreenArgs(
        playback: playback,
        controlsDrawerOpen: false,
        showEqMeter: true,
      ),
    );

    expect(find.byType(PrompterEqMeter), findsOneWidget);
    expect(find.text('조작판 열기'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    fake.dispose();
  });

  testWidgets('EQ 끄기 설정이면 미터가 없다', (tester) async {
    final fake = buildFakePlayback(song: fakeSong());
    final playback = fake.controller;
    await pumpStage(
      tester,
      args: PrompterScreenArgs(playback: playback, showEqMeter: false),
    );
    expect(find.byType(PrompterEqMeter), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    fake.dispose();
  });

  test('싱크 가사가 없으면 스윕 진행률은 null — 추정으로 음절을 가리키지 않는다', () {
    mockAudioChannels();
    final fake = buildFakePlayback(song: fakeSong());
    final playback = fake.controller;
    expect(playback.currentLineFraction(), isNull);
  });

  test('일시정지 중에도 오프셋 변경이 줄 인덱스에 즉시 반영된다', () {
    mockAudioChannels();
    final fake = buildFakePlayback(song: fakeSong());
    final playback = fake.controller;
    playback.timedLyrics.value = LrcParser.parse(
      '[00:10.00]첫 줄\n[00:20.00]둘째 줄\n[00:30.00]셋째 줄',
    );
    // 정지 상태(틱 없음)에서 위치 25초로 고정.
    playback.position.value = const Duration(seconds: 25);
    playback.applyLyricsOffset(0);
    expect(playback.lineIndex.value, 1, reason: '25초 = 둘째 줄');

    // 오프셋 +12초(가사 늦춤) → songTime 13초 = 첫 줄. 틱 없이 즉시 반영돼야
    // 한다 — 위치 틱에만 맡기면 일시정지 중 T·./가 "안 먹음"으로 보인다.
    playback.applyLyricsOffset(12000);
    expect(playback.lineIndex.value, 0);

    // 리셋(T) — 다시 둘째 줄.
    playback.applyLyricsOffset(0);
    expect(playback.lineIndex.value, 1);

    fake.dispose();
  });
}

/// PrompterScreen 인자 묶음 — 테스트마다 같은 기본값을 반복하지 않기 위한 헬퍼.
class PrompterScreenArgs {
  final PlaybackController playback;
  final bool controlsDrawerOpen;
  final bool showEqMeter;
  final ValueChanged<bool>? onControlsDrawerChanged;

  PrompterScreenArgs({
    required this.playback,
    this.controlsDrawerOpen = false,
    this.showEqMeter = true,
    this.onControlsDrawerChanged,
  });

  Widget build() => PrompterScreen(
    song: fakeSong(),
    playback: playback,
    fontSize: 24,
    lineHeight: 1.5,
    controlsDrawerOpen: controlsDrawerOpen,
    showEqMeter: showEqMeter,
    onControlsDrawerChanged: onControlsDrawerChanged,
  );
}
