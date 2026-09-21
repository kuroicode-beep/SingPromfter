// file: test/controllers/playback_force_transport_test.dart
//
// 녹음 고정용 재생 조작 — forcePlay/forcePause는 `playing` 거울을 믿지 않는다.
//
// `state.playing`은 네이티브 호출이 끝난 **뒤**의 상태 이벤트로 선다. 그 값으로
// 게이트하는 play()/pause()는 재생 직후의 정지를 무동작으로 삼켜서, 조각은
// 끝났는데 음악만 계속 나오는 틈이 있었다.
//
// testWidgets가 아니라 plain test()다 — 플랫폼 채널 응답을 실제로 기다린다.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/controllers/playback_controller.dart';
import 'package:singpromfter_app/models/backing_track.dart';
import 'package:singpromfter_app/models/prompter_settings.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/repository/song_repository.dart';
import 'package:singpromfter_app/services/prompter_audio_service.dart';
import 'package:singpromfter_app/services/song_queue_service.dart';

import '../fakes/fake_playback.dart';

/// 반주가 있는 곡. 픽스처의 fakeSong은 가사 전용이라, seek 한 번에 컨트롤러가
/// 시계를 스스로 돌리기 시작한다(가사 전용 곡의 규칙) — 멈춘 위치를 잴 수 없다.
Song _songWithBacking() {
  final now = DateTime(2026, 9, 22);
  return Song(
    id: 'force-song',
    title: '반주 있는 곡',
    artist: '테스트',
    lyricsPath: '',
    lyricsText: '첫 줄 둘째 줄',
    backingTracks: const [
      BackingTrack(slot: 1, fileName: 'mr.mp3', label: 'MR'),
    ],
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 네이티브로 나간 호출 이름(순서대로).
  late List<String> calls;

  /// getCurrentPosition이 돌려줄 값(ms). null이면 「모름」.
  int? nativePositionMs;

  setUp(() {
    calls = [];
    nativePositionMs = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        calls.add(call.method);
        if (call.method == 'getCurrentPosition') return nativePositionMs;
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (call) async => null,
    );
  });

  /// 재생·정지 호출만 추린다(create·setVolume 등은 관심 밖).
  List<String> transport() => [
    for (final c in calls)
      if (c == 'resume' || c == 'pause') c,
  ];

  group('forcePlay', () {
    test('🔴 playing 거울이 true로 낡아 있어도 재생을 건다', () async {
      final fake = buildFakePlayback(song: _songWithBacking());
      addTearDown(fake.dispose);
      final playback = fake.controller;
      playback.state.value = playback.state.value.copyWith(playing: true);

      // 게이트를 타는 play()는 아무것도 안 한다 — 이게 틈이다.
      await playback.play();
      expect(transport(), isEmpty);

      expect(await playback.forcePlay(), isTrue);
      expect(transport(), ['resume']);
    });

    test('반주가 준비 안 됐으면 걸지 않고 사유를 알린다 — 재생 가능 검사는 그대로', () async {
      final fake = buildFakePlayback(song: _songWithBacking());
      addTearDown(fake.dispose);
      final playback = fake.controller;
      playback.state.value = playback.state.value.copyWith(audioReady: false);

      expect(await playback.forcePlay(), isFalse);
      expect(transport(), isEmpty);
    });

    test('곡이 없으면 false — 호출부가 찍어 둔 조각 마크를 물릴 수 있게', () async {
      final fake = buildFakePlayback();
      addTearDown(fake.dispose);

      expect(await fake.controller.forcePlay(), isFalse);
      expect(transport(), isEmpty);
    });
  });

  group('forcePause', () {
    test('🔴 playing 거울이 아직 false여도(재생 직후) 실제로 멈춘다', () async {
      final fake = buildFakePlayback(song: _songWithBacking());
      addTearDown(fake.dispose);
      final playback = fake.controller;
      expect(playback.state.value.playing, isFalse);

      // 게이트를 타는 pause()는 「이미 멈춰 있다」고 보고 건너뛴다.
      await playback.pause();
      expect(transport(), isEmpty);

      await playback.forcePause();
      expect(transport(), ['pause']);
    });

    test('멈춘 뒤 네이티브 위치로 시계 앵커를 확정한다 — 다음 조각의 P0', () async {
      final fake = buildFakePlayback(song: _songWithBacking());
      addTearDown(fake.dispose);
      final playback = fake.controller;
      nativePositionMs = 83250;

      await playback.forcePause();

      expect(calls, containsAllInOrder(['pause', 'getCurrentPosition']));
      expect(playback.precisePosition, const Duration(milliseconds: 83250));
      expect(playback.position.value, const Duration(milliseconds: 83250));
    });

    test('네이티브가 위치를 모르면 앵커를 건드리지 않는다', () async {
      final fake = buildFakePlayback(song: _songWithBacking());
      addTearDown(fake.dispose);
      final playback = fake.controller;
      await playback.seek(const Duration(seconds: 12));
      nativePositionMs = null;

      await playback.forcePause();

      expect(playback.precisePosition, const Duration(seconds: 12));
    });

    test('반주가 없는 곡이면 멈출 것도 확정할 것도 없다 — 알림 없이 넘어간다', () async {
      // 알림까지 보려고 컨트롤러를 직접 조립한다(픽스처는 onMessage를 버린다).
      final messages = <String>[];
      final repo = SongRepository.instance;
      final audio = PrompterAudioService(repo);
      final playback = PlaybackController(
        audio: audio,
        queueService: SongQueueService(repo),
        repo: repo,
        lyricsScrollController: ScrollController(),
        songsProvider: () => const [],
        queueProvider: () => const [],
        settingsProvider: () => const PrompterSettings(),
        onQueueChanged: (_) {},
        onMessage: messages.add,
      )..init();
      addTearDown(() {
        playback.dispose();
        audio.dispose();
      });
      playback.state.value = playback.state.value.copyWith(
        song: _songWithBacking(),
        audioReady: false,
      );
      nativePositionMs = 5000;

      await playback.forcePause();

      expect(transport(), isEmpty);
      expect(calls, isNot(contains('getCurrentPosition')));
      // 같은 상황의 pause()는 「반주가 없어…」를 띄운다 — 정지 요청에는 소음이다.
      expect(messages, isEmpty);
      // forcePlay는 알린다 — 호출부가 마크를 물려야 하는 이유를 사용자도 알아야 한다.
      expect(await playback.forcePlay(), isFalse);
      expect(messages, hasLength(1));
    });
  });

  group('pause — 실제로 멈췄을 때만 앵커를 확정한다', () {
    test('재생 중이던 것을 멈추면 네이티브 위치로 맞춘다', () async {
      final fake = buildFakePlayback(song: _songWithBacking());
      addTearDown(fake.dispose);
      final playback = fake.controller;
      playback.state.value = playback.state.value.copyWith(playing: true);
      nativePositionMs = 41000;

      await playback.pause();

      expect(transport(), ['pause']);
      expect(playback.precisePosition, const Duration(milliseconds: 41000));
    });

    test('이미 멈춰 있었으면 묻지도 않는다 — 방금 seek한 앵커가 정확하다', () async {
      final fake = buildFakePlayback(song: _songWithBacking());
      addTearDown(fake.dispose);
      final playback = fake.controller;
      await playback.seek(const Duration(seconds: 30));
      calls.clear();
      nativePositionMs = 1234;

      await playback.pause();

      expect(calls, isNot(contains('getCurrentPosition')));
      expect(playback.precisePosition, const Duration(seconds: 30));
    });
  });
}
