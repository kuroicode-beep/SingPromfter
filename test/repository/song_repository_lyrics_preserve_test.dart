// file: test/repository/song_repository_lyrics_preserve_test.dart
//
// updateSong이 가사를 안 바꾼 편집에서 가사 txt를 메모리 본문으로 다시 쓰던 회귀.
//
// 증상: 로드 때 txt를 못 읽었거나(잠김·오프라인 → '') 바이트 하나가 깨져 다른
// 코드페이지로 풀린 곡을, 제목·가수·라벨·트림·폴더만 고치거나 제어 API로 편집하면
// 그 본문이 원본 txt를 영구히 덮었다. txt에는 .bak이 없고 songs.json에는 가사가 없어
// txt가 유일본이다.
//
// 🔴 실제 파일 IO를 기다리므로 plain test()다(testWidgets의 가짜 시계 금지).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/repository/song_repository.dart';

/// 임시 폴더를 Documents로 쓰게 만드는 path_provider.
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

  /// 디스크의 원본 가사 바이트 — 정상 UTF-8 한글이다.
  final original = utf8.encode('보고 싶다 이렇게 말하니까 더 보고 싶다\n너희 사진을 보고 있어도');

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sp_lyrics_keep_');
    PathProviderPlatform.instance = _FakePathProvider(temp.path);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  /// [title]의 txt를 [bytes]로 두고, 메모리 본문이 [loadedText]로 읽힌 곡을 만든다.
  Future<Song> songWithLyrics({
    required String title,
    required String loadedText,
  }) async {
    final dir = Directory('${temp.path}/data/txt');
    await dir.create(recursive: true);
    final path = '${dir.path}/${repo.buildLyricsFileName(title)}';
    await File(path).writeAsBytes(original);
    final now = DateTime(2026, 9, 22);
    return Song(
      id: 'song-1',
      title: title,
      artist: '가수',
      lyricsPath: path,
      lyricsText: loadedText,
      createdAt: now,
      updatedAt: now,
      backingTracks: const [],
    );
  }

  test('🔴 로드 때 못 읽은 곡(본문 \'\')의 제목만 바꿔도 txt 바이트가 그대로 옮겨진다', () async {
    final song = await songWithLyrics(title: '봄날', loadedText: '');

    final updated = await repo.updateSong(song: song, title: '봄날 (2)');

    expect(updated.title, '봄날 (2)');
    expect(updated.lyricsPath, endsWith('봄날 (2).txt'));
    expect(await File(updated.lyricsPath).readAsBytes(), original);
    // 옛 자리의 파일은 이동됐다.
    expect(await File(song.lyricsPath).exists(), isFalse);
  });

  test('제목이 그대로면 txt를 건드리지 않는다 — 가수·라벨·트림·폴더 편집', () async {
    final song = await songWithLyrics(title: '봄날', loadedText: '');
    final before = await File(song.lyricsPath).lastModified();

    final updated = await repo.updateSong(
      song: song,
      title: '봄날',
      artist: '다른 가수',
    );

    expect(updated.lyricsPath, song.lyricsPath);
    expect(await File(updated.lyricsPath).readAsBytes(), original);
    expect(await File(updated.lyricsPath).lastModified(), before);
  });

  test('메모리 본문과 같은 가사를 넘겨도(updateSongFields 경로) txt는 그대로다', () async {
    // 제어 API의 제목 수정은 lyrics: song.lyricsText로 부른다 — 못 읽은 세션이면 ''.
    final song = await songWithLyrics(title: '봄날', loadedText: '');

    final updated = await repo.updateSong(
      song: song,
      title: '봄날',
      lyrics: song.lyricsText,
    );

    expect(await File(updated.lyricsPath).readAsBytes(), original);
  });

  test('가사를 실제로 바꾼 편집은 예전처럼 새 본문을 쓴다', () async {
    final song = await songWithLyrics(title: '봄날', loadedText: '옛 가사');

    final updated = await repo.updateSong(
      song: song,
      title: '봄날',
      lyrics: '새 가사\n둘째 줄',
    );

    expect(updated.lyricsText, '새 가사\n둘째 줄');
    expect(await File(updated.lyricsPath).readAsString(), '새 가사\n둘째 줄');
  });

  test('txt가 아예 없으면 메모리 본문으로 만든다(복구)', () async {
    final song = await songWithLyrics(title: '봄날', loadedText: '메모리 가사');
    await File(song.lyricsPath).delete();

    final updated = await repo.updateSong(song: song, title: '봄날');

    expect(await File(updated.lyricsPath).readAsString(), '메모리 가사');
  });
}
