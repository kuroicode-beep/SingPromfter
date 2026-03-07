import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/song.dart';
import '../repository/song_repository.dart';
import '../theme/app_theme.dart';
import 'lyrics_screen.dart';

class SongListScreen extends StatefulWidget {
  const SongListScreen({super.key});

  @override
  State<SongListScreen> createState() => _SongListScreenState();
}

class _SongListScreenState extends State<SongListScreen> {
  final _repo = SongRepository.instance;
  List<Song> _songs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    final songs = await _repo.loadSongs();
    if (!mounted) return;
    setState(() {
      _songs = songs;
      _loading = false;
    });
  }

  Future<void> _addSong() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
      dialogTitle: '가사 파일(txt) 선택',
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null && file.path == null) return;
    final lyrics = bytes != null
        ? String.fromCharCodes(bytes).trim()
        : await _readFile(file.path!);

    if (!mounted) return;

    final titleController = TextEditingController(
      text: file.name.replaceAll(RegExp(r'\.txt$', caseSensitive: false), ''),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        title: const Text('곡 제목', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: titleController,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: '곡 제목 입력',
            hintStyle: TextStyle(color: AppColors.textMuted),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.accent),
            ),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('추가'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final id = const Uuid().v4();
    final song = await _repo.addSong(
      id: id,
      title: titleController.text.trim().isEmpty
          ? file.name
          : titleController.text.trim(),
      lyrics: lyrics,
    );

    _songs.add(song);
    await _repo.saveSongs(_songs);
    if (mounted) setState(() {});
  }

  Future<String> _readFile(String path) async {
    return File(path).readAsString();
  }

  Future<void> _addMr(Song song) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      dialogTitle: '"${song.title}" MR 파일(mp3) 선택',
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final sourcePath = file.path;
    if (sourcePath == null) return;

    final mrFileName = await _repo.copyMr(id: song.id, sourcePath: sourcePath);
    final updated = song.copyWith(mrFileName: mrFileName);
    final idx = _songs.indexWhere((s) => s.id == song.id);
    if (idx >= 0) _songs[idx] = updated;
    await _repo.saveSongs(_songs);
    if (mounted) setState(() {});
  }

  Future<void> _deleteSong(Song song) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        title: const Text('삭제', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          '"${song.title}"을(를) 삭제하시겠습니까?',
          style: const TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.deleteSong(song);
    _songs.removeWhere((s) => s.id == song.id);
    await _repo.saveSongs(_songs);
    if (mounted) setState(() {});
  }

  void _openLyrics(Song song) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LyricsScreen(song: song)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SingPromfter'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : _songs.isEmpty
              ? _buildEmpty()
              : _buildList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSong,
        icon: const Icon(Icons.add),
        label: const Text('가사 추가', style: TextStyle(fontWeight: FontWeight.w700)),
        tooltip: '가사(txt) 파일 추가',
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.music_note, size: 64, color: AppColors.border),
          const SizedBox(height: 16),
          const Text(
            '등록된 노래가 없습니다',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '아래 + 버튼으로 가사(txt)를 추가해 보세요',
            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _songs.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _SongTile(
        song: _songs[i],
        onTap: () => _openLyrics(_songs[i]),
        onPlay: () => _openLyrics(_songs[i]),
        onAddMr: () => _addMr(_songs[i]),
        onDelete: () => _deleteSong(_songs[i]),
      ),
    );
  }
}

class _SongTile extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback onAddMr;
  final VoidCallback onDelete;

  const _SongTile({
    required this.song,
    required this.onTap,
    required this.onPlay,
    required this.onAddMr,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.elevated,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (song.hasMr)
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Row(
                          children: [
                            Icon(Icons.music_note, size: 12, color: AppColors.accent),
                            SizedBox(width: 4),
                            Text('MR 있음', style: TextStyle(color: AppColors.accent, fontSize: 12)),
                          ],
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Text('MR 없음', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!song.hasMr)
                _ActionChip(
                  label: 'MR 추가',
                  icon: Icons.upload_file,
                  onTap: onAddMr,
                  color: AppColors.border,
                  textColor: AppColors.textMuted,
                ),
              const SizedBox(width: 6),
              _ActionChip(
                label: '재생',
                icon: Icons.play_arrow,
                onTap: onPlay,
                color: AppColors.accent,
                textColor: const Color(0xFF0A0A0A),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                color: AppColors.textMuted,
                onPressed: onDelete,
                tooltip: '삭제',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final Color textColor;

  const _ActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: textColor),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
          ],
        ),
      ),
    );
  }
}
