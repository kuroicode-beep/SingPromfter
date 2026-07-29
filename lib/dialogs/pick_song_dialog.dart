// file: lib/dialogs/pick_song_dialog.dart
//
// 기존 곡 하나를 고르는 다이얼로그 — 유튜브 검색 결과를 "4번 슬롯(노래방)"으로
// 붙일 대상을 정할 때 쓴다.
//
// 4번 슬롯이 이미 있는 곡은 막지 않는다 — repo.addBackingTrack이 기존 파일을
// 지우고 교체하므로, "사용 중" 배지를 보여 주고 덮어쓰기 확인을 한 번 거친다.
// (색만으로 상태를 구분하지 않는다 — 배지는 텍스트다.)
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/song.dart';
import '../models/track_variant.dart';
import '../services/song_filter_service.dart';
import '../theme/app_theme.dart';

class PickSongDialog {
  PickSongDialog._();

  /// 곡을 고르면 그 곡을, 취소하면 null을 돌려준다.
  static Future<Song?> show(
    BuildContext context, {
    required List<Song> songs,
  }) {
    return showDialog<Song>(
      context: context,
      builder: (_) => _PickSongDialogBody(songs: songs),
    );
  }
}

class _PickSongDialogBody extends StatefulWidget {
  final List<Song> songs;

  const _PickSongDialogBody({required this.songs});

  @override
  State<_PickSongDialogBody> createState() => _PickSongDialogBodyState();
}

class _PickSongDialogBodyState extends State<_PickSongDialogBody> {
  String _query = '';

  static final int _karaokeSlot = TrackVariant.karaoke.preferredSlot;

  List<Song> get _filtered => SongFilterService.filter(
    widget.songs,
    query: _query,
    mode: SongListFilterMode.all,
  );

  Future<void> _pick(Song song) async {
    final existing = song.trackForSlot(_karaokeSlot);
    if (existing != null) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('4번 슬롯 덮어쓰기'),
          content: Text(
            "'${song.title}'의 4번 슬롯에는 이미 '${existing.label}' 반주가 "
            '있습니다. 새 노래방 반주로 덮어쓸까요?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('덮어쓰기'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }
    if (!mounted) return;
    Navigator.pop(context, song);
  }

  @override
  Widget build(BuildContext context) {
    final results = _filtered;
    return AlertDialog(
      title: const Text('어느 곡에 붙일까요?'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: '제목·가수 검색',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Text('맞는 곡이 없습니다', style: AppTypography.bodyMuted),
                    )
                  : ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final song = results[index];
                        final occupied =
                            song.trackForSlot(_karaokeSlot) != null;
                        final subtitle = [
                          if (song.artist.isNotEmpty) song.artist,
                          if (occupied) '4번 사용 중',
                        ].join(' · ');
                        return Semantics(
                          button: true,
                          label:
                              '${song.title}'
                              '${song.artist.isEmpty ? '' : ', ${song.artist}'}'
                              '${occupied ? ', 4번 슬롯 사용 중' : ''}',
                          child: InkWell(
                            onTap: () => _pick(song),
                            child: Container(
                              constraints: const BoxConstraints(
                                minHeight: AppConstants.minTouchTarget,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              alignment: Alignment.centerLeft,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    song.title,
                                    style: AppTypography.body,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (subtitle.isNotEmpty)
                                    Text(
                                      subtitle,
                                      style: AppTypography.bodyMuted,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
      ],
    );
  }
}
