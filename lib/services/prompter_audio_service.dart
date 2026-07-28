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

  /// 현재 재생 위치를 직접 조회한다.
  /// Windows 위치 이벤트가 약 4Hz라 보간 시계의 보조 재동기화에 쓴다.
  Future<Duration?> currentPosition() => _player.getCurrentPosition();

  Future<void> setVolume(double volume) => _player.setVolume(volume);

  Future<void> setPlaybackRate(double rate) => _player.setPlaybackRate(rate);

  Future<AudioPrepareResult> prepareSelection({
    required Song? song,
    required int? selectedTrackSlot,
    required double volume,
    required double playbackRate,
    int? startMs,
    /// 키를 바꾼 변형본 경로. 주면 원본 대신 이 파일을 재생한다.
    String? overridePath,
  }) async {
    if (song == null || selectedTrackSlot == null) {
      return const AudioPrepareResult.notReady();
    }

    final track = song.trackForSlot(selectedTrackSlot);
    if (track == null) {
      return const AudioPrepareResult.notReady();
    }

    final path = overridePath ?? await _repo.getBackingTrackPath(track.fileName);
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

  /// 파일 하나를 바로 재생한다. 녹음 미리듣기처럼 곡과 무관한 재생에 쓴다.
  /// 프롬프터 재생과 섞이지 않도록 별도 인스턴스에서 호출할 것.
  Future<bool> playFile(String path) async {
    try {
      await _player.stop();
      await _player.setSourceDeviceFile(path);
      await _player.resume();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<String?> togglePlayPause({
    required Song? song,
    required bool audioReady,
    required bool playing,
  }) async {
    return playing
        ? pause(song: song, audioReady: audioReady, playing: playing)
        : play(song: song, audioReady: audioReady, playing: playing);
  }

  /// 명시적 재생. 이미 재생 중이면 무동작(멱등) — MCP 제어용.
  Future<String?> play({
    required Song? song,
    required bool audioReady,
    required bool playing,
  }) async {
    final blocked = _playabilityMessage(song: song, audioReady: audioReady);
    if (blocked != null || song == null) return blocked;
    if (!playing) await _player.resume();
    return null;
  }

  /// 명시적 일시정지. 정지 상태면 무동작(멱등).
  Future<String?> pause({
    required Song? song,
    required bool audioReady,
    required bool playing,
  }) async {
    final blocked = _playabilityMessage(song: song, audioReady: audioReady);
    if (blocked != null || song == null) return blocked;
    if (playing) await _player.pause();
    return null;
  }

  /// 재생 불가 사유. 가능하면 null.
  String? _playabilityMessage({
    required Song? song,
    required bool audioReady,
  }) {
    if (song == null) return null;
    if (audioReady) return null;
    if (song.backingTracks.isEmpty) {
      return '이 곡은 반주가 없어 가사만 표시됩니다.';
    }
    return '재생 가능한 반주를 먼저 선택해 주세요.';
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
