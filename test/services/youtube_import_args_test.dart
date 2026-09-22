// file: test/services/youtube_import_args_test.dart
//
// 유튜브 오디오 내려받기 인자. 가져오기 형식은 「위치 보정본」과 짝이다 —
// 원본은 VBR(V0)로 보존하고, 재생의 seek 정확도는 WAV 사본이 맡는다.
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/services/youtube_import_service.dart';

void main() {
  group('buildYoutubeAudioArgs', () {
    test('🔴 원본은 MP3 VBR V0 그대로다 — CBR로 바꿔도 seek 오차가 남아 얻는 게 없다', () {
      final args = buildYoutubeAudioArgs(
        url: 'https://youtu.be/abc',
        outputTemplate: r'C:\tmp\job\audio.%(ext)s',
      );
      expect(args, [
        '-x',
        '--audio-format',
        'mp3',
        '--audio-quality',
        '0',
        '--no-playlist',
        '--newline',
        '-o',
        r'C:\tmp\job\audio.%(ext)s',
        'https://youtu.be/abc',
      ]);
    });

    test('ffmpeg 위치와 JS 런타임 인자는 있을 때만 끼우고, 주소는 언제나 맨 끝이다', () {
      final args = buildYoutubeAudioArgs(
        url: 'https://youtu.be/abc',
        outputTemplate: 'audio.%(ext)s',
        ffmpegPath: r'C:\ffmpeg\bin\ffmpeg.exe',
        jsRuntimeArgs: const ['--js-runtimes', r'node:C:\node\node.exe'],
      );
      expect(
        args,
        containsAllInOrder([
          '--ffmpeg-location',
          r'C:\ffmpeg\bin\ffmpeg.exe',
          '--js-runtimes',
          r'node:C:\node\node.exe',
          '-o',
          'audio.%(ext)s',
        ]),
      );
      expect(args.last, 'https://youtu.be/abc');
      expect(args[args.indexOf('--audio-quality') + 1], '0');
    });
  });
}
