// file: test/fakes/fake_playback.dart
//
// 위젯 테스트용 PlaybackController.
//
// PrompterScreen은 PlaybackController(필수 의존성 9개)를 요구해 지금까지
// 위젯 테스트가 0건이었다 — 전체화면 드로어가 얼어붙는 버그(v2.8.2)가
// 테스트 없이 통과한 이유다. 여기서는 **진짜 컨트롤러**를 무해한 의존성으로
// 조립한다. app_controller_test에서 검증된 방식: audioplayers 채널만 막으면
// 컨트롤러 전체가 테스트 환경에서 돈다.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/controllers/playback_controller.dart';
import 'package:singpromfter_app/models/prompter_settings.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/repository/song_repository.dart';
import 'package:singpromfter_app/services/prompter_audio_service.dart';
import 'package:singpromfter_app/services/song_queue_service.dart';

/// 테스트 환경에는 audioplayers 네이티브가 없다 — setUp에서 한 번 부른다.
void mockAudioChannels() {
  for (final name in ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global']) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), (call) async => null);
  }
}

/// 컨트롤러와 그 오디오 서비스를 함께 정리하는 홀더.
/// audioplayers가 위치 폴링 Timer를 돌리므로 audio도 dispose해야
/// 위젯 테스트의 "Timer still pending" 검사에 걸리지 않는다.
class FakePlayback {
  final PlaybackController controller;
  final PrompterAudioService _audio;

  FakePlayback._(this.controller, this._audio);

  void dispose() {
    controller.dispose();
    _audio.dispose();
  }
}

/// 무해한 의존성으로 조립한 진짜 PlaybackController.
/// [song]을 주면 스냅샷에 실어 둔다(loadSong을 부르지 않으므로 파일 불필요).
FakePlayback buildFakePlayback({Song? song}) {
  final repo = SongRepository.instance;
  final audio = PrompterAudioService(repo);
  final controller = PlaybackController(
    audio: audio,
    queueService: SongQueueService(repo),
    repo: repo,
    lyricsScrollController: ScrollController(),
    songsProvider: () => const [],
    queueProvider: () => const [],
    settingsProvider: () => const PrompterSettings(),
    onQueueChanged: (_) {},
    onMessage: (_) {},
  )..init();
  if (song != null) {
    controller.state.value = controller.state.value.copyWith(
      song: song,
      audioReady: true,
      duration: const Duration(minutes: 3),
    );
  }
  return FakePlayback._(controller, audio);
}

/// 가사 몇 줄짜리 테스트 곡. LRC 없음(스윕 미동작 검증에 쓴다).
Song fakeSong({String title = '테스트 곡'}) {
  final now = DateTime(2026, 7, 29);
  return Song(
    id: 'fake-song',
    title: title,
    artist: '테스트',
    lyricsPath: '',
    lyricsText: '첫 줄\n둘째 줄\n셋째 줄',
    backingTracks: const [],
    createdAt: now,
    updatedAt: now,
  );
}
