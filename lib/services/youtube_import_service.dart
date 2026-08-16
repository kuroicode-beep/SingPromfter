// file: lib/services/youtube_import_service.dart
//
// 유튜브 링크에서 오디오를 받아 곡으로 등록할 준비를 한다.
//
// 방침: yt-dlp·ffmpeg를 앱에 번들하지 않고 사용자 환경의 도구를 호출한다.
// 작업은 data/tmp/<jobId>/에서 진행하고 성공했을 때만 라이브러리로 옮긴다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/mr_source_mode.dart';
import '../utils/lrc_edit.dart';
import '../utils/youtube_subtitle.dart';
import 'process/external_tool_locator.dart';
import 'process/process_runner.dart';
import 'process/tool_progress_parsers.dart';

/// yt-dlp 실패 원인을 사람 말로 바꾼다. (순수 함수 — 테스트 대상)
///
/// 예전엔 모든 실패에 "오래된 yt-dlp가 원인일 수 있어요"를 붙였는데,
/// 403(유튜브 일시 차단)에도 그 안내가 나와 사용자를 엉뚱한 데로 보냈다.
/// 원인별로 다음 행동이 다르다: 403은 기다리고, 해석 실패는 업데이트하고,
/// 그 외는 실제 오류를 보여 준다.
String describeDownloadFailure(
  List<String> errorLines, {
  required int exitCode,
  required bool nodeFound,
  bool? ejsFound,
}) {
  final detail = errorLines.isEmpty ? '종료 코드 $exitCode' : errorLines.last;
  if (detail.contains('403') || detail.contains('Forbidden')) {
    // 해석기 부재는 403의 근본 원인이라 안내를 최우선으로 둔다(2026-08-16 실사고).
    if (ejsFound == false) {
      return '유튜브가 요청을 막았습니다(403). JS 해석기(yt-dlp-ejs)가 없어 '
          '계속 실패할 수 있어요 — 설정 > 데이터·도구에서 확인해 주세요.';
    }
    final hint = nodeFound
        ? ''
        : ' Node.js가 없으면 제한된 방식으로 받아 이 오류가 잦습니다 — '
              '설치를 권합니다(${ExternalTool.node.installHint}).';
    return '유튜브가 일시적으로 요청을 막았습니다(403). '
        '같은 곡의 다른 영상으로 시도하거나 잠시 후 다시 시도해 주세요.$hint';
  }
  if (detail.contains('Unable to extract') ||
      detail.contains('Unsupported URL') ||
      detail.contains('Sign in to confirm')) {
    return '영상을 해석하지 못했습니다: $detail — '
        '오래된 yt-dlp가 원인일 수 있어요. 설정에서 업데이트(-U)를 실행해 보세요.';
  }
  return '내려받기에 실패했습니다: $detail';
}

/// 다운로드 전에 조회한 영상 정보.
class YoutubeMetadata {
  final String id;
  final String title;
  final String uploader;
  final Duration duration;

  const YoutubeMetadata({
    required this.id,
    required this.title,
    required this.uploader,
    required this.duration,
  });

  factory YoutubeMetadata.fromJson(Map<String, dynamic> json) {
    final seconds = (json['duration'] as num?)?.round() ?? 0;
    return YoutubeMetadata(
      id: json['id'] as String? ?? '',
      title: (json['title'] as String? ?? '').trim(),
      uploader:
          (json['uploader'] as String? ?? json['channel'] as String? ?? '')
              .trim(),
      duration: Duration(seconds: seconds),
    );
  }
}

class YoutubeImportResult {
  final bool success;
  final String? audioPath;
  final YoutubeMetadata? metadata;
  final String? message;

  const YoutubeImportResult._({
    required this.success,
    this.audioPath,
    this.metadata,
    this.message,
  });

  const YoutubeImportResult.success({
    required String audioPath,
    required YoutubeMetadata metadata,
  }) : this._(success: true, audioPath: audioPath, metadata: metadata);

  const YoutubeImportResult.failure(String message)
    : this._(success: false, message: message);
}

/// 링크가 유튜브 주소로 보이는지 확인한다. (순수 함수)
bool looksLikeYoutubeUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) return false;
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  final host = uri.host.toLowerCase().replaceFirst('www.', '');
  const hosts = {
    'youtube.com',
    'm.youtube.com',
    'music.youtube.com',
    'youtu.be',
  };
  return hosts.contains(host);
}

/// 유튜브 링크에서 영상 ID를 뽑는다. 못 찾으면 null. (순수 함수 — 테스트 대상)
///
/// 같은 영상을 다시 추가하려는지 판별하는 데 쓴다 — URL 표기가 달라도
/// (youtu.be 단축, 쿼리 순서, shorts/embed 경로) ID가 같으면 같은 영상이다.
String? youtubeVideoId(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return null;
  final host = uri.host.toLowerCase().replaceFirst('www.', '');
  if (host == 'youtu.be') {
    return uri.pathSegments.isEmpty || uri.pathSegments.first.isEmpty
        ? null
        : uri.pathSegments.first;
  }
  final v = uri.queryParameters['v'];
  if (v != null && v.isNotEmpty) return v;
  final segments = uri.pathSegments;
  if (segments.length >= 2 &&
      (segments[0] == 'shorts' || segments[0] == 'embed')) {
    return segments[1].isEmpty ? null : segments[1];
  }
  return null;
}

/// 너무 긴 영상(라이브 등)을 걸러내기 위한 상한.
const Duration maxImportDuration = Duration(minutes: 30);

class YoutubeImportService {
  final ProcessRunner _runner;
  final ExternalToolLocator _locator;
  final Future<Directory> Function() _tmpDirProvider;

  YoutubeImportService({
    required Future<Directory> Function() tmpDirProvider,
    ProcessRunner runner = const SystemProcessRunner(),
    ExternalToolLocator? locator,
  }) : _runner = runner,
       _locator = locator ?? ExternalToolLocator(runner: runner),
       _tmpDirProvider = tmpDirProvider;

  /// yt-dlp의 YouTube JS 챌린지 해석에 쓸 node 지정 인자.
  ///
  /// PC 전역 설정(%APPDATA%\yt-dlp\config)에 기대지 않고 앱이 직접 넘긴다 —
  /// 설정 파일이 지워지면 다운로드가 403/포맷 누락으로 조용히 깨졌었다.
  /// node가 없으면 빈 목록(yt-dlp가 알아서 폴백하고, 실패 시 안내한다).
  Future<List<String>> _jsRuntimeArgs() async {
    final node = await _locator.locate(ExternalTool.node);
    if (!node.found) return const [];
    return ['--js-runtimes', 'node:${node.path!}'];
  }

  /// 내려받기 전에 제목·가수·길이를 먼저 조회한다.
  /// 사용자가 등록 대화상자를 미리 채우고 취소할 수 있게 하기 위해서다.
  Future<YoutubeMetadata?> fetchMetadata(String url) async {
    final tool = await _locator.locate(ExternalTool.ytDlp);
    if (!tool.found) return null;

    final result = await _runner.run(tool.path!, [
      '--dump-single-json',
      '--no-playlist',
      ...await _jsRuntimeArgs(),
      url,
    ]);
    if (!result.ok || result.stdout.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(result.stdout);
      if (decoded is! Map<String, dynamic>) return null;
      return YoutubeMetadata.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// 업로더가 단 **한국어 수동 자막**을 세그먼트로 가져온다. 없으면 null.
  ///
  /// 수동 자막은 타이밍까지 있는 사실상 완성 LRC라 받아쓰기보다 훨씬
  /// 정확하다. 자동 생성 자막(ASR)은 환청 문제가 같아서 받지 않는다
  /// (--write-subs만 쓰고 --write-auto-subs는 안 쓴다).
  Future<List<SttSegment>?> fetchManualSubtitles(String url) async {
    final tool = await _locator.locate(ExternalTool.ytDlp);
    if (!tool.found) return null;

    final workDir = Directory(
      '${(await _tmpDirProvider()).path}${Platform.pathSeparator}'
      'subs_${DateTime.now().millisecondsSinceEpoch}',
    );
    await workDir.create(recursive: true);
    try {
      final result = await _runner.run(tool.path!, [
        '--skip-download',
        '--write-subs',
        '--sub-langs', 'ko.*',
        '--sub-format', 'json3',
        '--no-playlist',
        ...await _jsRuntimeArgs(),
        '-o', '${workDir.path}${Platform.pathSeparator}subs.%(ext)s',
        url,
      ]);
      if (!result.ok) return null;
      final files = workDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json3'))
          .toList();
      if (files.isEmpty) return null; // 수동 자막 없음 — 정상 폴백 경로
      final segments = segmentsFromJson3(await files.first.readAsString());
      return segments.isEmpty ? null : segments;
    } catch (e, stack) {
      debugPrint('유튜브 자막 조회 실패: $e\n$stack');
      return null;
    } finally {
      try {
        await workDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// 오디오를 내려받아 임시 폴더에 mp3로 남긴다.
  ///
  /// [onProgress]로 진행률을, [onCancel]에 취소 핸들을 넘겨준다.
  Future<YoutubeImportResult> download({
    required String url,
    required String jobId,
    required YoutubeMetadata metadata,
    MrSourceMode mode = MrSourceMode.asIs,
    void Function(JobProgress progress)? onProgress,
    void Function(void Function() cancel)? onCancel,
  }) async {
    if (!looksLikeYoutubeUrl(url)) {
      return const YoutubeImportResult.failure('유튜브 주소가 아닙니다.');
    }
    if (metadata.duration > maxImportDuration) {
      return YoutubeImportResult.failure(
        '영상이 너무 깁니다(${metadata.duration.inMinutes}분). '
        '${maxImportDuration.inMinutes}분 이하만 가져올 수 있습니다.',
      );
    }

    final ytDlp = await _locator.locate(ExternalTool.ytDlp);
    if (!ytDlp.found) {
      return const YoutubeImportResult.failure(
        'yt-dlp를 찾을 수 없습니다. 설치한 뒤 설정에서 경로를 지정해 주세요.',
      );
    }
    final ffmpeg = await _locator.locate(ExternalTool.ffmpeg);

    final workDir = Directory(
      '${(await _tmpDirProvider()).path}${Platform.pathSeparator}$jobId',
    );
    if (!await workDir.exists()) await workDir.create(recursive: true);

    final jsRuntime = await _jsRuntimeArgs();
    final args = <String>[
      '-x',
      '--audio-format', 'mp3',
      '--audio-quality', '0',
      '--no-playlist',
      '--newline',
      if (ffmpeg.found) ...['--ffmpeg-location', ffmpeg.path!],
      ...jsRuntime,
      '-o', '${workDir.path}${Platform.pathSeparator}audio.%(ext)s',
      url,
    ];

    final job = _runner.start(ytDlp.path!, args, workingDirectory: workDir.path);
    onCancel?.call(job.cancel);

    final errors = <String>[];
    final sub = job.lines.listen((line) {
      final progress = YtDlpProgressParser.parse(line);
      if (progress != null) onProgress?.call(progress);
      if (YtDlpProgressParser.isError(line)) errors.add(line.trim());
    });

    final exitCode = await job.exitCode;
    await sub.cancel();

    if (exitCode != 0) {
      await _cleanup(workDir);
      // 실패했을 때만 EJS 해석기 존재를 조회한다(-v 프로브 1회, 약 1~2초) —
      // 403의 근본 원인(해석기 부재)을 실패 안내에 바로 실어 주기 위해서다.
      final ejsVersion = await _locator.ytDlpEjsVersion(ytDlp.path!);
      return YoutubeImportResult.failure(
        describeDownloadFailure(
          errors,
          exitCode: exitCode,
          nodeFound: jsRuntime.isNotEmpty,
          ejsFound: ejsVersion != null,
        ),
      );
    }

    var audioPath = '${workDir.path}${Platform.pathSeparator}audio.mp3';
    if (!await File(audioPath).exists()) {
      final found = await _findAudioFile(workDir);
      if (found == null) {
        await _cleanup(workDir);
        return const YoutubeImportResult.failure('내려받은 오디오 파일을 찾지 못했습니다.');
      }
      audioPath = found;
    }

    if (mode == MrSourceMode.reduceVocal) {
      if (!ffmpeg.found) {
        return const YoutubeImportResult.failure(
          '보컬 줄이기에는 ffmpeg가 필요합니다. 설치한 뒤 다시 시도해 주세요.',
        );
      }
      onProgress?.call(const JobProgress(label: '보컬 줄이는 중'));
      final reduced = await _reduceVocal(
        ffmpegPath: ffmpeg.path!,
        input: audioPath,
        workDir: workDir,
        total: metadata.duration,
        onProgress: onProgress,
      );
      if (reduced == null) {
        return const YoutubeImportResult.failure('보컬 줄이기에 실패했습니다.');
      }
      audioPath = reduced;
    }

    return YoutubeImportResult.success(
      audioPath: audioPath,
      metadata: metadata,
    );
  }

  /// 센터 채널 제거로 보컬을 줄인다. 간이 방식이라 음질 저하가 있다.
  Future<String?> _reduceVocal({
    required String ffmpegPath,
    required String input,
    required Directory workDir,
    required Duration total,
    void Function(JobProgress progress)? onProgress,
  }) async {
    final output = '${workDir.path}${Platform.pathSeparator}audio_mr.mp3';
    final job = _runner.start(ffmpegPath, [
      '-y',
      '-i', input,
      '-af', 'pan=stereo|c0=c0-c1|c1=c1-c0',
      '-progress', 'pipe:1',
      '-nostats',
      output,
    ]);

    final sub = job.lines.listen((line) {
      final progress = FfmpegProgressParser.parse(line, total: total);
      if (progress != null) onProgress?.call(progress);
    });
    final exitCode = await job.exitCode;
    await sub.cancel();

    if (exitCode != 0 || !await File(output).exists()) return null;
    return output;
  }

  Future<String?> _findAudioFile(Directory dir) async {
    const audioExtensions = ['.mp3', '.m4a', '.opus', '.webm', '.wav'];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final lower = entity.path.toLowerCase();
      if (audioExtensions.any(lower.endsWith)) return entity.path;
    }
    return null;
  }

  Future<void> _cleanup(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // 정리 실패는 무시한다 — 다음 실행에서 다시 시도된다.
    }
  }

  /// 작업이 끝난 뒤 임시 폴더를 정리한다.
  Future<void> cleanupJob(String jobId) async {
    final dir = Directory(
      '${(await _tmpDirProvider()).path}${Platform.pathSeparator}$jobId',
    );
    await _cleanup(dir);
  }
}
