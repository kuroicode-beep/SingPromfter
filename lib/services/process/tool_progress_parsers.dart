// file: lib/services/process/tool_progress_parsers.dart
//
// yt-dlp·ffmpeg의 진행 출력 파서. 전부 순수 함수라 프로세스 없이 테스트한다.

/// 작업 진행 상황 한 조각.
class JobProgress {
  /// 0~1. 알 수 없으면 null.
  final double? ratio;

  /// 사용자에게 보여줄 짧은 한국어 설명.
  final String? label;

  const JobProgress({this.ratio, this.label});
}

class YtDlpProgressParser {
  YtDlpProgressParser._();

  // 예) [download]  42.3% of  4.21MiB at  1.23MiB/s ETA 00:02
  static final RegExp _download = RegExp(r'^\[download\]\s+([\d.]+)%');
  static final RegExp _destination = RegExp(r'^\[download\]\s+Destination:');

  /// 한 줄을 해석한다. 진행과 무관한 줄이면 null.
  static JobProgress? parse(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;

    final match = _download.firstMatch(trimmed);
    if (match != null) {
      final percent = double.tryParse(match.group(1)!);
      if (percent == null) return null;
      return JobProgress(
        ratio: (percent / 100).clamp(0.0, 1.0),
        label: '내려받는 중 ${percent.toStringAsFixed(1)}%',
      );
    }

    if (_destination.hasMatch(trimmed)) {
      return const JobProgress(label: '내려받는 중');
    }
    if (trimmed.startsWith('[ExtractAudio]')) {
      return const JobProgress(label: '오디오 추출 중');
    }
    if (trimmed.startsWith('[Merger]')) {
      return const JobProgress(label: '합치는 중');
    }
    return null;
  }

  /// 에러로 볼 만한 줄인지.
  static bool isError(String line) {
    final trimmed = line.trim();
    return trimmed.startsWith('ERROR:') || trimmed.startsWith('yt-dlp: error');
  }
}

class FfmpegProgressParser {
  FfmpegProgressParser._();

  /// `-progress pipe:1 -nostats`가 내보내는 key=value 줄을 해석한다.
  ///
  /// 주의: ffmpeg의 `out_time_ms`는 이름과 달리 **마이크로초**다.
  /// 실측 확인함 — 2초 입력에서 out_time_us와 out_time_ms가 모두 2000000.
  /// 따라서 둘 다 마이크로초로 취급한다.
  static Duration? parseOutTime(String line) {
    final trimmed = line.trim();
    final eq = trimmed.indexOf('=');
    if (eq <= 0) return null;
    final key = trimmed.substring(0, eq);
    final value = trimmed.substring(eq + 1).trim();

    if (key == 'out_time_us' || key == 'out_time_ms') {
      final micros = int.tryParse(value);
      if (micros == null || micros < 0) return null;
      return Duration(microseconds: micros);
    }
    return null;
  }

  /// 전체 길이를 알 때 진행률을 만든다.
  static JobProgress? parse(String line, {Duration? total}) {
    if (line.trim() == 'progress=end') {
      return const JobProgress(ratio: 1, label: '변환 완료');
    }

    final out = parseOutTime(line);
    if (out == null) return null;
    if (total == null || total <= Duration.zero) {
      return JobProgress(label: '변환 중 ${_mmss(out)}');
    }
    final ratio = (out.inMicroseconds / total.inMicroseconds).clamp(0.0, 1.0);
    return JobProgress(
      ratio: ratio,
      label: '변환 중 ${(ratio * 100).toStringAsFixed(0)}%',
    );
  }

  static String _mmss(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
