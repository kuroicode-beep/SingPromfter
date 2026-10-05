// file: lib/controllers/lyric_voice_monitor_controller.dart
// 가사 타임라인에 맞춰 SAPI로 미리 만든 음성을 RØDE 출력으로 보낸다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../services/lyrics_sync_math.dart';
import '../services/lyric_voice_monitor_service.dart';
import 'playback_controller.dart';

class LyricVoiceMonitorController {
  static const Duration lead = Duration(seconds: 1);

  final PlaybackController playback;
  final LyricVoiceMonitorService service;
  final void Function(String message) onMessage;
  final ValueNotifier<bool> enabled = ValueNotifier(false);
  final Map<int, String> _readyFiles = {};
  String? _preparedSongId;
  String? _preparingSongId;
  int _preparationGeneration = 0;
  String? _activeSongId;
  int _cursor = 0;
  bool _allowImmediateFirstCue = false;
  bool _lastPlaying = false;
  bool _reportedNotReady = false;
  bool _disposed = false;

  LyricVoiceMonitorController({
    required this.playback,
    required this.onMessage,
    LyricVoiceMonitorService? service,
  }) : service = service ?? LyricVoiceMonitorService() {
    playback.state.addListener(_onPlaybackChanged);
    playback.position.addListener(_onPositionChanged);
    playback.timedLyrics.addListener(_onLyricsChanged);
    _prepareSelectedSong();
  }

  Future<void> toggle() async {
    if (_disposed) return;
    if (enabled.value) {
      enabled.value = false;
      _allowImmediateFirstCue = false;
      _stopSafely();
      onMessage('가사 읽기 꺼짐');
      return;
    }
    Map<Object?, Object?> status = const {};
    try {
      status = await service.rodeOutputStatus;
      if (status['ok'] != true) {
        final detail = status['error']?.toString();
        onMessage(
          detail == null || detail.isEmpty
              ? 'RØDE 헤드폰 출력 장치를 열 수 없어 가사 읽기를 켜지 않았어요.'
              : detail,
        );
        return;
      }
    } on PlatformException catch (error) {
      onMessage(error.message ?? 'Windows 오디오 출력 점검에 실패했어요.');
      return;
    } on MissingPluginException {
      onMessage('이 기능은 Windows 앱에서 사용할 수 있어요.');
      return;
    } on Object catch (error) {
      onMessage('Windows 오디오 출력 점검에 실패했어요: $error');
      return;
    }
    enabled.value = true;
    _reportedNotReady = false;
    final snapshot = playback.snapshot;
    _activeSongId = snapshot.song?.id;
    _cursor = snapshot.playing ? playback.upcomingLineIndex() : 0;
    _allowImmediateFirstCue = snapshot.playing;
    final deviceName = status['device']?.toString();
    final route = deviceName == null || deviceName.isEmpty
        ? 'RØDE 출력'
        : deviceName;
    onMessage('가사 읽기 켜짐 · $route · Ctrl+Alt+Z');
    _onPositionChanged();
  }

  void dispose() {
    _disposed = true;
    playback.state.removeListener(_onPlaybackChanged);
    playback.position.removeListener(_onPositionChanged);
    playback.timedLyrics.removeListener(_onLyricsChanged);
    enabled.dispose();
    _stopSafely();
  }

  void _onPlaybackChanged() {
    final playing = playback.snapshot.playing;
    final justStarted = playing && !_lastPlaying;
    final justPaused = !playing && _lastPlaying;
    _lastPlaying = playing;
    if (justPaused && enabled.value) _stopSafely();
    final songId = playback.snapshot.song?.id;
    if (songId != _activeSongId) {
      _activeSongId = songId;
      final atSongStart =
          playback.position.value <= const Duration(milliseconds: 100);
      _cursor = playback.snapshot.playing && !atSongStart
          ? playback.upcomingLineIndex()
          : 0;
      _allowImmediateFirstCue = playback.snapshot.playing && atSongStart;
      _reportedNotReady = false;
      _readyFiles.clear();
      _preparedSongId = null;
      _preparingSongId = null;
      _preparationGeneration++;
      if (enabled.value) _stopSafely();
    }
    if (justStarted) {
      if (playback.position.value <= const Duration(milliseconds: 100) &&
          _cursor == 0) {
        _cursor = 0;
        _allowImmediateFirstCue = true;
      } else {
        _cursor = playback.upcomingLineIndex();
        _allowImmediateFirstCue = false;
      }
    }
    _onPositionChanged();
  }

  void _onLyricsChanged() {
    _readyFiles.clear();
    _preparedSongId = null;
    _preparingSongId = null;
    _preparationGeneration++;
    _prepareSelectedSong();
    if (enabled.value) {
      _cursor = playback.snapshot.playing ? playback.upcomingLineIndex() : 0;
      _allowImmediateFirstCue = false;
    }
  }

  Future<void> _prepareSelectedSong() async {
    final song = playback.snapshot.song;
    final lyrics = playback.timedLyrics.value;
    if (_disposed ||
        song == null ||
        lyrics == null ||
        lyrics.isEmpty ||
        _preparedSongId == song.id ||
        _preparingSongId == song.id) {
      return;
    }
    final songId = song.id;
    final generation = ++_preparationGeneration;
    _preparingSongId = songId;
    try {
      final temp = await getTemporaryDirectory();
      final safeId = songId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final dir = Directory(
        '${temp.path}${Platform.pathSeparator}singpromfter_lyric_voice${Platform.pathSeparator}$safeId',
      );
      await dir.create(recursive: true);
      final entries = <Map<String, String>>[];
      for (var i = 0; i < lyrics.lines.length; i++) {
        final text = lyrics.lines[i].text.trim();
        if (text.isEmpty) continue;
        final path =
            '${dir.path}${Platform.pathSeparator}$i-${_textKey(text)}.wav';
        entries.add({'index': '$i', 'text': text, 'path': path});
      }
      final result = await service.prepareLyrics(entries);
      if (_disposed ||
          generation != _preparationGeneration ||
          playback.snapshot.song?.id != songId) {
        return;
      }
      var readyCount = 0;
      String? firstError;
      for (var i = 0; i < entries.length && i < result.length; i++) {
        final item = result[i];
        final path = entries[i]['path']!;
        final file = File(path);
        final exists = await file.exists();
        final size = exists ? await file.length() : 0;
        if (item['ready'] == true && exists && size > 44) {
          _readyFiles[int.parse(entries[i]['index']!)] = path;
          readyCount++;
        } else {
          firstError ??= item['error']?.toString();
          if (firstError == null || firstError.isEmpty) {
            firstError = !exists
                ? '가사 음성 WAV 파일이 생성되지 않았어요.'
                : '가사 음성 WAV 파일이 비어 있거나 손상됐어요.';
          }
        }
      }
      _preparedSongId = songId;
      if (readyCount < entries.length) {
        final failedCount = entries.length - readyCount;
        final detail = firstError == null || firstError.isEmpty
            ? ''
            : ' 첫 실패: $firstError';
        onMessage(
          '가사 음성 준비 $readyCount/${entries.length}줄 완료, '
          '$failedCount줄은 재생하지 않아요.$detail',
        );
      }
      _onPositionChanged();
    } on Object catch (error) {
      _preparedSongId = songId;
      onMessage('가사 음성 사전 준비에 실패했어요: $error');
    } finally {
      if (generation == _preparationGeneration && _preparingSongId == songId) {
        _preparingSongId = null;
      }
    }
  }

  void _onPositionChanged() {
    if (_disposed || !enabled.value || !playback.snapshot.playing) return;
    final lyrics = playback.timedLyrics.value;
    if (lyrics == null || lyrics.isEmpty) return;
    final position = playback.precisePosition;
    while (_cursor < lyrics.lines.length) {
      final start = LyricsSyncMath.playerPositionForLine(
        lyrics: lyrics,
        index: _cursor,
        trackStartMs: playback.snapshot.trackStartMs,
        lyricsOffsetMs: playback.snapshot.lyricsOffsetMs,
        tempoScale: playback.snapshot.tempoScale,
      );
      final due = start > lead ? start - lead : Duration.zero;
      if (position < due) return;
      if (!_allowImmediateFirstCue && position >= start) {
        _cursor++;
        continue;
      }
      _allowImmediateFirstCue = false;
      final path = _readyFiles[_cursor];
      if (path == null) {
        _cursor++;
        if (!_reportedNotReady) {
          _reportedNotReady = true;
          onMessage('준비되지 않은 가사 음성은 늦게 재생하지 않고 건너뛰어요.');
        }
        continue;
      }
      _cursor++;
      unawaited(
        service.playFile(path).then((status) {
          final playbackStatus = status['status']?.toString();
          if (playbackStatus != 'played' && playbackStatus != 'cancelled' &&
              !_reportedNotReady) {
            _reportedNotReady = true;
            onMessage('가사 음성 재생 결과가 올바르지 않아요: $status');
          }
        }).catchError((Object error) {
          if (!_reportedNotReady) {
            _reportedNotReady = true;
            onMessage('RØDE 헤드폰에서 가사 음성을 재생하지 못했어요: $error');
          }
        }),
      );
      return;
    }
  }

  String _textKey(String text) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(text)) {
      hash = ((hash ^ byte) * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16);
  }

  void _stopSafely() {
    unawaited(
      service.stop().catchError((Object error) {
        if (!_disposed) onMessage('가사 음성을 정지하지 못했어요: $error');
      }),
    );
  }
}
