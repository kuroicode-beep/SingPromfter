// file: lib/services/playback_copy_service.dart
//
// VBR MP3 반주의 「위치 보정본」(재생용 WAV 사본)을 굽고 찾아 준다.
//
// 문제: Windows의 Media Foundation은 VBR MP3에서 seek 위치를 비트레이트로 어림한다.
// 실측으로 −217~+742ms가 어긋났고, 화살표로 이동한 뒤 받은 녹음 조각의 곡 좌표가
// 그만큼 틀려 이어붙이면 박자가 어긋난다. WAV는 어긋남이 0이다(utils/playback_copy_plan).
//
// ── 누가 어느 파일을 쓰는가 (🔴 이 구분이 깨지면 조용히 어긋난다) ──────────
//   · **플레이어만** 보정본을 쓴다 — PlaybackController.prepareAudioForSelection이
//     기본 키·템포일 때 여기서 받은 경로를 재생 파일로 물린다.
//   · 테이크의 `sourceAudioPath`·고정 세션의 `activeAudioPath`는 **실제로 재생한
//     파일**을 적는다(보정본을 틀었으면 보정본 경로). 반주 자르기·믹스는 그 경로가
//     살아 있으면 그걸 쓰고, 사본이 축출돼 없으면 원본 슬롯 파일로 물러난다 —
//     **ffmpeg 시간축(자르기·믹스)에서만** 둘이 표본 단위로 같다(입력 쪽 `-ss`는 VBR
//     원본에서도 오차 0.00ms로 실측). 플레이어 축은 다르다: 원본 위에서 받은 조각의
//     좌표는 MF 머리 상수(+12ms)만큼 늦다(playback_copy_plan.dart 머리말).
//   · **그 밖의 전부는 원본**을 쓴다 — 키·템포 변형본 렌더, 구운 키조절 슬롯, 조성
//     추정, EQ 레벨·노래 구간 분석, 반주 내보내기, 백업, 폰 동기화. 전부
//     `repo.getBackingTrackPath(파일명)`으로 원본을 집고, 캐시 키도 원본 파일명이다.
//     사본은 언제든 축출되는 파생물이라, 여기에 의존하면 축출 때 사슬이 끊긴다.
//
// ── 파생 데이터 규칙 ─────────────────────────────────────
//   · 위치: OneDrive **밖**의 앱 캐시 폴더(`%LOCALAPPDATA%\com.svil\singpromfter_app\
//     playback`). Documents/data 아래에 두면 최대 2GB가 OneDrive로 올라가고, 업로드
//     중 잡힌 핸들 때문에 rename·삭제가 실패한다. data/mp3에 두면 고아 점검이 지운다.
//   · 백업·폰 동기화는 곡 모델이 가리키는 파일만 싣는다 — 이 폴더는 어디에도 안 실린다.
//   · 원본은 **절대** 고치거나 지우지 않는다. 읽기만 한다.
//   · 실패는 치명적이지 않다. 못 구우면 null을 돌려주고 원본이 그대로 재생된다.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/audio_header_probe.dart';
import '../utils/playback_copy_plan.dart';
import 'process/external_tool_locator.dart';
import 'process/process_runner.dart';

/// 곡을 물릴 때의 조회 결과. 굽지 않는다 — 있는 것만 본다.
class PlaybackCopyLookup {
  /// 지금 쓸 수 있는 보정본 경로. 없으면 null.
  final String? copyPath;

  /// 원본이 VBR MP3인데 쓸 보정본이 없다 — 뒤에서 구워야 한다.
  final bool needsCopy;

  const PlaybackCopyLookup({this.copyPath, this.needsCopy = false});

  static const none = PlaybackCopyLookup();
}

class PlaybackCopyService {
  final ProcessRunner _runner;
  final ExternalToolLocator _locator;
  final Future<Directory> Function()? _cacheDirBuilder;
  final Future<AudioHeaderProbe> Function(String path) _prober;

  /// 캐시 용량 상한. 넘으면 오래 안 쓴 사본부터 버린다.
  final int maxCacheBytes;

  /// 녹음·고정 조각이 열려 있을 때 다시 확인하는 간격과, 기다리다 포기하는 시간.
  final Duration busyRetryDelay;
  final Duration busyMaxWait;

  /// 렌더 한 번의 상한. 실측 0.2~0.34초라, 이걸 넘기면 뭔가 멎은 것이다.
  final Duration renderTimeout;

  /// 지금 플레이어가 물고 있는 파일 경로. 용량 축출에서 그 사본을 지킨다.
  String? Function()? activePathProvider;

  PlaybackCopyService({
    ProcessRunner runner = const SystemProcessRunner(),
    ExternalToolLocator? locator,
    Future<Directory> Function()? cacheDirBuilder,
    Future<AudioHeaderProbe> Function(String path)? prober,
    this.maxCacheBytes = kPlaybackCopyCacheMaxBytes,
    this.busyRetryDelay = const Duration(seconds: 3),
    this.busyMaxWait = const Duration(minutes: 30),
    this.renderTimeout = const Duration(seconds: 120),
  }) : _runner = runner,
       _locator = locator ?? ExternalToolLocator(runner: runner),
       _cacheDirBuilder = cacheDirBuilder,
       _prober = prober ?? probeAudioFile;

  Directory? _cacheDir;

  /// 같은 원본(지문 포함)의 렌더는 하나만 돈다 — 나중 호출은 같은 Future를 기다린다.
  final Map<String, Future<String?>> _inFlight = {};

  /// 이번 실행에서 굽다 실패한 지문. 곡을 물릴 때마다 같은 실패를 되풀이하지 않는다.
  final Set<String> _failed = {};

  /// 머리 바이트 판정 결과(지문별). 같은 곡을 다시 물릴 때 파일을 또 읽지 않는다.
  final Map<String, AudioHeaderProbe> _probes = {};

  /// 렌더는 **한 번에 하나**만 돈다 — 이 꼬리에 줄을 세운다.
  Future<void> _tail = Future<void>.value();

  JobHandle? _running;
  bool _disposed = false;

  /// 사본 폴더. 앱 캐시 폴더를 못 얻으면(테스트의 가짜 path_provider 등)
  /// Documents/data/cache/playback으로 물러난다 — 거기도 백업·동기화에는 안 실린다.
  Future<Directory> get cacheDir async {
    final known = _cacheDir;
    if (known != null) {
      if (!await known.exists()) await known.create(recursive: true);
      return known;
    }
    Directory dir;
    final custom = _cacheDirBuilder;
    if (custom != null) {
      dir = await custom();
    } else {
      try {
        dir = Directory(
          '${(await getApplicationCacheDirectory()).path}'
          '${Platform.pathSeparator}playback',
        );
      } catch (_) {
        final docs = await getApplicationDocumentsDirectory();
        dir = Directory('${docs.path}/data/cache/playback');
      }
    }
    if (!await dir.exists()) await dir.create(recursive: true);
    return _cacheDir = dir;
  }

  /// 지금 쓸 수 있는 보정본이 있는지 **조회만** 한다. 굽지 않고, 던지지 않는다.
  ///
  /// 곡을 물리는 길에서 불리므로 가볍다 — 원본 stat 한 번, 사본 stat 한 번, 그리고
  /// 사본이 없을 때만 원본 머리 64KB를 읽어 VBR인지 본다(결과는 기억한다).
  Future<PlaybackCopyLookup> lookup({
    required String sourcePath,
    required String sourceFileName,
  }) async {
    try {
      final name = await _copyNameFor(sourcePath, sourceFileName);
      if (name == null) return PlaybackCopyLookup.none;
      final copy = File(_join((await cacheDir).path, name));
      if (await _isUsable(copy)) {
        await _touch(copy);
        return PlaybackCopyLookup(copyPath: copy.path);
      }
      final probe = await _probe(sourcePath, name);
      return PlaybackCopyLookup(needsCopy: probe.needsSeekCopy);
    } catch (e) {
      debugPrint('위치 보정본 조회 실패($sourceFileName): $e');
      return PlaybackCopyLookup.none;
    }
  }

  /// 곡을 물릴 때의 한 걸음 — 재생할 파일과 그 성격을 정한다. **기다리지 않는다.**
  ///
  /// - 쓸 보정본이 있다 → 그 경로(seekCopy)
  /// - VBR 원본인데 보정본이 없다 → 원본(path: null, vbrOriginal) + 굽기를 뒤에 건다.
  ///   구워진 사본은 **다음에 물릴 때** 쓰인다 — 재생 중인 파일을 갈아끼우지 않는다.
  /// - 그 밖(CBR·m4a·WAV·못 읽음) → 원본(plain)
  Future<PlaybackCopyResolution> resolveForLoad({
    required String sourcePath,
    required String sourceFileName,
    bool Function()? isBusy,
    Duration startDelay = kPlaybackCopyStartDelay,
  }) async {
    final found = await lookup(
      sourcePath: sourcePath,
      sourceFileName: sourceFileName,
    );
    final copyPath = found.copyPath;
    if (copyPath != null) {
      return (path: copyPath, kind: PlaybackSourceKind.seekCopy);
    }
    if (!found.needsCopy) return kPlainPlayback;
    _runInBackground(
      ensure(
        sourcePath: sourcePath,
        sourceFileName: sourceFileName,
        isBusy: isBusy,
        startDelay: startDelay,
      ),
    );
    return (path: null, kind: PlaybackSourceKind.vbrOriginal);
  }

  /// 뒤에 걸어 둔 굽기가 전부 끝날 때까지 기다린다(테스트용).
  @visibleForTesting
  Future<void> settle() async {
    while (_background.isNotEmpty) {
      await Future.wait(_background.toList());
    }
  }

  final Set<Future<void>> _background = {};

  /// 기다리지 않는 작업을 걸고, 끝나면 목록에서 뺀다. 실패는 [ensure]가 이미 삼켰다.
  void _runInBackground(Future<String?> job) {
    late final Future<void> tracked;
    tracked = job.then<void>((_) {}, onError: (_) {}).whenComplete(() {
      _background.remove(tracked);
    });
    _background.add(tracked);
  }

  /// 보정본을 준비한다 — 있으면 그대로, VBR인데 없으면 굽는다. 경로 또는 null.
  ///
  /// VBR이 아니거나, ffmpeg가 없거나, 굽다 실패하면 null이다(원본을 그대로 쓰면 된다).
  /// 같은 원본을 동시에 불러도 렌더는 한 번만 돌고, 서로 다른 원본은 한 줄로 선다.
  ///
  /// [startDelay]만큼 기다렸다가 시작한다 — 곡을 물린 직후에는 플레이어가 파일을 열고
  /// EQ 분석이 도는 참이라, 그 뒤로 비켜 선다(우선순위가 가장 낮은 일이다).
  /// [isBusy]가 참인 동안(녹음 중·고정 조각이 열림)에는 시작하지 않고 기다린다.
  Future<String?> ensure({
    required String sourcePath,
    required String sourceFileName,
    bool Function()? isBusy,
    Duration startDelay = Duration.zero,
  }) async {
    if (_disposed) return null;
    try {
      final name = await _copyNameFor(sourcePath, sourceFileName);
      if (name == null) return null;
      final copy = File(_join((await cacheDir).path, name));
      if (await _isUsable(copy)) return copy.path;
      if (_failed.contains(name)) return null;
      final probe = await _probe(sourcePath, name);
      if (!probe.needsSeekCopy) return null;

      final running = _inFlight[name];
      if (running != null) return await running;
      final job = _enqueue(
        () => _render(
          sourcePath: sourcePath,
          sourceFileName: sourceFileName,
          name: name,
          isBusy: isBusy,
          startDelay: startDelay,
        ),
      );
      _inFlight[name] = job;
      try {
        return await job;
      } finally {
        _inFlight.remove(name);
      }
    } catch (e) {
      debugPrint('위치 보정본 준비 실패($sourceFileName): $e');
      return null;
    }
  }

  /// [sourceFileName]에서 나온 사본을 전부 지운다(지문 무관). 지운 개수.
  /// 반주를 갈아끼우거나 뺄 때 TrackAssetService가 부른다.
  Future<int> clearFor(String sourceFileName) async {
    if (sourceFileName.trim().isEmpty) return 0;
    try {
      return await _deleteWhere(
        (name) => isPlaybackCopyOf(name, sourceFileName),
      );
    } catch (e) {
      debugPrint('위치 보정본 정리 실패($sourceFileName): $e');
      return 0;
    }
  }

  /// 쓸모없어진 사본을 치운다. 지운 개수를 돌려준다.
  ///
  /// - 원본이 사라진 사본(곡·반주 삭제 — 그 길은 파일명 무효화를 부르지 않는다)
  /// - 지문이 안 맞는 사본(같은 이름으로 다른 오디오가 들어왔다)
  /// - 지난 실행이 굽다 죽어 남긴 `.part`
  /// 그다음 용량 상한에 맞춘다. 앱을 켤 때와 「라이브러리 정리」에서 부른다.
  Future<int> sweep({
    required Iterable<String> liveSourceFileNames,
    required Future<String?> Function(String sourceFileName) sourcePathOf,
  }) async {
    try {
      final dir = await cacheDir;
      final byPrefix = {
        for (final name in liveSourceFileNames) playbackCopyPrefix(name): name,
      };
      final expected = <String, String?>{};
      var removed = 0;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = _baseName(entity.path);
        final prefix = playbackCopyPrefixOf(name);
        if (prefix == null) continue; // 우리가 만든 파일이 아니다.
        if (_isInFlight(name)) continue;
        var stale = name.endsWith(kPlaybackCopyPartSuffix);
        if (!stale) {
          final source = byPrefix[prefix];
          if (source == null) {
            stale = true;
          } else {
            if (!expected.containsKey(source)) {
              final path = await sourcePathOf(source);
              expected[source] = path == null
                  ? null
                  : await _copyNameFor(path, source);
            }
            stale = expected[source] != name;
          }
        }
        if (stale && await _deleteQuietly(entity)) removed += 1;
      }
      removed += await trimTo(maxCacheBytes);
      return removed;
    } catch (e) {
      debugPrint('위치 보정본 점검 실패: $e');
      return 0;
    }
  }

  /// 캐시 총 용량(바이트). 굽는 중인 `.part`도 센다 — 디스크를 차지하는 건 같다.
  Future<int> cacheSize() async {
    var total = 0;
    try {
      await for (final entity in (await cacheDir).list()) {
        if (entity is! File) continue;
        if (playbackCopyPrefixOf(_baseName(entity.path)) == null) continue;
        total += await entity.length();
      }
    } catch (e) {
      debugPrint('위치 보정본 용량 계산 실패: $e');
    }
    return total;
  }

  /// 사본을 전부 지운다. 파생물이라 언제든 다시 구울 수 있다. 지운 개수.
  Future<int> clearCache() async {
    try {
      return await _deleteWhere((_) => true);
    } catch (e) {
      debugPrint('위치 보정본 캐시 삭제 실패: $e');
      return 0;
    }
  }

  /// 캐시를 [maxBytes] 아래로 줄인다 — 오래 안 쓴 것부터. 지운 개수.
  /// [keep]과 지금 재생 중인 사본, 굽는 중인 파일은 건드리지 않는다.
  Future<int> trimTo(int maxBytes, {Set<String> keep = const {}}) async {
    try {
      final dir = await cacheDir;
      final entries = <PlaybackCopyEntry>[];
      final files = <String, File>{};
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = _baseName(entity.path);
        if (playbackCopyPrefixOf(name) == null) continue;
        final stat = await entity.stat();
        files[name] = entity;
        entries.add((
          name: name,
          bytes: stat.size,
          lastUsedMs: stat.modified.millisecondsSinceEpoch,
        ));
      }
      final active = activePathProvider?.call();
      final protect = {
        ...keep,
        if (active != null) _baseName(active),
        for (final name in _inFlight.keys) ...[
          name,
          '$name$kPlaybackCopyPartSuffix',
        ],
      };
      var removed = 0;
      for (final name in planPlaybackCopyEviction(
        entries,
        maxBytes: maxBytes,
        keep: protect,
      )) {
        if (await _deleteQuietly(files[name]!)) removed += 1;
      }
      return removed;
    } catch (e) {
      debugPrint('위치 보정본 용량 정리 실패: $e');
      return 0;
    }
  }

  /// 앱을 닫을 때 부른다 — 굽던 ffmpeg를 끊는다(남은 `.part`는 다음 실행이 치운다).
  void dispose() {
    _disposed = true;
    _running?.cancel();
  }

  // ── 내부 ────────────────────────────────────────────────

  /// 한 줄로 세운다. 앞 작업이 어떻게 끝났든 다음 작업은 돈다.
  Future<String?> _enqueue(Future<String?> Function() job) {
    final run = _tail.then((_) => job());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  /// 실제로 굽는다 — `.part`에 쓰고, 성공하면 rename으로 확정한다.
  Future<String?> _render({
    required String sourcePath,
    required String sourceFileName,
    required String name,
    required bool Function()? isBusy,
    required Duration startDelay,
  }) async {
    File? part;
    try {
      if (startDelay > Duration.zero) await Future<void>.delayed(startDelay);
      // 녹음 중·고정 조각이 열린 동안에는 디스크와 CPU를 건드리지 않는다.
      var waited = Duration.zero;
      while (!_disposed && (isBusy?.call() ?? false)) {
        if (waited >= busyMaxWait) return null;
        await Future<void>.delayed(busyRetryDelay);
        waited += busyRetryDelay;
      }
      if (_disposed) return null;

      // 기다리는 사이에 원본이 바뀌었으면 이 렌더는 무의미하다(다음 물림이 새로 건다).
      if (await _copyNameFor(sourcePath, sourceFileName) != name) return null;
      final out = File(_join((await cacheDir).path, name));
      if (await _isUsable(out)) return out.path;

      final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);
      if (!ffmpeg.found) {
        _failed.add(name);
        return null;
      }

      part = File('${out.path}$kPlaybackCopyPartSuffix');
      await _deleteQuietly(part);
      final job = _runner.start(
        ffmpeg.path!,
        buildPlaybackCopyArgs(input: sourcePath, output: part.path),
      );
      _running = job;
      final lastLines = <String>[];
      final sub = job.lines.listen((line) {
        lastLines.add(line);
        if (lastLines.length > 6) lastLines.removeAt(0);
      }, onError: (_) {});
      int exitCode;
      try {
        exitCode = await job.exitCode.timeout(
          renderTimeout,
          onTimeout: () {
            job.cancel();
            return -1;
          },
        );
      } finally {
        _running = null;
        await sub.cancel();
      }

      if (exitCode != 0 || !await _isUsable(part)) {
        debugPrint(
          '위치 보정본 렌더 실패($sourceFileName, 종료 $exitCode): '
          '${lastLines.join(' | ')}',
        );
        await _deleteQuietly(part);
        if (!_disposed) _failed.add(name);
        return null;
      }
      // 굽는 0.3초 사이에 원본이 갈렸으면 이 사본은 옛 오디오다 — 버린다.
      if (await _copyNameFor(sourcePath, sourceFileName) != name) {
        await _deleteQuietly(part);
        return null;
      }

      // 같은 원본의 옛 지문 사본을 먼저 치운다(재생 중이라 잠긴 것은 건너뛴다).
      final partName = _baseName(part.path);
      await _deleteWhere(
        (other) =>
            isPlaybackCopyOf(other, sourceFileName) &&
            other != name &&
            other != partName,
      );
      await part.rename(out.path);
      await trimTo(maxCacheBytes, keep: {name});
      return out.path;
    } catch (e) {
      debugPrint('위치 보정본 렌더 중 오류($sourceFileName): $e');
      if (part != null) await _deleteQuietly(part);
      _failed.add(name);
      return null;
    }
  }

  /// 원본의 지금 지문으로 사본 이름을 만든다. 원본이 없으면 null.
  Future<String?> _copyNameFor(String sourcePath, String sourceFileName) async {
    final stat = await File(sourcePath).stat();
    if (stat.type != FileSystemEntityType.file) return null;
    return playbackCopyFileName(
      sourceFileName,
      sizeBytes: stat.size,
      modifiedMs: stat.modified.millisecondsSinceEpoch,
    );
  }

  Future<AudioHeaderProbe> _probe(String sourcePath, String name) async =>
      _probes[name] ??= await _prober(sourcePath);

  /// 확정된 사본인가 — 있고, WAV 헤더보다 크다. (`.part`에서 rename된 것만 이 이름을
  /// 가지므로 반쪽 파일일 수는 없다.)
  Future<bool> _isUsable(File file) async {
    try {
      return await file.exists() &&
          await file.length() >= kPlaybackCopyMinBytes;
    } catch (_) {
      return false;
    }
  }

  /// 「방금 썼다」를 수정시각으로 남긴다 — 용량 축출이 이 값으로 오래된 순을 매긴다.
  Future<void> _touch(File file) async {
    try {
      await file.setLastModified(DateTime.now());
    } catch (_) {
      // 재생 중이라 잠겼으면 못 바꾼다 — 축출 순서가 조금 흐려질 뿐이다.
    }
  }

  bool _isInFlight(String name) {
    for (final running in _inFlight.keys) {
      if (name == running || name == '$running$kPlaybackCopyPartSuffix') {
        return true;
      }
    }
    return false;
  }

  /// 조건에 맞는 우리 파일을 지운다. 🔴 **파일 단위로** 시도한다 — 재생 중인 사본은
  /// Windows에서 잠겨 있어, 루프 전체를 try 하나로 감싸면 거기서 나머지가 멈춘다.
  Future<int> _deleteWhere(bool Function(String name) test) async {
    final dir = await cacheDir;
    var removed = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = _baseName(entity.path);
      if (playbackCopyPrefixOf(name) == null) continue;
      if (_isInFlight(name) || !test(name)) continue;
      if (await _deleteQuietly(entity)) removed += 1;
    }
    return removed;
  }

  Future<bool> _deleteQuietly(File file) async {
    try {
      if (!await file.exists()) return false;
      await file.delete();
      return true;
    } catch (_) {
      return false; // 잠긴 파일 — 다음 점검이 다시 시도한다.
    }
  }

  static String _join(String dir, String name) =>
      '$dir${Platform.pathSeparator}$name';

  /// `/`와 `\`가 섞인 경로에서도 파일 이름만 떼어 낸다.
  static String _baseName(String path) {
    final cut = path.lastIndexOf(RegExp(r'[\\/]'));
    return cut < 0 ? path : path.substring(cut + 1);
  }
}
