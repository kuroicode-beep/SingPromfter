// file: lib/services/lyric_voice_monitor_service.dart
// RØDE 전용 가사 음성 출력을 Windows 네이티브 채널에 요청한다.
import 'package:flutter/services.dart';

class LyricVoiceMonitorService {
  static const MethodChannel _channel = MethodChannel(
    'singpromfter/lyric_voice_monitor',
  );

  Future<bool> get hasRodeOutput async =>
      await _channel.invokeMethod<bool>('hasRodeOutput') ?? false;

  Future<List<bool>> prepareLyrics(List<Map<String, String>> entries) async =>
      (await _channel.invokeListMethod<bool>('prepareLyrics', entries) ??
              const <bool>[])
          .toList(growable: false);

  Future<void> playFile(String path) =>
      _channel.invokeMethod<void>('playFile', {'path': path});

  Future<void> stop() => _channel.invokeMethod<void>('stop');
}
