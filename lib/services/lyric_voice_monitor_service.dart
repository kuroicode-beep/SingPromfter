// file: lib/services/lyric_voice_monitor_service.dart
// RØDE 전용 가사 음성 출력을 Windows 네이티브 채널에 요청한다.
import 'package:flutter/services.dart';

class LyricVoiceMonitorService {
  static const MethodChannel _channel = MethodChannel(
    'singpromfter/lyric_voice_monitor',
  );

  Future<Map<Object?, Object?>> get rodeOutputStatus async {
    final status = await _channel.invokeMapMethod<Object?, Object?>(
      'hasRodeOutput',
    );
    return status ?? const <Object?, Object?>{};
  }

  Future<List<Map<Object?, Object?>>> prepareLyrics(
    List<Map<String, String>> entries,
  ) async {
    final results = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'prepareLyrics',
      entries,
    );
    return results?.toList(growable: false) ?? const <Map<Object?, Object?>>[];
  }

  Future<Map<Object?, Object?>> playFile(String path) async =>
      await _channel.invokeMapMethod<Object?, Object?>('playFile', {
        'path': path,
      }) ??
      const <Object?, Object?>{};

  Future<void> stop() => _channel.invokeMethod<void>('stop');

  Future<void> logEvent(String message) =>
      _channel.invokeMethod<void>('logEvent', {'message': message});
}
