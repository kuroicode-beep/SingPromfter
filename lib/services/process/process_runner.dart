// file: lib/services/process/process_runner.dart
//
// 외부 도구(yt-dlp·ffmpeg) 실행 계층.
//
// Process.run이 아니라 Process.start를 쓴다. 작업이 수십 초~수 분이고
// 두 도구 모두 진행률을 스트림으로 흘리며, 취소가 필요하기 때문이다.
// 추상 클래스로 둬서 테스트는 FakeProcessRunner를 주입한다(모킹 패키지 불필요).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 외부 도구 출력 디코더. **엄격한 utf8.decoder를 쓰면 안 된다.**
///
/// yt-dlp(파이썬)는 stdout이 파이프일 때 로케일 코드페이지로 인코딩한다.
/// 이 PC는 cp949라, 내려받기 대상 경로에 한글이 있으면
/// `[download] Destination: C:\...\OneDrive\문서\...` 줄이 cp949 바이트로 나온다.
/// 엄격한 UTF-8 디코더는 여기서 FormatException을 던지고, forEach가 끊기면서
/// **파이프를 더 이상 비우지 않는다.** 그러면 yt-dlp가 stdout 쓰기에서 막히다
/// `[Errno 22] Invalid argument`로 죽는다 — 실제로 한글 데이터 폴더에서
/// 가져오기가 통째로 실패하던 원인이 이것이었다.
///
/// 파싱이 필요한 값(진행률·`ERROR:` 접두사)은 전부 ASCII라, 깨진 바이트를
/// 대체 문자로 흘려보내도 동작에는 영향이 없다. 던지지 않는 것이 핵심이다.
const Utf8Decoder toolOutputDecoder = Utf8Decoder(allowMalformed: true);

/// 실행 중인 외부 프로세스 하나에 대한 핸들.
class JobHandle {
  /// stdout + stderr을 줄 단위로 합친 스트림.
  final Stream<String> lines;

  /// 종료 코드. 취소된 경우에도 완료된다.
  final Future<int> exitCode;

  final void Function() _cancel;
  final void Function(String data)? _writeStdin;

  JobHandle({
    required this.lines,
    required this.exitCode,
    required void Function() cancel,
    void Function(String data)? writeStdin,
  }) : _cancel = cancel,
       _writeStdin = writeStdin;

  void cancel() => _cancel();

  /// 프로세스 표준입력에 쓴다. ffmpeg에 'q'를 보내 우아하게 끝낼 때 쓴다.
  bool writeStdin(String data) {
    if (_writeStdin == null) return false;
    _writeStdin(data);
    return true;
  }
}

abstract class ProcessRunner {
  JobHandle start(String executable, List<String> arguments, {String? workingDirectory});

  /// 짧은 조회용(버전 확인 등). 표준 출력 전체를 문자열로 돌려준다.
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  });
}

class ProcessOutput {
  final int exitCode;
  final String stdout;
  final String stderr;

  const ProcessOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  bool get ok => exitCode == 0;
}

class SystemProcessRunner implements ProcessRunner {
  const SystemProcessRunner();

  @override
  JobHandle start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) {
    final controller = StreamController<String>.broadcast();
    final exitCompleter = Completer<int>();
    Process? process;
    var cancelled = false;

    Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      // URL·경로가 argv로 그대로 전달되므로 셸을 거치지 않는다(따옴표·주입 문제 회피).
      runInShell: false,
    ).then((started) {
      process = started;
      if (cancelled) {
        started.kill();
        return;
      }

      final stdoutDone = started.stdout
          .transform(toolOutputDecoder)
          .transform(const LineSplitter())
          .forEach(controller.add);
      final stderrDone = started.stderr
          .transform(toolOutputDecoder)
          .transform(const LineSplitter())
          .forEach(controller.add);

      Future.wait([
        stdoutDone.catchError((_) {}),
        stderrDone.catchError((_) {}),
      ]).whenComplete(() async {
        final code = await started.exitCode;
        if (!exitCompleter.isCompleted) exitCompleter.complete(code);
        await controller.close();
      });
    }).catchError((Object error) {
      controller.addError(error);
      if (!exitCompleter.isCompleted) exitCompleter.complete(-1);
      controller.close();
    });

    return JobHandle(
      lines: controller.stream,
      exitCode: exitCompleter.future,
      cancel: () {
        cancelled = true;
        process?.kill();
      },
      writeStdin: (data) {
        try {
          process?.stdin.write(data);
          process?.stdin.flush();
        } catch (_) {
          // 이미 끝난 프로세스면 무시한다.
        }
      },
    );
  }

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    try {
      final result = await Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        runInShell: false,
      );
      return ProcessOutput(
        exitCode: result.exitCode,
        stdout: result.stdout is String ? result.stdout as String : '',
        stderr: result.stderr is String ? result.stderr as String : '',
      );
    } catch (e) {
      return ProcessOutput(exitCode: -1, stdout: '', stderr: '$e');
    }
  }
}
