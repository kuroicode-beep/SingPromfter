#include "lyric_voice_plugin.h"

#include <sapi.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <thread>

namespace {
constexpr char kChannelName[] = "singpromfter/lyric_voice_monitor";
std::mutex g_synthesis_mutex;

std::wstring Utf8ToWide(const std::string& text) {
  if (text.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                       text.c_str(), -1, nullptr, 0);
  if (size <= 0) return {};
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.c_str(), -1,
                      result.data(), size);
  result.pop_back();
  return result;
}

bool FindKoreanVoice(ISpObjectToken** voice) {
  ISpObjectTokenCategory* category = nullptr;
  if (FAILED(CoCreateInstance(CLSID_SpObjectTokenCategory, nullptr,
                              CLSCTX_ALL, IID_ISpObjectTokenCategory,
                              reinterpret_cast<void**>(&category)))) return false;
  if (FAILED(category->SetId(SPCAT_VOICES, FALSE))) {
    category->Release();
    return false;
  }
  IEnumSpObjectTokens* tokens = nullptr;
  if (FAILED(category->EnumTokens(nullptr, nullptr, &tokens))) {
    category->Release();
    return false;
  }
  category->Release();
  ULONG count = 0;
  tokens->GetCount(&count);
  bool found = false;
  for (ULONG i = 0; i < count && !found; ++i) {
    ISpObjectToken* token = nullptr;
    if (FAILED(tokens->Next(1, &token, nullptr)) || !token) continue;
    WCHAR* language = nullptr;
    WCHAR* token_id = nullptr;
    const bool korean_language =
        SUCCEEDED(token->GetStringValue(L"Language", &language)) && language &&
        (wcsstr(language, L"412") != nullptr || wcsstr(language, L"0412") != nullptr);
    const bool korean_name =
        SUCCEEDED(token->GetId(&token_id)) && token_id &&
        (wcsstr(token_id, L"ko-KR") != nullptr || wcsstr(token_id, L"Heami") != nullptr);
    if (korean_language && korean_name) {
      *voice = token;
      token = nullptr;
      found = true;
    }
    CoTaskMemFree(language);
    CoTaskMemFree(token_id);
    if (token) token->Release();
  }
  tokens->Release();
  return found;
}

bool SynthesizeKorean(const std::wstring& text, const std::wstring& path) {
  const HRESULT com_result = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(com_result) && com_result != RPC_E_CHANGED_MODE) return false;
  bool success = false;
  ISpObjectToken* voice_token = nullptr;
  ISpVoice* voice = nullptr;
  ISpStream* stream = nullptr;
  if (!FindKoreanVoice(&voice_token) ||
      FAILED(CoCreateInstance(CLSID_SpVoice, nullptr, CLSCTX_ALL,
                              IID_ISpVoice, reinterpret_cast<void**>(&voice))) ||
      FAILED(voice->SetVoice(voice_token)) ||
      FAILED(CoCreateInstance(CLSID_SpFileStream, nullptr, CLSCTX_ALL,
                              IID_ISpStream, reinterpret_cast<void**>(&stream)))) {
    if (stream) stream->Release();
    if (voice) voice->Release();
    if (voice_token) voice_token->Release();
    if (SUCCEEDED(com_result)) CoUninitialize();
    return false;
  }
  WAVEFORMATEX format{};
  format.wFormatTag = WAVE_FORMAT_PCM;
  format.nChannels = 1;
  format.nSamplesPerSec = 22050;
  format.wBitsPerSample = 16;
  format.nBlockAlign = format.nChannels * format.wBitsPerSample / 8;
  format.nAvgBytesPerSec = format.nSamplesPerSec * format.nBlockAlign;
  if (SUCCEEDED(stream->BindToFile(path.c_str(), SPFM_CREATE_ALWAYS,
                                   &SPDFID_WaveFormatEx, &format, 0)) &&
      SUCCEEDED(voice->SetOutput(stream, FALSE)) &&
      SUCCEEDED(voice->Speak(text.c_str(), SPF_DEFAULT, nullptr)) &&
      SUCCEEDED(stream->Close())) {
    success = true;
  }
  stream->Release();
  voice->Release();
  voice_token->Release();
  if (SUCCEEDED(com_result)) CoUninitialize();
  return success;
}

uint32_t ReadU32(const char* data) {
  return static_cast<uint8_t>(data[0]) |
         (static_cast<uint32_t>(static_cast<uint8_t>(data[1])) << 8) |
         (static_cast<uint32_t>(static_cast<uint8_t>(data[2])) << 16) |
         (static_cast<uint32_t>(static_cast<uint8_t>(data[3])) << 24);
}
uint16_t ReadU16(const char* data) {
  return static_cast<uint8_t>(data[0]) |
         (static_cast<uint16_t>(static_cast<uint8_t>(data[1])) << 8);
}

bool IsUsableWaveFile(const std::wstring& path) {
  std::ifstream file(path, std::ios::binary);
  char header[12]{};
  file.read(header, sizeof(header));
  if (file.gcount() != sizeof(header) || std::string(header, 4) != "RIFF" ||
      std::string(header + 8, 4) != "WAVE") return false;
  bool has_format = false;
  bool has_audio = false;
  while (file && !file.eof()) {
    char chunk[8]{};
    file.read(chunk, sizeof(chunk));
    if (file.gcount() != sizeof(chunk)) break;
    const uint32_t size = ReadU32(chunk + 4);
    if (std::string(chunk, 4) == "fmt " && size >= 16 && size < 4096) {
      char fmt[16]{};
      file.read(fmt, sizeof(fmt));
      if (!file || ReadU16(fmt) != WAVE_FORMAT_PCM) return false;
      has_format = true;
      if (size > sizeof(fmt)) file.seekg(size - sizeof(fmt), std::ios::cur);
    } else if (std::string(chunk, 4) == "data" && size > 0) {
      has_audio = true;
      break;
    } else {
      file.seekg(size, std::ios::cur);
    }
    if (size & 1) file.seekg(1, std::ios::cur);
  }
  return has_format && has_audio;
}
}  // namespace

LyricVoicePlugin::LyricVoicePlugin(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}

LyricVoicePlugin::~LyricVoicePlugin() {
  if (channel_) channel_->SetMethodCallHandler(nullptr);
  for (auto& worker : workers_) if (worker.joinable()) worker.join();
  StopPlayback();
}

bool LyricVoicePlugin::HasUniqueRodeOutput() const {
  UINT matches = 0;
  const UINT count = waveOutGetNumDevs();
  for (UINT i = 0; i < count; ++i) {
    WAVEOUTCAPSW caps{};
    if (waveOutGetDevCapsW(i, &caps, sizeof(caps)) != MMSYSERR_NOERROR) continue;
    const std::wstring name(caps.szPname);
    if (name.find(L"RØDE") != std::wstring::npos &&
        name.find(L"NT-USB") != std::wstring::npos) ++matches;
  }
  return matches == 1;
}

bool LyricVoicePlugin::PlayWaveFile(const std::wstring& path,
                                    std::string* error) {
  std::lock_guard<std::mutex> lock(playback_mutex_);
  if (wave_out_) {
    waveOutReset(wave_out_);
    waveOutUnprepareHeader(wave_out_, &wave_header_, sizeof(wave_header_));
    waveOutClose(wave_out_);
    wave_out_ = nullptr;
  }
  wave_data_.clear();
  std::ifstream file(path, std::ios::binary);
  if (!file) { *error = "가사 음성 파일을 열 수 없어요."; return false; }
  char riff[12]{};
  file.read(riff, sizeof(riff));
  if (file.gcount() != sizeof(riff) || std::string(riff, 4) != "RIFF" ||
      std::string(riff + 8, 4) != "WAVE") {
    *error = "가사 음성 파일 형식이 올바르지 않아요."; return false;
  }
  WAVEFORMATEX format{};
  bool have_format = false;
  while (file && !file.eof()) {
    char chunk[8]{};
    file.read(chunk, sizeof(chunk));
    if (file.gcount() != sizeof(chunk)) break;
    const uint32_t size = ReadU32(chunk + 4);
    if (std::string(chunk, 4) == "fmt " && size >= 16 && size < 4096) {
      std::vector<char> fmt(size);
      file.read(fmt.data(), size);
      if (!file) break;
      std::memcpy(&format, fmt.data(), std::min<size_t>(sizeof(format), 16));
      have_format = format.wFormatTag == WAVE_FORMAT_PCM;
      if (size & 1) file.seekg(1, std::ios::cur);
    } else if (std::string(chunk, 4) == "data" && size > 0) {
      wave_data_.resize(size);
      file.read(wave_data_.data(), size);
      break;
    } else {
      file.seekg(size + (size & 1), std::ios::cur);
    }
  }
  if (!have_format || wave_data_.empty()) {
    *error = "재생할 수 있는 PCM 음성이 아니에요."; return false;
  }
  UINT device = WAVE_MAPPER;
  UINT matches = 0;
  for (UINT i = 0; i < waveOutGetNumDevs(); ++i) {
    WAVEOUTCAPSW caps{};
    if (waveOutGetDevCapsW(i, &caps, sizeof(caps)) != MMSYSERR_NOERROR) continue;
    const std::wstring name(caps.szPname);
    if (name.find(L"RØDE") != std::wstring::npos &&
        name.find(L"NT-USB") != std::wstring::npos) { device = i; ++matches; }
  }
  if (matches != 1) { *error = "RØDE 헤드폰 출력을 하나로 확인할 수 없어요."; return false; }
  if (waveOutOpen(&wave_out_, device, &format, 0, 0, CALLBACK_NULL) != MMSYSERR_NOERROR) {
    wave_out_ = nullptr;
    *error = "RØDE 헤드폰 출력 장치를 열 수 없어요."; return false;
  }
  wave_header_ = {};
  wave_header_.lpData = wave_data_.data();
  wave_header_.dwBufferLength = static_cast<DWORD>(wave_data_.size());
  if (waveOutPrepareHeader(wave_out_, &wave_header_, sizeof(wave_header_)) != MMSYSERR_NOERROR ||
      waveOutWrite(wave_out_, &wave_header_, sizeof(wave_header_)) != MMSYSERR_NOERROR) {
    waveOutReset(wave_out_);
    waveOutClose(wave_out_);
    wave_out_ = nullptr;
    *error = "RØDE 헤드폰으로 가사 음성을 보낼 수 없어요."; return false;
  }
  return true;
}

void LyricVoicePlugin::StopPlayback() {
  std::lock_guard<std::mutex> lock(playback_mutex_);
  if (!wave_out_) return;
  waveOutReset(wave_out_);
  waveOutUnprepareHeader(wave_out_, &wave_header_, sizeof(wave_header_));
  waveOutClose(wave_out_);
  wave_out_ = nullptr;
  wave_data_.clear();
}

void LyricVoicePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "hasRodeOutput") {
    result->Success(flutter::EncodableValue(HasUniqueRodeOutput()));
    return;
  }
  if (call.method_name() == "stop") { StopPlayback(); result->Success(); return; }
  if (call.method_name() == "playFile") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) { result->Error("invalid_args", "파일 경로가 없어요."); return; }
    const auto it = args->find(flutter::EncodableValue("path"));
    const auto* path = it == args->end() ? nullptr : std::get_if<std::string>(&it->second);
    if (!path) { result->Error("invalid_args", "파일 경로가 없어요."); return; }
    std::string error;
    if (PlayWaveFile(Utf8ToWide(*path), &error)) result->Success();
    else result->Error("play_failed", error);
    return;
  }
  if (call.method_name() == "prepareLyrics") {
    const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
    if (!args) { result->Error("invalid_args", "가사 음성 목록이 올바르지 않아요."); return; }
    struct Entry { std::wstring text; std::wstring path; };
    std::vector<Entry> entries;
    for (const auto& value : *args) {
      const auto* map = std::get_if<flutter::EncodableMap>(&value);
      if (!map) continue;
      const auto text_it = map->find(flutter::EncodableValue("text"));
      const auto path_it = map->find(flutter::EncodableValue("path"));
      if (text_it == map->end() || path_it == map->end()) continue;
      const auto* text = std::get_if<std::string>(&text_it->second);
      const auto* path = std::get_if<std::string>(&path_it->second);
      if (!text || !path || text->empty() || path->empty()) continue;
      entries.push_back({Utf8ToWide(*text), Utf8ToWide(*path)});
    }
    workers_.emplace_back([entries = std::move(entries), result = std::move(result)]() mutable {
      const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
      flutter::EncodableList done;
      for (const auto& entry : entries) {
        std::error_code ec;
        bool ready = std::filesystem::exists(entry.path, ec) &&
                     std::filesystem::file_size(entry.path, ec) > 44 &&
                     IsUsableWaveFile(entry.path);
        if (!ready) {
          std::filesystem::create_directories(std::filesystem::path(entry.path).parent_path(), ec);
          std::lock_guard<std::mutex> synthesis_lock(g_synthesis_mutex);
          ready = SynthesizeKorean(entry.text, entry.path);
        }
        done.emplace_back(ready);
      }
      if (SUCCEEDED(com)) CoUninitialize();
      result->Success(flutter::EncodableValue(std::move(done)));
    });
    return;
  }
  result->NotImplemented();
}
