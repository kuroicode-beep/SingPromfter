// file: lib/services/song_sort_service.dart
//
// 곡 목록 정렬. 필터(SongListFilterMode)와 축을 분리해 둔다 —
// 하나의 enum에 정렬을 끼워 넣으면 세 곳의 호출부가 모두 꼬인다.
import '../models/practice_session.dart';
import '../models/song.dart';

enum SongSortMode { title, recentlyAdded, mostPracticed, leastPracticed }

extension SongSortModeInfo on SongSortMode {
  String get label => switch (this) {
    SongSortMode.title => '제목순',
    SongSortMode.recentlyAdded => '최근 등록순',
    SongSortMode.mostPracticed => '많이 부른 순',
    SongSortMode.leastPracticed => '덜 부른 순',
  };

  String get storageValue => name;

  static SongSortMode fromStorage(String? raw) {
    for (final mode in SongSortMode.values) {
      if (mode.name == raw) return mode;
    }
    return SongSortMode.title;
  }
}

class SongSortService {
  SongSortService._();

  /// 정렬한 새 목록을 만든다. 원본은 건드리지 않는다.
  ///
  /// [practiceCounts]는 곡 id → 연습 횟수. 없으면 0으로 본다.
  static List<Song> sort(
    List<Song> songs, {
    SongSortMode mode = SongSortMode.title,
    Map<String, int> practiceCounts = const {},
  }) {
    final sorted = List<Song>.from(songs);
    switch (mode) {
      case SongSortMode.title:
        sorted.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case SongSortMode.recentlyAdded:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case SongSortMode.mostPracticed:
        sorted.sort((a, b) {
          final diff =
              (practiceCounts[b.id] ?? 0) - (practiceCounts[a.id] ?? 0);
          // 횟수가 같으면 제목순으로 안정적으로 정렬한다.
          if (diff != 0) return diff;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
      case SongSortMode.leastPracticed:
        sorted.sort((a, b) {
          final diff =
              (practiceCounts[a.id] ?? 0) - (practiceCounts[b.id] ?? 0);
          if (diff != 0) return diff;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
    }
    return List.unmodifiable(sorted);
  }

  /// 연습 집계에서 곡별 횟수 맵을 만든다.
  static Map<String, int> practiceCountsFrom(List<PracticeSummary> summaries) {
    return {for (final s in summaries) s.songId: s.sessionCount};
  }

  /// 제목이 겹치는 곡들을 찾는다. (대소문자·앞뒤 공백 무시)
  static List<List<Song>> findDuplicateTitles(List<Song> songs) {
    final byTitle = <String, List<Song>>{};
    for (final song in songs) {
      final key = song.title.trim().toLowerCase();
      if (key.isEmpty) continue;
      byTitle.putIfAbsent(key, () => []).add(song);
    }
    return byTitle.values
        .where((group) => group.length > 1)
        .toList(growable: false);
  }
}

/// 라이브러리 점검 결과.
class LibraryAudit {
  /// 어느 곡도 참조하지 않는 반주 파일명.
  final List<String> orphanTrackFiles;

  /// 어느 곡도 참조하지 않는 싱크 가사 파일명.
  final List<String> orphanLrcFiles;

  /// 파일이 사라진 반주를 가진 곡.
  final List<Song> songsWithMissingTracks;

  /// 제목이 겹치는 곡 묶음.
  final List<List<Song>> duplicateTitleGroups;

  const LibraryAudit({
    this.orphanTrackFiles = const [],
    this.orphanLrcFiles = const [],
    this.songsWithMissingTracks = const [],
    this.duplicateTitleGroups = const [],
  });

  bool get isClean =>
      orphanTrackFiles.isEmpty &&
      orphanLrcFiles.isEmpty &&
      songsWithMissingTracks.isEmpty &&
      duplicateTitleGroups.isEmpty;

  int get orphanCount => orphanTrackFiles.length + orphanLrcFiles.length;

  /// 디스크 목록과 곡 목록을 비교해 점검한다. (순수 함수 — 파일시스템 불필요)
  static LibraryAudit compare({
    required List<Song> songs,
    required List<String> trackFilesOnDisk,
    required List<String> lrcFilesOnDisk,
  }) {
    final referencedTracks = <String>{
      for (final song in songs)
        for (final track in song.backingTracks) track.fileName,
    };
    final referencedLrc = <String>{
      for (final song in songs)
        if ((song.lrcFileName ?? '').isNotEmpty) song.lrcFileName!,
    };

    final orphanTracks = trackFilesOnDisk
        .where((f) => !referencedTracks.contains(f))
        .toList(growable: false);
    final orphanLrc = lrcFilesOnDisk
        .where((f) => !referencedLrc.contains(f))
        .toList(growable: false);

    final onDisk = trackFilesOnDisk.toSet();
    final missing = songs
        .where(
          (song) => song.backingTracks.any(
            (t) => t.fileName.isNotEmpty && !onDisk.contains(t.fileName),
          ),
        )
        .toList(growable: false);

    return LibraryAudit(
      orphanTrackFiles: orphanTracks,
      orphanLrcFiles: orphanLrc,
      songsWithMissingTracks: missing,
      duplicateTitleGroups: SongSortService.findDuplicateTitles(songs),
    );
  }
}
