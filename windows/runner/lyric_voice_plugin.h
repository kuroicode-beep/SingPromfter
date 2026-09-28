#ifndef RUNNER_LYRIC_VOICE_PLUGIN_H_
#define RUNNER_LYRIC_VOICE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <mmsystem.h>

#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

class LyricVoicePlugin {
 public:
  explicit LyricVoicePlugin(flutter::BinaryMessenger* messenger);
  ~LyricVoicePlugin();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  bool HasUniqueRodeOutput() const;
  bool PlayWaveFile(const std::wstring& path, std::string* error);
  void StopPlayback();

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  mutable std::mutex playback_mutex_;
  HWAVEOUT wave_out_ = nullptr;
  WAVEHDR wave_header_{};
  std::vector<char> wave_data_;
  std::vector<std::thread> workers_;
};

#endif  // RUNNER_LYRIC_VOICE_PLUGIN_H_
