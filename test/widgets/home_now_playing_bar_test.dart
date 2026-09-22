// file: test/widgets/home_now_playing_bar_test.dart
//
// 홈 상단 Now Playing 줄 — 곡·반주 글자 끝에 「재생: 위치 보정본」이 붙는다.
// 🔴 색이 아니라 **글자**로 알리고, 글자가 붙고 떨어져도 시맨틱스 노드 수는 그대로다
// (생겼다 사라지는 접근성 노드가 엔진 크래시를 냈다 — center_alert.dart 머리말).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/backing_track.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/utils/playback_copy_plan.dart';
import 'package:singpromfter_app/widgets/home_now_playing_bar.dart';

import '../fakes/semantics_count.dart';

Song _song({bool withTrack = true}) {
  final now = DateTime(2026, 9, 22);
  return Song(
    id: 's1',
    title: '내 남자친구에게',
    artist: '테스트',
    lyricsPath: '',
    lyricsText: '가사',
    backingTracks: withTrack
        ? const [BackingTrack(slot: 1, fileName: 'a_mr1.mp3', label: '원곡')]
        : const [],
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('nowPlayingTrackLabel', () {
    test('보정본을 쓸 때만 끝에 글자가 붙는다', () {
      expect(nowPlayingTrackLabel(_song(), 1), '반주 1 · 원곡');
      expect(
        nowPlayingTrackLabel(
          _song(),
          1,
          playbackNote: playbackSourceNote(PlaybackSourceKind.seekCopy),
        ),
        '반주 1 · 원곡 · 재생: 위치 보정본',
      );
      expect(
        nowPlayingTrackLabel(
          _song(),
          1,
          playbackNote: playbackSourceNote(PlaybackSourceKind.vbrOriginal),
        ),
        '반주 1 · 원곡',
      );
    });

    test('재생 파일이 없는 상태(가사 전용·미선택)에는 붙지 않는다', () {
      expect(
        nowPlayingTrackLabel(_song(withTrack: false), null, playbackNote: '메모'),
        '가사 전용',
      );
      expect(nowPlayingTrackLabel(_song(), null, playbackNote: '메모'), '반주 미선택');
      expect(nowPlayingTrackLabel(null, 1, playbackNote: '메모'), isNull);
    });
  });

  testWidgets('글자가 한 줄 안에 같이 실린다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeNowPlayingBar(
            song: _song(),
            selectedTrackSlot: 1,
            playing: true,
            playbackNote: '재생: 위치 보정본',
          ),
        ),
      ),
    );
    expect(
      find.text('재생 중: 내 남자친구에게 · 반주 1 · 원곡 · 재생: 위치 보정본'),
      findsOneWidget,
    );
  });

  testWidgets('🔴 글자가 붙고 떨어져도 시맨틱스 노드 수가 그대로다', (tester) async {
    final handle = tester.ensureSemantics();
    Future<int> count(String? note) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeNowPlayingBar(
              song: _song(),
              selectedTrackSlot: 1,
              playing: false,
              playbackNote: note,
            ),
          ),
        ),
      );
      return countSemanticsNodes(tester);
    }

    final without = await count(null);
    final withNote = await count('재생: 위치 보정본');
    final back = await count(null);

    expect(withNote, without);
    expect(back, without);
    handle.dispose();
  });
}
