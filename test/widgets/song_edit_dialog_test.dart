// file: test/widgets/song_edit_dialog_test.dart
//
// 곡 수정 다이얼로그의 트랙별 재생 키 조절(v3.2.0) 검증.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/dialogs/song_edit_dialog.dart';
import 'package:singpromfter_app/models/backing_track.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/models/song_draft.dart';
import 'package:singpromfter_app/theme/app_theme.dart';
import 'package:singpromfter_app/utils/music_key.dart';

Song _song({List<BackingTrack>? tracks, MusicKey? musicalKey}) {
  final now = DateTime(2026, 7, 30);
  return Song(
    id: 's1',
    title: '테스트 곡',
    lyricsPath: 's1.txt',
    lyricsText: '가사',
    backingTracks:
        tracks ??
        const [BackingTrack(slot: 1, fileName: 'mr1.mp3', label: '원곡')],
    createdAt: now,
    updatedAt: now,
    musicalKey: musicalKey,
  );
}

void main() {
  // 다이얼로그가 닫힐 때 채워진다. 열려 있는 동안 await하면 교착이라
  // onPressed 안에서만 기다린다.
  SongEditDraft? result;

  Future<void> openDialog(
    WidgetTester tester,
    Song song, {
    Map<int, int> trackPitches = const {},
  }) async {
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await SongEditDialog.show(
                  context,
                  song,
                  trackPitches: trackPitches,
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  testWidgets('트랙이 있는 슬롯에만 재생 키 줄이 보인다', (tester) async {
    await openDialog(tester, _song());

    // 반주1만 파일이 있으므로 재생 키 줄도 하나뿐이다.
    expect(find.text('재생 키'), findsOneWidget);
    expect(find.text('원키'), findsOneWidget);
    // 빈 슬롯은 '없음 + 추가' 한 줄로만 나온다.
    expect(find.text('없음'), findsNWidgets(3));
    expect(find.text('추가'), findsNWidgets(3));
  });

  testWidgets('구운 키는 수정 박스가 아니라 고정 뱃지다', (tester) async {
    await openDialog(
      tester,
      _song(
        tracks: const [
          BackingTrack(
            slot: 3,
            fileName: 'mr3.mp3',
            label: '키조절',
            bakedSemitones: -5,
          ),
        ],
      ),
    );

    // 예전의 '구운 키(반음)' 입력 칸은 없어야 한다.
    expect(find.text('구운 키(반음)'), findsNothing);
    expect(find.text('구운 -5'), findsOneWidget);
    // 재생 키는 여전히 조절 가능하다.
    expect(find.byTooltip('키 한 음 올리기'), findsOneWidget);
  });

  testWidgets('라벨·구간은 세부 설정을 펼쳐야 나온다', (tester) async {
    await openDialog(tester, _song());

    expect(find.text('반주 라벨'), findsNothing);
    await tester.ensureVisible(find.text('세부 설정 — 라벨·구간'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('세부 설정 — 라벨·구간'));
    await tester.pumpAndSettle();
    expect(find.text('반주 라벨'), findsOneWidget);
    expect(find.text('시작(초)'), findsOneWidget);
    expect(find.text('끝(초)'), findsOneWidget);
  });

  testWidgets('+/-로 값을 바꿔 저장하면 드래프트에 실린다', (tester) async {
    await openDialog(tester, _song(), trackPitches: {1: 2});

    // 현재 값(+2)에서 한 음 더 올린다. 스크롤 영역 아래일 수 있어
    // 화면에 끌어올린 뒤 누른다.
    expect(find.text('2키 높임'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('키 한 음 올리기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('키 한 음 올리기'));
    await tester.pump();
    expect(find.text('3키 높임'), findsOneWidget);

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(result?.trackPitchSemitones[1], 3);
  });

  testWidgets('조성을 알면 실효 조성(구운 키+재생 키)을 함께 보여준다', (tester) async {
    await openDialog(
      tester,
      _song(
        tracks: const [
          BackingTrack(
            slot: 1,
            fileName: 'mr1.mp3',
            label: '키조절',
            bakedSemitones: 1,
          ),
        ],
        musicalKey: const MusicKey(0, KeyMode.major), // C
      ),
      trackPitches: {1: 2},
    );

    // C + 구운 1 + 재생 2 = 실효 E♭(+3).
    expect(find.text('실효 E♭ (+3)'), findsOneWidget);
  });
}
