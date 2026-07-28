import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:singpromfter_app/constants/app_constants.dart';
import 'package:singpromfter_app/models/backing_track.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/widgets/song_tile.dart';

// 고밀도 곡 목록 행(v2.5.0) — 제목 아래 한 줄에 상태가 모두 모인다.
Song makeSong({
  String title = '테스트 곡',
  String artist = '',
  List<BackingTrack> tracks = const [],
  String? lrcFileName,
  bool favorite = false,
}) => Song(
  id: 'song-1',
  title: title,
  artist: artist,
  lyricsPath: 'test.txt',
  lyricsText: '가사',
  backingTracks: tracks,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  isFavorite: favorite,
  lrcFileName: lrcFileName,
);

Widget wrap(SongTile tile) => MaterialApp(home: Scaffold(body: tile));

SongTile buildTile({
  required Song song,
  bool selected = false,
  int pitchSemitones = 0,
  int practiceCount = 0,
  void Function(int slot)? onSelectTrack,
  int? selectedTrackSlot,
}) => SongTile(
  song: song,
  selected: selected,
  selectedTrackSlot: selectedTrackSlot,
  pitchSemitones: pitchSemitones,
  practiceCount: practiceCount,
  onSelectTrack: onSelectTrack,
  onSelect: () {},
  onStart: () {},
  onReserve: () {},
  onEdit: () {},
  onDelete: () {},
  onToggleFavorite: () {},
);

void main() {
  testWidgets('제목과 조작 아이콘을 보여준다', (tester) async {
    await tester.pumpWidget(
      wrap(buildTile(song: makeSong(favorite: true))),
    );

    expect(find.text('테스트 곡'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsOneWidget);
    // 조작은 아이콘으로 압축했다 — 이름은 툴팁/시맨틱스로 남긴다.
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.playlist_add), findsOneWidget);
  });

  testWidgets('반주가 없으면 상태줄에 그렇게 적는다', (tester) async {
    await tester.pumpWidget(wrap(buildTile(song: makeSong())));
    expect(find.text('반주 없음'), findsOneWidget);
  });

  testWidgets('가수·반주·싱크가사·키·연습횟수를 한 줄로 모은다', (tester) async {
    await tester.pumpWidget(
      wrap(
        buildTile(
          song: makeSong(
            artist: '아이유',
            tracks: const [
              BackingTrack(slot: 1, fileName: 'a.mp3', label: 'MR1'),
              BackingTrack(slot: 2, fileName: 'b.mp3', label: 'MR2'),
            ],
            lrcFileName: 'song-1.lrc',
          ),
          pitchSemitones: -2,
          practiceCount: 12,
        ),
      ),
    );

    expect(find.text('아이유 · 반주 2 · 싱크가사 · 2키 낮춤 · 12회'), findsOneWidget);
  });

  testWidgets('선택하지 않으면 수정·삭제를 감춘다', (tester) async {
    await tester.pumpWidget(wrap(buildTile(song: makeSong())));
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('선택하면 수정·삭제가 나온다', (tester) async {
    await tester.pumpWidget(
      wrap(buildTile(song: makeSong(), selected: true)),
    );
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('실제 목록 폭(300)에서 긴 제목도 넘치지 않는다', (tester) async {
    // 조작 아이콘이 한 줄에 여럿 들어가므로 좁은 패널이 진짜 위험 지점이다.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: AppConstants.homeSongListWidth,
            child: buildTile(
              song: makeSong(
                title: '아주 아주 긴 제목의 노래 제목이 계속 이어지는 경우를 위한 시험용 문자열',
                artist: '이름이 아주 긴 가수 이름',
                tracks: const [
                  BackingTrack(slot: 1, fileName: 'a.mp3', label: '원곡'),
                  BackingTrack(slot: 2, fileName: 'b.mp3', label: 'MR'),
                  BackingTrack(slot: 3, fileName: 'c.mp3', label: '키조절 2키 낮춤'),
                  BackingTrack(slot: 4, fileName: 'd.mp3', label: '노래방'),
                ],
                lrcFileName: 'song-1.lrc',
              ),
              selected: true,
              selectedTrackSlot: 1,
              pitchSemitones: 3,
              practiceCount: 999,
              onSelectTrack: (_) {},
            ),
          ),
        ),
      ),
    );
    // 오버플로가 나면 pumpWidget 단계에서 예외로 실패한다.
    expect(tester.takeException(), isNull);
  });

  testWidgets('반주가 둘 이상일 때만 슬롯 선택줄을 편다', (tester) async {
    final oneTrack = makeSong(
      tracks: const [BackingTrack(slot: 1, fileName: 'a.mp3', label: 'MR1')],
    );
    await tester.pumpWidget(
      wrap(
        buildTile(
          song: oneTrack,
          selected: true,
          selectedTrackSlot: 1,
          onSelectTrack: (_) {},
        ),
      ),
    );
    expect(find.text('MR1'), findsNothing);

    final twoTracks = makeSong(
      tracks: const [
        BackingTrack(slot: 1, fileName: 'a.mp3', label: 'MR1'),
        BackingTrack(slot: 2, fileName: 'b.mp3', label: 'MR2'),
      ],
    );
    await tester.pumpWidget(
      wrap(
        buildTile(
          song: twoTracks,
          selected: true,
          selectedTrackSlot: 1,
          onSelectTrack: (_) {},
        ),
      ),
    );
    expect(find.text('MR1'), findsOneWidget);
    expect(find.text('MR2'), findsOneWidget);
    // 선택 상태는 색만이 아니라 체크 표시로도 알린다.
    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}
