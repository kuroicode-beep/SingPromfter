import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/services/process/external_tool_locator.dart';
import 'package:singpromfter_app/services/youtube_import_service.dart';

// yt-dlp 실패 안내의 원인별 분기.
//
// 예전엔 모든 실패에 "오래된 yt-dlp가 원인일 수 있어요"가 붙어, 유튜브가
// 일시적으로 막은 403에도 업데이트 안내가 나왔다. 원인별로 다음 행동이
// 다르다: 403은 기다리고, 해석 실패는 업데이트하고, 그 외는 실제 오류.
void main() {
  group('describeDownloadFailure', () {
    test('403은 재시도 안내 — 업데이트 안내를 붙이지 않는다', () {
      final msg = describeDownloadFailure(
        ['ERROR: unable to download video data: HTTP Error 403: Forbidden'],
        exitCode: 1,
        nodeFound: true,
      );
      expect(msg, contains('잠시 후 다시 시도'));
      expect(msg, isNot(contains('업데이트')));
    });

    test('403은 다른 영상 시도 팁을 준다 — 영상 단위 일시 차단 우회', () {
      final msg = describeDownloadFailure(
        ['ERROR: unable to download video data: HTTP Error 403: Forbidden'],
        exitCode: 1,
        nodeFound: true,
      );
      expect(msg, contains('다른 영상'));
    });

    test('403 + node 없음이면 설치 힌트를 함께 준다', () {
      final msg = describeDownloadFailure(
        ['ERROR: HTTP Error 403: Forbidden'],
        exitCode: 1,
        nodeFound: false,
      );
      expect(msg, contains('Node.js'));
      expect(msg, contains(ExternalTool.node.installHint));
    });

    test('해석 실패는 yt-dlp 업데이트 안내', () {
      final msg = describeDownloadFailure(
        ['ERROR: Unable to extract video data'],
        exitCode: 1,
        nodeFound: true,
      );
      expect(msg, contains('업데이트(-U)'));
    });

    test('그 외에는 실제 오류를 그대로 보여 준다', () {
      final msg = describeDownloadFailure(
        ['ERROR: [Errno 22] Invalid argument'],
        exitCode: 1,
        nodeFound: true,
      );
      expect(msg, contains('[Errno 22]'));
      expect(msg, isNot(contains('업데이트')));
    });

    test('오류 줄이 없으면 종료 코드라도 알린다', () {
      final msg = describeDownloadFailure(
        const [],
        exitCode: 255,
        nodeFound: true,
      );
      expect(msg, contains('255'));
    });
  });

  group('parseYtDlpEjsVersion', () {
    test('verbose 헤더의 Optional libraries 줄에서 버전을 찾는다', () {
      const header =
          '[debug] Optional libraries: brotli-1.2.0, certifi-2026.02.25, '
          'requests-2.34.2, sqlite3-3.50.4, urllib3-2.6.3, yt_dlp_ejs-0.8.0\n'
          '[debug] JS runtimes: node-24.13.1';
      expect(parseYtDlpEjsVersion(header), '0.8.0');
    });

    test('해석기가 없으면 null — 403 실패의 주원인 진단', () {
      const header =
          '[debug] Optional libraries: brotli-1.2.0, requests-2.34.2\n'
          '[debug] JS runtimes: node-24.13.1';
      expect(parseYtDlpEjsVersion(header), isNull);
    });

    test('빈 출력도 null', () {
      expect(parseYtDlpEjsVersion(''), isNull);
    });
  });

  group('ExternalTool.node', () {
    test('표준 설치 위치(Program Files\\nodejs)를 후보에 넣는다', () {
      final paths = ExternalToolLocator.knownPathsFor(
        ExternalTool.node,
        environment: {'ProgramFiles': r'C:\Program Files'},
      );
      // 실행 파일명은 플랫폼을 따른다 — CI(리눅스)에서는 확장자가 없다.
      final exe = Platform.isWindows ? 'node.exe' : 'node';
      expect(paths, contains('C:\\Program Files\\nodejs\\$exe'));
    });

    test('설치 안내 명령이 있다', () {
      expect(ExternalTool.node.installHint, contains('NodeJS'));
    });
  });
}
