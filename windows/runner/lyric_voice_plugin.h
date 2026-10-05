#ifndef RUNNER_LYRIC_VOICE_PLUGIN_H_
#define RUNNER_LYRIC_VOICE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <atomic>
#include <memory>
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
  bool FindRodeOutput(std::wstring* device_name, std::string* error) const;
  bool PlayWaveFile(const std::wstring& path,
                    const std::atomic<bool>& cancelled,
                    bool* was_cancelled,
                    std::wstring* device_name,
                    std::string* error);
  void StopPlayback();

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::atomic<bool> playback_cancelled_{false};
  std::thread playback_worker_;
  std::vector<std::thread> workers_;
};

#endif  // RUNNER_LYRIC_VOICE_PLUGIN_H_
