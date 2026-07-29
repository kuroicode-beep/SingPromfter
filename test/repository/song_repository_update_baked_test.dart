import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:singpromfter_app/models/backing_track.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/repository/song_repository.dart';

// updateSong이 반주의 bakedSemitones를 지우던 회귀.
//
// 증상: −2키로 구워 둔 슬롯이 songs.json에 baked=0으로 기록돼, 무대가
// 그 슬롯의 조성을 원키로 표시했다. 파일은 멀쩡하고 숫자만 틀려서
// 재생해 보기 전에는 눈치채기 어렵다.
//
// 원인: updateSong이 슬롯마다 BackingTrack을 새로 만드는데, 기존 반주를
// 유지하는 분기에서 bakedSemitones를 옮겨 담지 않아 기본값 0이 됐다.
// 편집 다이얼로그는 draft.trackBakedSemitones로 값을 다시 얹어 줘서 멀쩡했고,
// 제목·가수만 바꾸는 경로(제어 API의 sp_edit_song)에서만 터졌다.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  final repo = SongRepository.instance;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sp_repo_test');
    PathProviderPlatform.instance = _FakePathProvider(temp.path);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  /// 슬롯 [slot]에 실제 파일이 있는 곡을 만든다.
  Future<Song> songWithTrack({
    required String title,
    required int slot,
    required int baked,
    required String label,
  }) async {
    final mrDir = Directory('${temp.path}/data/mp3');
    await mrDir.create(recursive: true);
    final fileName = repo.buildBackingTrackFileName(title, slot);
    await File('${mrDir.path}/$fileName').writeAsBytes([0, 1, 2, 3]);
    final now = DateTime(2026, 7, 29);
    return Song(
      id: 'song-1',
      title: title,
      artist: '가수',
      lyricsPath: '',
      lyricsText: '한 줄',
      createdAt: now,
      updatedAt: now,
      backingTracks: [
        BackingTrack(
          slot: slot,
          fileName: fileName,
          label: label,
          bakedSemitones: baked,
        ),
      ],
    );
  }

  test('제목만 바꿔도 구운 키가 유지된다 (파일명이 함께 바뀌는 경로)', () async {
    final song = await songWithTrack(
      title: '선물(가사첨부)',
      slot: 3,
      baked: -2,
      label: '키조절 2키 낮춤',
    );

    final updated = await repo.updateSong(song: song, title: '선물');

    final track = updated.trackForSlot(3);
    expect(track, isNotNull);
    expect(track!.fileName, '선물_mr3.mp3', reason: '파일은 새 제목으로 옮겨진다');
    expect(track.bakedSemitones, -2, reason: '구운 키는 그대로여야 한다');
  });

  test('제목이 그대로면 구운 키가 유지된다 (파일명이 안 바뀌는 경로)', () async {
    final song = await songWithTrack(
      title: '선물',
      slot: 3,
      baked: -2,
      label: '키조절 2키 낮춤',
    );

    final updated = await repo.updateSong(song: song, title: '선물');

    expect(updated.trackForSlot(3)!.bakedSemitones, -2);
  });

  test('파일이 사라져도 구운 키 기록은 남는다', () async {
    final song = await songWithTrack(
      title: '선물',
      slot: 3,
      baked: -2,
      label: '키조절 2키 낮춤',
    );
    await File('${temp.path}/data/mp3/선물_mr3.mp3').delete();

    final updated = await repo.updateSong(song: song, title: '다른 제목');

    expect(updated.trackForSlot(3)!.bakedSemitones, -2);
  });

  test('구운 키가 0인 슬롯은 0 그대로', () async {
    final song = await songWithTrack(
      title: '선물',
      slot: 1,
      baked: 0,
      label: '원곡',
    );

    final updated = await repo.updateSong(song: song, title: '선물 2');

    expect(updated.trackForSlot(1)!.bakedSemitones, 0);
  });

  test('파일을 새로 넣으면 구운 키는 0으로 되돌아간다', () async {
    // 새 오디오는 사용자가 준 원본이라 구워진 키가 없다. 이건 의도된 동작이다.
    final song = await songWithTrack(
      title: '선물',
      slot: 3,
      baked: -2,
      label: '키조절 2키 낮춤',
    );
    final replacement = File('${temp.path}/새반주.mp3');
    await replacement.writeAsBytes([9, 9, 9]);

    final updated = await repo.updateSong(
      song: song,
      title: '선물',
      sourceTrackPaths: {3: replacement.path},
    );

    expect(updated.trackForSlot(3)!.bakedSemitones, 0);
  });
}
