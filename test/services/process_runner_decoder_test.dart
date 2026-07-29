import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/services/process/process_runner.dart';

// 외부 도구 출력 디코더.
//
// 회귀 대상: 데이터 폴더가 `C:\Users\...\OneDrive\문서\data`처럼 한글을 포함할 때
// 유튜브 가져오기가 통째로 실패하던 문제. yt-dlp는 stdout이 파이프면 로케일
// 코드페이지(여기선 cp949)로 인코딩하는데, 엄격한 utf8.decoder가 그 줄에서
// FormatException을 던지고 스트림이 끊겨 파이프가 안 비워졌다. 그러면 yt-dlp가
// stdout 쓰기에서 막히다 `[Errno 22] Invalid argument`로 죽는다.
void main() {
  // cp949로 인코딩된 `문서` — UTF-8로는 해석할 수 없는 바이트열.
  const hangulCp949 = [0xB9, 0xAE, 0xBC, 0xAD];

  List<int> destinationLineCp949() => [
    ...utf8.encode(r'[download] Destination: C:\Users\kuroi\OneDrive\'),
    ...hangulCp949,
    ...utf8.encode('\\data\\tmp\\audio.webm\n'),
  ];

  test('UTF-8이 아닌 바이트가 와도 던지지 않는다', () {
    expect(
      () => toolOutputDecoder.convert(destinationLineCp949()),
      returnsNormally,
    );
  });

  test('엄격한 디코더였다면 던졌을 입력이다', () {
    // 이 테스트가 깨지면 위 테스트가 아무것도 증명하지 않게 된다.
    expect(
      () => const Utf8Decoder().convert(destinationLineCp949()),
      throwsFormatException,
    );
  });

  test('파싱에 쓰는 ASCII 부분은 그대로 남는다', () {
    final decoded = toolOutputDecoder.convert(destinationLineCp949());
    expect(decoded, startsWith('[download] Destination: '));
    expect(decoded, contains(r'\data\tmp\audio.webm'));
  });

  test('깨진 바이트 뒤의 줄도 계속 읽힌다', () async {
    // 실제 실패는 "한 줄이 깨진다"가 아니라 "그 뒤로 스트림이 죽는다"였다.
    final chunks = Stream<List<int>>.fromIterable([
      destinationLineCp949(),
      utf8.encode('[download]  50.0% of 3.68MiB\n'),
      utf8.encode('ERROR: something went wrong\n'),
    ]);
    final lines = await chunks
        .transform(toolOutputDecoder)
        .transform(const LineSplitter())
        .toList();

    expect(lines, hasLength(3));
    expect(lines[1], contains('50.0%'));
    expect(lines[2], 'ERROR: something went wrong');
  });

  test('정상 UTF-8은 손상 없이 통과한다', () {
    final decoded = toolOutputDecoder.convert(
      utf8.encode('[youtube] 윤후 - 선물: Downloading webpage'),
    );
    expect(decoded, '[youtube] 윤후 - 선물: Downloading webpage');
  });
}
