// file: test/controllers/playback_copy_load_test.dart
//
// 곡을 물릴 때 어느 파일이 플레이어에 들어가는가 — 위치 보정본(VBR MP3의 WAV 사본).
//
// 진짜 PlaybackController + 진짜 PlaybackCopyService(가짜 ffmpeg)로 돈다. 플레이어만
// 채널 목이다 — setSourceUrl로 넘어간 경로를 받아 적고 「준비됨」 이벤트를 돌려준다.
//
// 고정하는 약속:
//   · 첫 물림은 **원본**을 바로 튼다(굽기를 기다리지 않는다).
//   · 뒤에서 구워져도 물려 있는 파일을 갈아끼우지 않는다.
//   · **다음 물림**부터 사본을 튼다. 테이크가 받아 적는 activeAudioPath도 사본이다.
//   · 키·템포 변형본을 틀 때는 묻지 않는다. 사본을 못 열면 원본으로 물러난다.
//
// 🔴 testWidgets가 아니라 plain test()다 — 파일 IO와 채널 응답을 실제로 기다린다.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singpromfter_app/controllers/playback_controller.dart';
import 'package:singpromfter_app/models/backing_track.dart';
import 'package:singpromfter_app/models/prompter_settings.dart';
import 'package:singpromfter_app/models/song.dart';
import 'package:singpromfter_app/repository/song_repository.dart';
import 'package:singpromfter_app/services/playback_copy_service.dart';
import 'package:singpromfter_app/services/process/process_runner.dart';
import 'package:singpromfter_app/services/prompter_audio_service.dart';
import 'package:singpromfter_app/services/song_queue_service.dart';
import 'package:singpromfter_app/utils/playback_copy_plan.dart';

import '../fakes/fake_mp3.dart';

const _fileName = '보정 대상_mr1.mp3';

/// 임시 폴더를 Documents로 쓰게 만드는 path_provider(캐시 폴더는 서비스에 직접 준다).
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

/// 출력 파일만 써 주는 ffmpeg 흉내. [gate]가 있으면 열릴 때까지 끝나지 않는다.
class _FakeFfmpeg implements ProcessRunner {
  final List<List<String>> renders = [];
  Completer<void>? gate;

  @override
  JobHandle start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) {
    renders.add(arguments);
    final exit = Completer<int>();
    Future<void>(() async {
      await (gate?.future ?? Future<void>.value());
      File(arguments.last).writeAsBytesSync(List.filled(200, 7));
      exit.complete(0);
    });
    return JobHandle(
      lines: const Stream<String>.empty(),
      exitCode: exit.future,
      cancel: () {},
    );
  }

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async => const ProcessOutput(exitCode: 0, stdout: 'ffmpeg', stderr: '');
}

Song _song() {
  final now = DateTime(2026, 9, 22);
  return Song(
    id: 'vbr-song',
    title: '보정 대상',
    artist: '테스트',
    lyricsPath: '',
    lyricsText: '첫 줄\n둘째 줄',
    backingTracks: const [
      BackingTrack(slot: 1, fileName: _fileName, label: '원곡'),
    ],
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late File original;
  late _FakeFfmpeg ffmpeg;
  late PlaybackCopyService copies;
  late PrompterSettings settings;

  /// 플레이어에 물린 파일 경로(물린 순서대로).
  late List<String> opened;

  /// 이 꼬리로 끝나는 파일은 플레이어가 못 연다(깨진 사본 흉내).
  String? unplayableSuffix;

  /// 재생 파일을 물을 때마다 센다.
  late int resolverCalls;
  late bool capturing;

  /// 컨트롤러가 사용자에게 띄운 안내.
  late List<String> messages;

  late PlaybackController playback;
  late PrompterAudioService audio;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('sp_copyload_');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
    SharedPreferences.setMockInitialValues({});
    final mp3Dir = Directory('${root.path}/data/mp3')
      ..createSync(recursive: true);
    original = File('${mp3Dir.path}/$_fileName')
      ..writeAsBytesSync(fakeVbrMp3());

    opened = [];
    unplayableSuffix = null;
    resolverCalls = 0;
    capturing = false;
    messages = [];
    settings = const PrompterSettings();

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const codec = StandardMethodCodec();
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        final args = (call.arguments as Map?) ?? const {};
        final playerId = args['playerId'] as String?;
        final events = 'xyz.luan/audioplayers/events/$playerId';
        if (call.method == 'create') {
          // 이벤트 채널의 listen/cancel을 받아 준다.
          messenger.setMockMethodCallHandler(
            MethodChannel(events),
            (_) async => null,
          );
        }
        if (call.method == 'setSourceUrl') {
          final url = args['url'] as String;
          final blocked = unplayableSuffix;
          if (blocked != null && url.endsWith(blocked)) {
            throw PlatformException(code: 'open_failed', message: url);
          }
          opened.add(url);
          // audioplayers는 「준비됨」 이벤트가 올 때까지 setSource를 끝내지 않는다.
          scheduleMicrotask(() {
            messenger.handlePlatformMessage(
              events,
              codec.encodeSuccessEnvelope(<String, Object>{
                'event': 'audio.onPrepared',
                'value': true,
              }),
              (_) {},
            );
          });
        }
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (call) async => null,
    );

    ffmpeg = _FakeFfmpeg();
    copies = PlaybackCopyService(
      runner: ffmpeg,
      cacheDirBuilder: () async => Directory('${root.path}/LocalAppData'),
    );

    final repo = SongRepository.instance;
    audio = PrompterAudioService(repo);
    playback = PlaybackController(
      audio: audio,
      queueService: SongQueueService(repo),
      repo: repo,
      lyricsScrollController: ScrollController(),
      songsProvider: () => const [],
      queueProvider: () => const [],
      settingsProvider: () => settings,
      onQueueChanged: (_) {},
      onMessage: messages.add,
      trackVariantResolver: (song, slot, semitones, tempo) async =>
          '${root.path}/variant__p+2.m4a',
      // AppController._resolvePlaybackCopy와 같은 모양 — 원본 경로를 집어 서비스에 묻는다.
      playbackCopyResolver: (song, slot) async {
        resolverCalls += 1;
        final path = await repo.getBackingTrackPath(
          song.trackForSlot(slot)!.fileName,
        );
        return copies.resolveForLoad(
          sourcePath: path!,
          sourceFileName: song.trackForSlot(slot)!.fileName,
          isBusy: () => capturing,
          startDelay: Duration.zero,
        );
      },
    )..init();
    playback.isRecordingProvider = () => capturing;
  });

  tearDown(() async {
    playback.dispose();
    await audio.dispose();
    copies.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('🔴 첫 물림은 원본을 바로 틀고, 다음 물림부터 위치 보정본을 튼다', () async {
    ffmpeg.gate = Completer<void>(); // 렌더가 아직 안 끝난 채로 첫 물림을 본다.
    final before = original.readAsBytesSync();

    await playback.loadSong(_song());

    expect(opened, [original.path], reason: '굽기를 기다리지 않고 원본을 연다');
    expect(playback.snapshot.audioReady, isTrue);
    expect(playback.snapshot.activeAudioPath, original.path);
    expect(playback.snapshot.sourceKind, PlaybackSourceKind.vbrOriginal);

    // 뒤에서 굽기가 끝난다 — 🔴 물려 있는 파일은 그대로다(갈아끼우지 않는다).
    ffmpeg.gate!.complete();
    await copies.settle();
    expect(ffmpeg.renders, hasLength(1));
    expect(opened, hasLength(1));
    expect(playback.snapshot.activeAudioPath, original.path);
    expect(playback.snapshot.sourceKind, PlaybackSourceKind.vbrOriginal);

    // 같은 곡을 다시 물린다 → 사본.
    await playback.loadSong(_song());

    expect(opened, hasLength(2));
    final copyPath = opened.last;
    expect(copyPath, endsWith('.wav'));
    expect(copyPath, contains('LocalAppData'));
    expect(File(copyPath).existsSync(), isTrue);
    // 테이크의 sourceAudioPath·고정 세션 컨텍스트는 이 값을 그대로 받는다.
    expect(playback.snapshot.activeAudioPath, copyPath);
    expect(playback.snapshot.sourceKind, PlaybackSourceKind.seekCopy);
    expect(ffmpeg.renders, hasLength(1), reason: '있는 사본을 다시 굽지 않는다');
    // 원본은 읽기만 했다.
    expect(original.readAsBytesSync(), before);
  });

  test('슬롯을 다시 고르는 것도 「다음 물림」이다', () async {
    await playback.loadSong(_song());
    await copies.settle();

    await playback.selectTrackSlot(1);

    expect(opened.last, endsWith('.wav'));
    expect(playback.snapshot.sourceKind, PlaybackSourceKind.seekCopy);
  });

  test('VBR이 아닌 반주는 원본 그대로(plain) — 굽지도 않는다', () async {
    original.writeAsBytesSync(fakeCbrMp3());

    await playback.loadSong(_song());
    await copies.settle();
    await playback.loadSong(_song());

    expect(opened, [original.path, original.path]);
    expect(playback.snapshot.sourceKind, PlaybackSourceKind.plain);
    expect(ffmpeg.renders, isEmpty);
  });

  test('🔴 키·템포 변형본을 틀 때는 보정본을 묻지 않는다 — 변형본은 어긋나지 않는다', () async {
    settings = settings.withSongPitch('vbr-song', 1, 2);

    await playback.loadSong(_song());
    await copies.settle();

    expect(opened.single, endsWith('variant__p+2.m4a'));
    expect(resolverCalls, 0);
    expect(playback.snapshot.sourceKind, PlaybackSourceKind.plain);
    expect(ffmpeg.renders, isEmpty);
  });

  test('사본을 못 열면 원본으로 물러난다 — 파생물 하나 때문에 재생이 막히지 않는다', () async {
    await playback.loadSong(_song());
    await copies.settle();
    unplayableSuffix = '.wav';

    await playback.loadSong(_song());

    expect(opened.last, original.path);
    expect(playback.snapshot.audioReady, isTrue);
    expect(playback.snapshot.activeAudioPath, original.path);
    expect(playback.snapshot.sourceKind, PlaybackSourceKind.vbrOriginal);
    // 사본 실패는 사용자에게 알릴 일이 아니다 — 원본이 멀쩡히 재생된다.
    expect(messages, isEmpty);
  });

  test('리졸버가 멎어도 첫 재생을 막지 않는다 — 상한을 넘기면 원본을 튼다', () async {
    final stuck = PlaybackController(
      audio: audio,
      queueService: SongQueueService(SongRepository.instance),
      repo: SongRepository.instance,
      lyricsScrollController: ScrollController(),
      songsProvider: () => const [],
      queueProvider: () => const [],
      settingsProvider: () => settings,
      onQueueChanged: (_) {},
      onMessage: (_) {},
      playbackCopyResolver: (song, slot) =>
          Completer<PlaybackCopyResolution>().future,
    );
    addTearDown(stuck.dispose);
    final watch = Stopwatch()..start();

    await stuck.loadSong(_song());

    expect(opened, [original.path]);
    expect(stuck.snapshot.sourceKind, PlaybackSourceKind.plain);
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('리졸버가 던져도 원본으로 재생된다', () async {
    final broken = PlaybackController(
      audio: audio,
      queueService: SongQueueService(SongRepository.instance),
      repo: SongRepository.instance,
      lyricsScrollController: ScrollController(),
      songsProvider: () => const [],
      queueProvider: () => const [],
      settingsProvider: () => settings,
      onQueueChanged: (_) {},
      onMessage: (_) {},
      playbackCopyResolver: (song, slot) async => throw StateError('boom'),
    );
    addTearDown(broken.dispose);

    await broken.loadSong(_song());

    expect(opened, [original.path]);
    expect(broken.snapshot.audioReady, isTrue);
  });

  group('adoptPlaybackCopyIfIdle — 받기 직전에 갈아타기', () {
    test('멈춰 있으면 그사이 구워진 사본으로 갈아탄다', () async {
      await playback.loadSong(_song());
      await copies.settle();
      expect(playback.snapshot.sourceKind, PlaybackSourceKind.vbrOriginal);

      expect(await playback.adoptPlaybackCopyIfIdle(), isTrue);

      expect(opened.last, endsWith('.wav'));
      expect(playback.snapshot.sourceKind, PlaybackSourceKind.seekCopy);
      expect(playback.snapshot.activeAudioPath, opened.last);
    });

    test('🔴 재생 중이면 손대지 않는다', () async {
      await playback.loadSong(_song());
      await copies.settle();
      playback.state.value = playback.state.value.copyWith(playing: true);

      expect(await playback.adoptPlaybackCopyIfIdle(), isFalse);

      expect(opened, [original.path]);
      expect(playback.snapshot.sourceKind, PlaybackSourceKind.vbrOriginal);
    });

    test('🔴 녹음 중·고정 조각이 열려 있으면 손대지 않는다', () async {
      await playback.loadSong(_song());
      await copies.settle();
      capturing = true;

      expect(await playback.adoptPlaybackCopyIfIdle(), isFalse);
      expect(opened, [original.path]);
    });

    test('사본이 아직 없으면 아무 일도 없다', () async {
      ffmpeg.gate = Completer<void>();
      await playback.loadSong(_song());

      expect(await playback.adoptPlaybackCopyIfIdle(), isFalse);
      expect(opened, [original.path]);

      ffmpeg.gate!.complete();
      await copies.settle();
    });

    test('이미 사본을 쓰고 있거나 VBR이 아니면 묻지도 않는다', () async {
      await playback.loadSong(_song());
      await copies.settle();
      await playback.loadSong(_song());
      final asked = resolverCalls;

      expect(await playback.adoptPlaybackCopyIfIdle(), isFalse);
      expect(resolverCalls, asked);
    });

    test('🔴 positionHeardSinceSeek — 재생으로 도달한 자리만 「옮겨질 수 있다」로 친다', () async {
      // VBR 원본을 듣다 멈춘 자리의 보고 위치는 들린 내용과 최대 ±0.7초 어긋나 있다.
      // 그 자리에서 사본으로 갈아타면 방금 멈춘 자리가 옮겨진 것으로 들린다 — 화면이
      // 이 값을 보고 안내를 싣는다. 화살표로 정한 자리는 옮겨지지 않는다.
      // 플레이어 목은 resume/pause를 받아 주고, audioplayers가 상태 이벤트를 스트림으로
      // 낸다(비동기) — 한 틱 기다려 컨트롤러의 거울(playing)이 서게 한다.
      Future<void> settle() => Future<void>.delayed(Duration.zero);

      await playback.loadSong(_song());
      await copies.settle();
      expect(playback.positionHeardSinceSeek, isFalse, reason: '물린 직후');

      // 재생 → 정지: 재생으로 도달한 자리다.
      expect(await playback.forcePlay(), isTrue);
      await settle();
      expect(playback.snapshot.playing, isTrue);
      expect(playback.positionHeardSinceSeek, isTrue);
      await playback.forcePause();
      await settle();
      expect(playback.snapshot.playing, isFalse);
      expect(playback.positionHeardSinceSeek, isTrue);
      expect(await playback.adoptPlaybackCopyIfIdle(), isTrue);
      expect(playback.snapshot.sourceKind, PlaybackSourceKind.seekCopy);
      // 갈아타기(위치 유지)는 이 값을 건드리지 않는다 — 화면은 갈아타기 전에 읽는다.
      expect(playback.positionHeardSinceSeek, isTrue);

      // 멈춘 채 화살표로 정한 자리 — 안내할 것이 없다.
      await playback.seek(const Duration(seconds: 30));
      expect(playback.positionHeardSinceSeek, isFalse);

      // 재생 중의 이동은 새 자리부터 계속 듣는 것이다 — 그 뒤의 정지 위치는 재생으로 도달.
      await playback.forcePlay();
      await settle();
      await playback.seek(const Duration(seconds: 40));
      expect(playback.positionHeardSinceSeek, isTrue);
      await playback.forcePause();
      await settle();
      expect(playback.positionHeardSinceSeek, isTrue);

      // 정지(처음으로 되돌림)는 사용자가 정한 자리다.
      await playback.stop();
      await settle();
      expect(playback.positionHeardSinceSeek, isFalse);
      // 처음부터 다시 재생하면 다시 듣는 것이다.
      await playback.restart();
      await settle();
      expect(playback.snapshot.playing, isTrue);
      expect(playback.positionHeardSinceSeek, isTrue);
      await playback.forcePause();
      await settle();
    });
  });

  test('🔴 곡을 바꿀 때 옛 곡의 sourceKind·activeAudioPath가 새 곡에 남지 않는다', () async {
    // 고정 중 VBR 원본 곡 A에서 CBR 곡 B를 고르면, 예전에는 loadSong의 첫 스냅샷이
    // song=B·sourceKind=vbrOriginal(A의 것)이라 VBR 안내가 B에 잘못 떴다(곡마다 한 번인
    // 문지기를 소비해 되돌릴 수도 없었다). B의 성격은 prepare가 정할 때까지 plain이다.
    ffmpeg.gate = Completer<void>();
    await playback.loadSong(_song());
    expect(playback.snapshot.sourceKind, PlaybackSourceKind.vbrOriginal);
    final aPath = playback.snapshot.activeAudioPath!;

    final cbrDir = Directory('${root.path}/data/mp3');
    File('${cbrDir.path}/보통 곡_mr1.mp3').writeAsBytesSync(fakeCbrMp3());
    final now = DateTime(2026, 9, 22);
    final songB = Song(
      id: 'cbr-song',
      title: '보통 곡',
      artist: '테스트',
      lyricsPath: '',
      lyricsText: '첫 줄',
      backingTracks: const [
        BackingTrack(slot: 1, fileName: '보통 곡_mr1.mp3', label: '원곡'),
      ],
      createdAt: now,
      updatedAt: now,
    );

    final seen = <PlaybackSnapshot>[];
    void collect() => seen.add(playback.state.value);
    playback.state.addListener(collect);
    await playback.loadSong(songB);
    playback.state.removeListener(collect);

    final ofB = seen.where((s) => s.song?.id == 'cbr-song');
    expect(ofB, isNotEmpty);
    for (final snapshot in ofB) {
      expect(snapshot.sourceKind, isNot(PlaybackSourceKind.vbrOriginal));
      expect(snapshot.activeAudioPath, isNot(aPath));
    }
    expect(playback.snapshot.sourceKind, PlaybackSourceKind.plain);
    // 무대 화면이 진행바를 넣었다 뺐다 하는 값(audioReady)은 곡 전환 중에도 흔들리지 않는다.
    expect(ofB.every((s) => s.audioReady), isTrue);

    ffmpeg.gate!.complete();
    await copies.settle();
  });

  test('받는 중에 물린 곡은 굽기를 미룬다 — 조각이 닫히면 굽는다', () async {
    final slow = PlaybackCopyService(
      runner: ffmpeg,
      cacheDirBuilder: () async => Directory('${root.path}/LocalAppData2'),
      busyRetryDelay: const Duration(milliseconds: 10),
    );
    addTearDown(slow.dispose);
    capturing = true;

    final first = await slow.resolveForLoad(
      sourcePath: original.path,
      sourceFileName: _fileName,
      isBusy: () => capturing,
      startDelay: Duration.zero,
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(first.kind, PlaybackSourceKind.vbrOriginal);
    expect(ffmpeg.renders, isEmpty);

    capturing = false;
    await slow.settle();
    expect(ffmpeg.renders, hasLength(1));
  });
}
