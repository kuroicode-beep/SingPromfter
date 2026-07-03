// file: lib/services/prompter_audio_service.dart
//
// 오디오 플레이어 제어와 반주 파일 준비를 담당한다.
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../models/song.dart';
import '../repository/song_repository.dart';

class PrompterAudioService {
  final SongRepository _repo;
  final AudioPlayer _player = AudioPlayer();

  PrompterAudioService(this._repo);

  AudioBindings bind({
    required void Function(bool playing) onPlayingChanged,
    required ValueChangedDuration onPositionChanged,
    required ValueChangedDuration onDurationChanged,
    required Future<void> Function() onCompleted,
  }) {
    return AudioBindings([
      _player.onPlayerStateChanged.listen((state) async {
        onPlayingChanged(state == PlayerState.playing);
        if (state == PlayerState.completed) {
          await onCompleted();
        }
      }),
      _player.onPositionChanged.listen(onPositionChanged),
      _player.onDurationChanged.listen(onDurationChanged),
    ]);
  }

  Future<void> dispose() => _player.dispose();

  Future<void> setVolume(double volume) => _player.setVolume(volume);

  Future<void> setPlaybackRate(double rate) => _player.setPlaybackRate(rate);

  Future<AudioPrepareResult> prepareSelection({
    required Song? song,
    required int? selectedTrackSlot,
    required double volume,
    required double playbackRate,
    int? startMs,
  }) async {
    if (song == null || selectedTrackSlot == null) {
      return const AudioPrepareResult.notReady();
    }

    final track = song.trackForSlot(selectedTrackSlot);
    if (track == null) {
      return const AudioPrepareResult.notReady();
    }

    final path = await _repo.getBackingTrackPath(track.fileName);
    if (path == null) {
      return const AudioPrepareResult.notReady(
        message: '반주 파일을 찾을 수 없습니다. 곡을 다시 등록해 주세요.',
      );
    }

    try {
      await _player.stop();
      await _player.setSourceDeviceFile(path);
      await _player.setVolume(volume);
      await _player.setPlaybackRate(playbackRate);
      if (startMs != null && startMs > 0) {
        await _player.seek(Duration(milliseconds: startMs));
      }
      return const AudioPrepareResult.ready();
    } catch (e) {
      return AudioPrepareResult.notReady(message: '반주 파일을 재생할 수 없습니다: $e');
    }
  }

  Future<String?> togglePlayPause({
    required Song? song,
    required bool audioReady,
    required bool playing,
  }) async {
    if (song == null) return null;
    if (!audioReady) {
      if (song.backingTracks.isEmpty) {
        return '이 곡은 반주가 없어 가사만 표시됩니다.';
      }
      return '재생 가능한 반주를 먼저 선택해 주세요.';
    }

    if (playing) {
      await _player.pause();
    } else {
      await _player.resume();
    }
    return null;
  }

  Future<void> stop() async {
    await _player.pause();
    await _player.seek(Duration.zero);
  }

  Future<String?> restart({required bool audioReady, int? startMs}) async {
    if (!audioReady) {
      return '재생 가능한 반주가 없습니다.';
    }
    await _player.seek(Duration(milliseconds: startMs ?? 0));
    await _player.resume();
    return null;
  }

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> resumeFromStart({int? startMs}) async {
    await _player.seek(Duration(milliseconds: startMs ?? 0));
    await _player.resume();
  }
}

typedef ValueChangedDuration = void Function(Duration value);

class AudioBindings {
  final List<StreamSubscription<dynamic>> _subscriptions;

  const AudioBindings(this._subscriptions);

  void cancel() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
  }
}

class AudioPrepareResult {
  final bool ready;
  final String? message;

  const AudioPrepareResult._({required this.ready, this.message});

  const AudioPrepareResult.ready() : this._(ready: true);

  const AudioPrepareResult.notReady({String? message})
    : this._(ready: false, message: message);
}
