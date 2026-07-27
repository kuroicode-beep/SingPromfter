import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/services/process/external_tool_locator.dart';
import 'package:singpromfter_app/services/process/tool_progress_parsers.dart';

void main() {
  group('YtDlpProgressParser', () {
    test('다운로드 퍼센트를 읽는다', () {
      final p = YtDlpProgressParser.parse(
        '[download]  42.3% of  4.21MiB at  1.23MiB/s ETA 00:02',
      );
      expect(p, isNotNull);
      expect(p!.ratio, closeTo(0.423, 0.0001));
      expect(p.label, contains('42.3'));
    });

    test('0%와 100%도 읽는다', () {
      expect(
        YtDlpProgressParser.parse(
          '[download]   0.0% of  4.21MiB at  Unknown B/s ETA Unknown',
        )!.ratio,
        0,
      );
      expect(
        YtDlpProgressParser.parse(
          '[download] 100% of  4.21MiB in 00:00:03 at 1.40MiB/s',
        )!.ratio,
        1,
      );
    });

    test('단계 표시 줄은 라벨만 준다', () {
      expect(
        YtDlpProgressParser.parse('[ExtractAudio] Destination: a.mp3')!.label,
        '오디오 추출 중',
      );
      expect(
        YtDlpProgressParser.parse('[Merger] Merging formats into "a.mp4"')!.label,
        '합치는 중',
      );
    });

    test('진행과 무관한 줄은 null', () {
      expect(YtDlpProgressParser.parse('[youtube] Extracting URL: ...'), isNull);
      expect(YtDlpProgressParser.parse(''), isNull);
      expect(YtDlpProgressParser.parse('random noise'), isNull);
    });

    test('에러 줄을 구분한다', () {
      expect(
        YtDlpProgressParser.isError('ERROR: Video unavailable'),
        isTrue,
      );
      expect(YtDlpProgressParser.isError('[download] 10%'), isFalse);
    });
  });

  group('FfmpegProgressParser', () {
    // 실측: 2초 입력에서 out_time_us와 out_time_ms가 모두 2000000이다.
    // 즉 out_time_ms는 이름과 달리 마이크로초다.
    test('out_time_us를 마이크로초로 읽는다', () {
      expect(
        FfmpegProgressParser.parseOutTime('out_time_us=2000000'),
        const Duration(seconds: 2),
      );
    });

    test('out_time_ms도 마이크로초로 취급한다 (ffmpeg의 이름 함정)', () {
      expect(
        FfmpegProgressParser.parseOutTime('out_time_ms=2000000'),
        const Duration(seconds: 2),
      );
    });

    test('다른 키는 무시한다', () {
      expect(FfmpegProgressParser.parseOutTime('bitrate=  66.1kbits/s'), isNull);
      expect(FfmpegProgressParser.parseOutTime('speed= 145x'), isNull);
      expect(FfmpegProgressParser.parseOutTime('total_size=16527'), isNull);
      expect(FfmpegProgressParser.parseOutTime('no-equals-sign'), isNull);
    });

    test('전체 길이를 알면 비율을 만든다', () {
      final p = FfmpegProgressParser.parse(
        'out_time_us=30000000',
        total: const Duration(seconds: 60),
      );
      expect(p!.ratio, closeTo(0.5, 0.0001));
    });

    test('길이를 모르면 라벨만 준다', () {
      final p = FfmpegProgressParser.parse('out_time_us=95000000');
      expect(p!.ratio, isNull);
      expect(p.label, contains('01:35'));
    });

    test('progress=end는 완료로 본다', () {
      final p = FfmpegProgressParser.parse('progress=end');
      expect(p!.ratio, 1);
    });

    test('비율은 1을 넘지 않는다', () {
      final p = FfmpegProgressParser.parse(
        'out_time_us=99000000',
        total: const Duration(seconds: 10),
      );
      expect(p!.ratio, 1);
    });
  });

  group('ExternalToolLocator.rankCandidates', () {
    test('사용자 지정 → PATH → 알려진 경로 순', () {
      final ranked = ExternalToolLocator.rankCandidates(
        userPath: r'C:\my\yt-dlp.exe',
        pathLookup: r'C:\path\yt-dlp.exe',
        knownPaths: [r'C:\known\yt-dlp.exe'],
      );
      expect(ranked, [
        r'C:\my\yt-dlp.exe',
        r'C:\path\yt-dlp.exe',
        r'C:\known\yt-dlp.exe',
      ]);
    });

    test('빈 값은 건너뛴다', () {
      final ranked = ExternalToolLocator.rankCandidates(
        userPath: '   ',
        pathLookup: null,
        knownPaths: [r'C:\known\ffmpeg.exe', ''],
      );
      expect(ranked, [r'C:\known\ffmpeg.exe']);
    });

    test('중복은 순서를 유지하며 제거한다 (대소문자 무시)', () {
      final ranked = ExternalToolLocator.rankCandidates(
        userPath: r'C:\Tools\yt-dlp.exe',
        pathLookup: r'c:\tools\YT-DLP.EXE',
        knownPaths: [r'C:\Tools\yt-dlp.exe', r'C:\other\yt-dlp.exe'],
      );
      expect(ranked, [r'C:\Tools\yt-dlp.exe', r'C:\other\yt-dlp.exe']);
    });

    test('후보가 없으면 빈 목록', () {
      expect(ExternalToolLocator.rankCandidates(), isEmpty);
    });
  });
}
