// file: lib/services/youtube_import_service.dart
//
// 유튜브 링크에서 오디오를 받아 곡으로 등록할 준비를 한다.
//
// 방침: yt-dlp·ffmpeg를 앱에 번들하지 않고 사용자 환경의 도구를 호출한다.
// 작업은 data/tmp/<jobId>/에서 진행하고 성공했을 때만 라이브러리로 옮긴다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/mr_source_mode.dart';
import 'process/external_tool_locator.dart';
import 'process/process_runner.dart';
import 'process/tool_progress_parsers.dart';

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

  /// 내려받기 전에 제목·가수·길이를 먼저 조회한다.
  /// 사용자가 등록 대화상자를 미리 채우고 취소할 수 있게 하기 위해서다.
  Future<YoutubeMetadata?> fetchMetadata(String url) async {
    final tool = await _locator.locate(ExternalTool.ytDlp);
    if (!tool.found) return null;

    final result = await _runner.run(tool.path!, [
      '--dump-single-json',
      '--no-playlist',
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

    final args = <String>[
      '-x',
      '--audio-format', 'mp3',
      '--audio-quality', '0',
      '--no-playlist',
      '--newline',
      if (ffmpeg.found) ...['--ffmpeg-location', ffmpeg.path!],
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
      final detail = errors.isEmpty ? '종료 코드 $exitCode' : errors.last;
      return YoutubeImportResult.failure('내려받기에 실패했습니다: $detail');
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
