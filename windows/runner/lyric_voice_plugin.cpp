#include "lyric_voice_plugin.h"

#include <audioclient.h>
#include <audiopolicy.h>
#include <endpointvolume.h>
#include <mmdeviceapi.h>
#include <functiondiscoverykeys_devpkey.h>
#include <sapi.h>
#include <propvarutil.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <mutex>
#include <sstream>
#include <thread>
#include <cwctype>
#include <ctime>

namespace {
constexpr char kChannelName[] = "singpromfter/lyric_voice_monitor";
std::mutex g_synthesis_mutex;
std::mutex g_log_mutex;

void LogLyricVoiceEvent(const std::string& message) {
  char* local_app_data = nullptr;
  size_t local_app_data_size = 0;
  if (_dupenv_s(&local_app_data, &local_app_data_size, "LOCALAPPDATA") != 0 ||
      !local_app_data || !*local_app_data) {
    free(local_app_data);
    return;
  }
  const std::filesystem::path app_data_path(local_app_data);
  free(local_app_data);
  std::lock_guard<std::mutex> lock(g_log_mutex);
  const auto log_path = app_data_path / "SingPromfter" / "logs" /
                        "lyric_voice_monitor.log";
  std::error_code ec;
  std::filesystem::create_directories(log_path.parent_path(), ec);
  if (ec) return;
  std::ofstream log(log_path, std::ios::binary | std::ios::app);
  if (!log) return;
  const auto now = std::chrono::system_clock::to_time_t(
      std::chrono::system_clock::now());
  std::tm local_time{};
  localtime_s(&local_time, &now);
  log << std::put_time(&local_time, "%Y-%m-%d %H:%M:%S") << " "
      << message << "\n";
}

std::string HResultMessage(const char* action, HRESULT code) {
  std::ostringstream message;
  message << action << " (HRESULT 0x" << std::hex << std::uppercase
          << static_cast<unsigned long>(code) << ").";
  return message.str();
}

bool ContainsIgnoringCase(const std::wstring& value,
                          const std::wstring& needle) {
  std::wstring folded_value(value);
  std::wstring folded_needle(needle);
  std::transform(folded_value.begin(), folded_value.end(), folded_value.begin(),
                 [](wchar_t ch) { return static_cast<wchar_t>(towlower(ch)); });
  std::transform(folded_needle.begin(), folded_needle.end(), folded_needle.begin(),
                 [](wchar_t ch) { return static_cast<wchar_t>(towlower(ch)); });
  return folded_value.find(folded_needle) != std::wstring::npos;
}

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

std::string WideToUtf8(const std::wstring& text) {
  if (text.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
                                       text.c_str(), -1, nullptr, 0, nullptr, nullptr);
  if (size <= 0) return {};
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.c_str(), -1,
                      result.data(), size, nullptr, nullptr);
  result.pop_back();
  return result;
}

std::string DeviceId(IMMDevice* device) {
  LPWSTR id = nullptr;
  if (!device || FAILED(device->GetId(&id)) || !id) return "unknown";
  const std::string result = WideToUtf8(id);
  CoTaskMemFree(id);
  return result;
}

void LogEndpointState(IMMDevice* device, IAudioClient* client) {
  std::ostringstream state;
  state << "audio-endpoint id=" << DeviceId(device);
  IAudioEndpointVolume* endpoint_volume = nullptr;
  HRESULT hr = device->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_ALL,
                                nullptr, reinterpret_cast<void**>(&endpoint_volume));
  if (SUCCEEDED(hr) && endpoint_volume) {
    float scalar = 0.0f;
    BOOL muted = FALSE;
    const HRESULT volume_hr = endpoint_volume->GetMasterVolumeLevelScalar(&scalar);
    const HRESULT mute_hr = endpoint_volume->GetMute(&muted);
    state << " endpointVolume=";
    if (SUCCEEDED(volume_hr)) state << scalar;
    else state << "error";
    state << " endpointMute=";
    if (SUCCEEDED(mute_hr)) state << (muted ? "true" : "false");
    else state << "error";
    endpoint_volume->Release();
  } else {
    state << " endpointVolume=unavailable";
  }
  LogLyricVoiceEvent(state.str());

  IAudioSessionManager2* manager = nullptr;
  hr = device->Activate(__uuidof(IAudioSessionManager2), CLSCTX_ALL, nullptr,
                        reinterpret_cast<void**>(&manager));
  if (FAILED(hr) || !manager) {
    LogLyricVoiceEvent("audio-session-manager unavailable " + HResultMessage("Activate", hr));
    return;
  }
  IAudioSessionEnumerator* sessions = nullptr;
  hr = manager->GetSessionEnumerator(&sessions);
  if (FAILED(hr) || !sessions) {
    LogLyricVoiceEvent("audio-session-enumeration failed " + HResultMessage("GetSessionEnumerator", hr));
    manager->Release();
    return;
  }
  int count = 0;
  sessions->GetCount(&count);
  const DWORD current_pid = GetCurrentProcessId();
  bool found_current = false;
  for (int i = 0; i < count; ++i) {
    IAudioSessionControl* control = nullptr;
    if (FAILED(sessions->GetSession(i, &control)) || !control) continue;
    IAudioSessionControl2* control2 = nullptr;
    if (SUCCEEDED(control->QueryInterface(IID_PPV_ARGS(&control2))) && control2) {
      DWORD process_id = 0;
      if (SUCCEEDED(control2->GetProcessId(&process_id)) && process_id == current_pid) {
        ISimpleAudioVolume* volume = nullptr;
        if (SUCCEEDED(control->QueryInterface(IID_PPV_ARGS(&volume))) && volume) {
          float scalar = 0.0f;
          BOOL muted = FALSE;
          const HRESULT volume_hr = volume->GetMasterVolume(&scalar);
          const HRESULT mute_hr = volume->GetMute(&muted);
          std::ostringstream session;
          session << "audio-session pid=" << process_id << " count=" << count
                  << " volume=";
          if (SUCCEEDED(volume_hr)) session << scalar;
          else session << "error";
          session << " mute=";
          if (SUCCEEDED(mute_hr)) session << (muted ? "true" : "false");
          else session << "error";
          LogLyricVoiceEvent(session.str());
          volume->Release();
          found_current = true;
        }
      }
      control2->Release();
    }
    control->Release();
  }
  if (!found_current) {
    LogLyricVoiceEvent("audio-session current-process-not-found pid=" +
                       std::to_string(current_pid) + " count=" + std::to_string(count));
  }
  sessions->Release();
  manager->Release();
  (void)client;
}

bool FindKoreanVoice(ISpObjectToken** voice, std::string* error) {
  ISpObjectTokenCategory* category = nullptr;
  HRESULT hr = CoCreateInstance(CLSID_SpObjectTokenCategory, nullptr,
                                CLSCTX_ALL, IID_ISpObjectTokenCategory,
                                reinterpret_cast<void**>(&category));
  if (FAILED(hr)) {
    *error = HResultMessage("SAPI 음성 목록을 열지 못했어요", hr);
    return false;
  }
  hr = category->SetId(SPCAT_VOICES, FALSE);
  if (FAILED(hr)) {
    category->Release();
    *error = HResultMessage("SAPI 음성 목록을 선택하지 못했어요", hr);
    return false;
  }
  IEnumSpObjectTokens* tokens = nullptr;
  hr = category->EnumTokens(nullptr, nullptr, &tokens);
  if (FAILED(hr)) {
    category->Release();
    *error = HResultMessage("SAPI 음성 목록을 읽지 못했어요", hr);
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
    WCHAR* attribute_language = nullptr;
    WCHAR* token_id = nullptr;
    token->GetStringValue(L"Language", &language);
    ISpDataKey* attributes = nullptr;
    if (SUCCEEDED(token->OpenKey(L"Attributes", &attributes)) && attributes) {
      attributes->GetStringValue(L"Language", &attribute_language);
      attributes->Release();
    }
    token->GetId(&token_id);
    const std::wstring locale = language ? language : L"";
    const std::wstring attribute_locale =
        attribute_language ? attribute_language : L"";
    const std::wstring id = token_id ? token_id : L"";
    const bool korean_language = ContainsIgnoringCase(locale, L"412") ||
                                 ContainsIgnoringCase(locale, L"0412") ||
                                 ContainsIgnoringCase(attribute_locale, L"412") ||
                                 ContainsIgnoringCase(attribute_locale, L"0412");
    const bool korean_name = ContainsIgnoringCase(id, L"ko-KR") ||
                             ContainsIgnoringCase(id, L"Heami");
    if (korean_language && korean_name) {
      *voice = token;
      token = nullptr;
      found = true;
    }
    CoTaskMemFree(language);
    CoTaskMemFree(attribute_language);
    CoTaskMemFree(token_id);
    if (token) token->Release();
  }
  tokens->Release();
  if (!found) *error = "한국어 SAPI 음성(한국어 412)을 찾지 못했어요.";
  return found;
}

bool SynthesizeKorean(const std::wstring& text, const std::wstring& path,
                      std::string* error) {
  const HRESULT com_result = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(com_result) && com_result != RPC_E_CHANGED_MODE) {
    *error = HResultMessage("한국어 음성 합성 초기화에 실패했어요", com_result);
    return false;
  }
  ISpObjectToken* voice_token = nullptr;
  ISpVoice* voice = nullptr;
  ISpStream* stream = nullptr;
  HRESULT hr = S_OK;
  bool success = FindKoreanVoice(&voice_token, error);
  if (success) {
    hr = CoCreateInstance(CLSID_SpVoice, nullptr, CLSCTX_ALL, IID_ISpVoice,
                          reinterpret_cast<void**>(&voice));
    success = SUCCEEDED(hr);
    if (!success) *error = HResultMessage("SAPI 음성 엔진을 만들지 못했어요", hr);
  }
  if (success) {
    hr = voice->SetVoice(voice_token);
    success = SUCCEEDED(hr);
    if (!success) *error = HResultMessage("한국어 SAPI 음성을 선택하지 못했어요", hr);
  }
  if (success) {
    hr = CoCreateInstance(CLSID_SpFileStream, nullptr, CLSCTX_ALL, IID_ISpStream,
                          reinterpret_cast<void**>(&stream));
    success = SUCCEEDED(hr);
    if (!success) *error = HResultMessage("SAPI WAV 파일 스트림을 만들지 못했어요", hr);
  }
  WAVEFORMATEX format{};
  format.wFormatTag = WAVE_FORMAT_PCM;
  format.nChannels = 1;
  format.nSamplesPerSec = 22050;
  format.wBitsPerSample = 16;
  format.nBlockAlign = format.nChannels * format.wBitsPerSample / 8;
  format.nAvgBytesPerSec = format.nSamplesPerSec * format.nBlockAlign;
  if (success) {
    hr = stream->BindToFile(path.c_str(), SPFM_CREATE_ALWAYS,
                            &SPDFID_WaveFormatEx, &format, 0);
    success = SUCCEEDED(hr);
    if (!success) *error = HResultMessage("가사 음성 WAV 파일을 열지 못했어요", hr);
  }
  if (success) {
    hr = voice->SetOutput(stream, FALSE);
    success = SUCCEEDED(hr);
    if (!success) *error = HResultMessage("한국어 음성 출력을 설정하지 못했어요", hr);
  }
  if (success) {
    hr = voice->Speak(text.c_str(), SPF_DEFAULT, nullptr);
    success = SUCCEEDED(hr);
    if (!success) *error = HResultMessage("한국어 가사를 합성하지 못했어요", hr);
  }
  if (success) {
    hr = stream->Close();
    success = SUCCEEDED(hr);
    if (!success) *error = HResultMessage("가사 음성 WAV 파일을 닫지 못했어요", hr);
  }
  if (stream) stream->Release();
  if (voice) voice->Release();
  if (voice_token) voice_token->Release();
  if (SUCCEEDED(com_result)) CoUninitialize();
  if (!success) {
    std::error_code ec;
    std::filesystem::remove(path, ec);
  }
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
  std::error_code ec;
  const uint64_t file_size = std::filesystem::file_size(path, ec);
  if (ec || file_size < 44 || file_size > 64 * 1024 * 1024) return false;
  std::ifstream file(path, std::ios::binary);
  char header[12]{};
  file.read(header, sizeof(header));
  if (file.gcount() != sizeof(header) || std::string(header, 4) != "RIFF" ||
      std::string(header + 8, 4) != "WAVE") return false;
  const uint64_t riff_end = static_cast<uint64_t>(ReadU32(header + 4)) + 8;
  if (riff_end < sizeof(header) || riff_end > file_size) return false;
  bool has_format = false;
  bool has_audio = false;
  uint64_t position = sizeof(header);
  while (position + 8 <= riff_end) {
    char chunk[8]{};
    file.read(chunk, sizeof(chunk));
    if (file.gcount() != sizeof(chunk)) return false;
    const uint32_t size = ReadU32(chunk + 4);
    const uint64_t payload_end = position + 8 + size;
    if (payload_end > riff_end) return false;
    if (std::string(chunk, 4) == "fmt " && size >= 16 && size < 4096) {
      char fmt[16]{};
      file.read(fmt, sizeof(fmt));
      if (file.gcount() != sizeof(fmt) || ReadU16(fmt) != WAVE_FORMAT_PCM ||
          ReadU16(fmt + 2) != 1 || ReadU32(fmt + 4) != 22050 ||
          ReadU16(fmt + 12) != 2 || ReadU16(fmt + 14) != 16) return false;
      has_format = true;
      if (size > sizeof(fmt)) file.seekg(size - sizeof(fmt), std::ios::cur);
    } else if (std::string(chunk, 4) == "data" && size > 0) {
      has_audio = (size % 2) == 0;
      file.seekg(size, std::ios::cur);
    } else {
      file.seekg(size, std::ios::cur);
    }
    if (size & 1) file.seekg(1, std::ios::cur);
    if (!file) return false;
    position = payload_end + (size & 1);
  }
  return has_format && has_audio;
}

bool ContainsRodeUsbName(const std::wstring& name) {
  std::wstring folded(name);
  std::transform(folded.begin(), folded.end(), folded.begin(),
                 [](wchar_t ch) { return static_cast<wchar_t>(towlower(ch)); });
  return (folded.find(L"r\u00f8de") != std::wstring::npos ||
          folded.find(L"rode") != std::wstring::npos) &&
         folded.find(L"nt-usb") != std::wstring::npos;
}

bool EnumerateRodeOutput(IMMDevice** selected, std::wstring* selected_name,
                        std::string* error) {
  *selected = nullptr;
  IMMDeviceEnumerator* enumerator = nullptr;
  HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                CLSCTX_ALL, IID_PPV_ARGS(&enumerator));
  if (FAILED(hr)) {
    *error = HResultMessage("Windows 오디오 엔드포인트 목록을 읽지 못했어요", hr);
    return false;
  }
  IMMDeviceCollection* devices = nullptr;
  hr = enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &devices);
  enumerator->Release();
  if (FAILED(hr)) {
    *error = HResultMessage("활성 출력 장치를 조회하지 못했어요", hr);
    return false;
  }

  UINT count = 0;
  devices->GetCount(&count);
  UINT matches = 0;
  for (UINT i = 0; i < count; ++i) {
    IMMDevice* device = nullptr;
    if (FAILED(devices->Item(i, &device)) || !device) continue;
    IPropertyStore* properties = nullptr;
    std::wstring name;
    if (SUCCEEDED(device->OpenPropertyStore(STGM_READ, &properties)) && properties) {
      PROPVARIANT value;
      PropVariantInit(&value);
      if (SUCCEEDED(properties->GetValue(PKEY_Device_FriendlyName, &value)) &&
          value.vt == VT_LPWSTR && value.pwszVal) {
        name = value.pwszVal;
      }
      PropVariantClear(&value);
      properties->Release();
    }
    if (ContainsRodeUsbName(name)) {
      ++matches;
      if (matches == 1) {
        *selected = device;
        *selected_name = name;
        device = nullptr;
      }
    }
    if (device) device->Release();
  }
  devices->Release();
  if (matches == 1) return true;
  if (*selected) {
    (*selected)->Release();
    *selected = nullptr;
  }
  *error = matches == 0
      ? "활성화된 RØDE NT-USB 출력 장치를 찾지 못했어요."
      : "RØDE NT-USB 출력 장치가 둘 이상이라 하나를 고를 수 없어요.";
  return false;
}

bool ProbeRodeOutput(IMMDevice* device, std::string* error) {
  IAudioClient* client = nullptr;
  HRESULT hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                reinterpret_cast<void**>(&client));
  if (FAILED(hr)) {
    *error = HResultMessage("RØDE 출력 엔드포인트를 열지 못했어요", hr);
    return false;
  }

  WAVEFORMATEX format{};
  format.wFormatTag = WAVE_FORMAT_PCM;
  format.nChannels = 1;
  format.nSamplesPerSec = 22050;
  format.wBitsPerSample = 16;
  format.nBlockAlign = format.nChannels * format.wBitsPerSample / 8;
  format.nAvgBytesPerSec = format.nSamplesPerSec * format.nBlockAlign;
  hr = client->Initialize(AUDCLNT_SHAREMODE_SHARED,
                          AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM |
                              AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
                          10000000, 0, &format, nullptr);
  IAudioRenderClient* render = nullptr;
  if (SUCCEEDED(hr)) {
    hr = client->GetService(__uuidof(IAudioRenderClient),
                            reinterpret_cast<void**>(&render));
  }
  if (SUCCEEDED(hr)) hr = client->Start();
  if (SUCCEEDED(hr)) {
    BYTE* buffer = nullptr;
    hr = render->GetBuffer(1, &buffer);
    if (SUCCEEDED(hr)) hr = render->ReleaseBuffer(1, AUDCLNT_BUFFERFLAGS_SILENT);
  }
  if (client) {
    const HRESULT stop_result = client->Stop();
    if (SUCCEEDED(hr) && FAILED(stop_result)) hr = stop_result;
  }
  if (render) render->Release();
  client->Release();
  if (FAILED(hr)) {
    *error = HResultMessage("RØDE 무음 오디오 경로를 확인하지 못했어요", hr);
    LogLyricVoiceEvent("silent-probe initialize-or-buffer failed " + *error);
    return false;
  }
  LogLyricVoiceEvent("silent-probe initialized endpoint=" + DeviceId(device));
  return true;
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

bool LyricVoicePlugin::FindRodeOutput(std::wstring* device_name,
                                      std::string* error) const {
  const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(com) && com != RPC_E_CHANGED_MODE) {
    *error = HResultMessage("Windows 오디오 초기화에 실패했어요", com);
    return false;
  }
  IMMDevice* device = nullptr;
  const bool found = EnumerateRodeOutput(&device, device_name, error);
  bool usable = found;
  if (found) {
    usable = ProbeRodeOutput(device, error);
    device->Release();
  }
  if (SUCCEEDED(com)) CoUninitialize();
  LogLyricVoiceEvent(usable
      ? "silent-output-probe=ok device=" + WideToUtf8(*device_name)
      : "silent-output-probe=failed error=" + *error);
  return usable;
}

bool LyricVoicePlugin::PlayWaveFile(const std::wstring& path,
                                    const std::atomic<bool>& cancelled,
                                    bool* was_cancelled,
                                    std::wstring* device_name,
                                    std::string* error) {
  *was_cancelled = false;
  LogLyricVoiceEvent("playback-open path=" + WideToUtf8(std::filesystem::path(path).filename().wstring()));
  const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(com) && com != RPC_E_CHANGED_MODE) {
    *error = HResultMessage("Windows 오디오 초기화에 실패했어요", com);
    return false;
  }
  std::ifstream file(path, std::ios::binary);
  if (!file) {
    *error = "가사 음성 파일을 열 수 없어요.";
    if (SUCCEEDED(com)) CoUninitialize();
    return false;
  }
  char riff[12]{};
  file.read(riff, sizeof(riff));
  if (file.gcount() != sizeof(riff) || std::string(riff, 4) != "RIFF" ||
      std::string(riff + 8, 4) != "WAVE") {
    *error = "가사 음성 파일 형식이 올바르지 않아요.";
    if (SUCCEEDED(com)) CoUninitialize();
    return false;
  }
  WAVEFORMATEX format{};
  std::vector<char> wave_data;
  bool have_format = false;
  bool complete_data = false;
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
      have_format = format.wFormatTag == WAVE_FORMAT_PCM &&
                    format.nChannels > 0 && format.nSamplesPerSec > 0 &&
                    format.nBlockAlign > 0 && format.wBitsPerSample == 16;
      if (size & 1) file.seekg(1, std::ios::cur);
    } else if (std::string(chunk, 4) == "data" && size > 0) {
      if (size > 64 * 1024 * 1024) break;
      wave_data.resize(size);
      file.read(wave_data.data(), size);
      complete_data = file.gcount() == static_cast<std::streamsize>(size);
      break;
    } else {
      file.seekg(size + (size & 1), std::ios::cur);
    }
  }
  if (!have_format || !complete_data || wave_data.empty() ||
      wave_data.size() % format.nBlockAlign != 0) {
    *error = "재생할 수 있는 16비트 PCM 음성이 아니에요.";
    LogLyricVoiceEvent("playback-wave-invalid error=" + *error);
    if (SUCCEEDED(com)) CoUninitialize();
    return false;
  }
  IMMDevice* device = nullptr;
  if (!EnumerateRodeOutput(&device, device_name, error)) {
    LogLyricVoiceEvent("playback-route-failed error=" + *error);
    if (SUCCEEDED(com)) CoUninitialize();
    return false;
  }
  const std::string device_id = DeviceId(device);
  LogLyricVoiceEvent("playback-route name=" + WideToUtf8(*device_name) +
                     " id=" + device_id + " sourceRate=" +
                     std::to_string(format.nSamplesPerSec) + " channels=" +
                     std::to_string(format.nChannels) + " bits=" +
                     std::to_string(format.wBitsPerSample) + " bytes=" +
                     std::to_string(wave_data.size()));
  IAudioClient* client = nullptr;
  HRESULT hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                reinterpret_cast<void**>(&client));
  if (FAILED(hr)) {
    *error = HResultMessage("RØDE 출력 엔드포인트를 열지 못했어요", hr);
    LogLyricVoiceEvent("playback-activate-failed endpoint=" + device_id + " " + *error);
    device->Release();
    if (SUCCEEDED(com)) CoUninitialize();
    return false;
  }
  hr = client->Initialize(AUDCLNT_SHAREMODE_SHARED,
                          AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM |
                              AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
                          10000000, 0, &format, nullptr);
  if (FAILED(hr)) {
    *error = HResultMessage("RØDE 오디오 스트림을 시작할 수 없어요", hr);
    LogLyricVoiceEvent("playback-initialize-failed endpoint=" + device_id + " " + *error);
    device->Release();
    client->Release();
    if (SUCCEEDED(com)) CoUninitialize();
    return false;
  }
  UINT32 buffer_frames = 0;
  hr = client->GetBufferSize(&buffer_frames);
  IAudioRenderClient* render = nullptr;
  if (SUCCEEDED(hr)) {
    hr = client->GetService(__uuidof(IAudioRenderClient),
                            reinterpret_cast<void**>(&render));
  }
  if (FAILED(hr) || buffer_frames == 0) {
    *error = HResultMessage("RØDE 오디오 버퍼를 준비하지 못했어요", hr);
    LogLyricVoiceEvent("playback-buffer-failed endpoint=" + device_id + " bufferFrames=" +
                       std::to_string(buffer_frames) + " " + *error);
    device->Release();
    if (render) render->Release();
    client->Release();
    if (SUCCEEDED(com)) CoUninitialize();
    return false;
  }

  const UINT32 total_frames = static_cast<UINT32>(
      wave_data.size() / format.nBlockAlign);
  LogLyricVoiceEvent("playback-buffer-ready endpoint=" + device_id + " bufferFrames=" +
                     std::to_string(buffer_frames) + " totalFrames=" +
                     std::to_string(total_frames));
  UINT32 written_frames = 0;
  HRESULT playback_hr = client->Start();
  if (SUCCEEDED(playback_hr)) {
    LogLyricVoiceEvent("playback-started endpoint=" + device_id + " pid=" +
                       std::to_string(GetCurrentProcessId()));
    LogEndpointState(device, client);
  } else {
    LogLyricVoiceEvent("playback-start-failed endpoint=" + device_id + " " +
                       HResultMessage("IAudioClient::Start", playback_hr));
  }
  while (SUCCEEDED(playback_hr) && !cancelled.load() &&
         written_frames < total_frames) {
    UINT32 padding = 0;
    playback_hr = client->GetCurrentPadding(&padding);
    if (FAILED(playback_hr)) break;
    const UINT32 available = buffer_frames - std::min(buffer_frames, padding);
    if (available == 0) {
      Sleep(5);
      continue;
    }
    const UINT32 frames = std::min(available, total_frames - written_frames);
    BYTE* target = nullptr;
    playback_hr = render->GetBuffer(frames, &target);
    if (FAILED(playback_hr)) break;
    const size_t offset = static_cast<size_t>(written_frames) * format.nBlockAlign;
    std::memcpy(target, wave_data.data() + offset,
                static_cast<size_t>(frames) * format.nBlockAlign);
    playback_hr = render->ReleaseBuffer(frames, 0);
    if (SUCCEEDED(playback_hr)) written_frames += frames;
  }
  bool drained = false;
  while (SUCCEEDED(playback_hr) && !cancelled.load() &&
         written_frames == total_frames) {
    UINT32 padding = 0;
    playback_hr = client->GetCurrentPadding(&padding);
    if (FAILED(playback_hr)) break;
    if (padding == 0) {
      drained = true;
      break;
    }
    Sleep(5);
  }
  const bool cancelled_before_completion = cancelled.load() && !drained;
  const HRESULT stop_hr = client->Stop();
  device->Release();
  render->Release();
  client->Release();
  if (SUCCEEDED(com)) CoUninitialize();
  if (FAILED(playback_hr)) {
    *error = HResultMessage("RØDE 오디오 출력 중 오류가 났어요", playback_hr);
    LogLyricVoiceEvent("playback-stream-failed endpoint=" + device_id + " writtenFrames=" +
                       std::to_string(written_frames) + "/" +
                       std::to_string(total_frames) + " drained=" +
                       (drained ? "true" : "false") + " " + *error);
    return false;
  }
  if (FAILED(stop_hr)) {
    *error = HResultMessage("RØDE 오디오 스트림을 정지하지 못했어요", stop_hr);
    LogLyricVoiceEvent("playback-stop-failed endpoint=" + device_id + " " + *error);
    return false;
  }
  *was_cancelled = cancelled_before_completion;
  LogLyricVoiceEvent("playback-finished endpoint=" + device_id + " writtenFrames=" +
                     std::to_string(written_frames) + "/" +
                     std::to_string(total_frames) + " drained=" +
                     (drained ? "true" : "false") + " cancelled=" +
                     (*was_cancelled ? "true" : "false"));
  return true;
}

void LyricVoicePlugin::StopPlayback() {
  playback_cancelled_.store(true);
  if (playback_worker_.joinable()) playback_worker_.join();
  playback_cancelled_.store(false);
}

void LyricVoicePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  LogLyricVoiceEvent("method-call name=" + call.method_name());
  if (call.method_name() == "logEvent") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    const auto it = args ? args->find(flutter::EncodableValue("message"))
                         : flutter::EncodableMap::const_iterator{};
    const auto* message = args && it != args->end()
        ? std::get_if<std::string>(&it->second) : nullptr;
    if (!message) {
      LogLyricVoiceEvent("method-log-event invalid-args");
      result->Error("invalid_args", "진단 메시지가 없어요.");
      return;
    }
    LogLyricVoiceEvent("flutter " + *message);
    result->Success();
    return;
  }
  if (call.method_name() == "hasRodeOutput") {
    std::wstring device_name;
    std::string error;
    const bool found = FindRodeOutput(&device_name, &error);
    flutter::EncodableMap status;
    status.emplace(flutter::EncodableValue("ok"), flutter::EncodableValue(found));
    status.emplace(flutter::EncodableValue("device"),
                   flutter::EncodableValue(found ? WideToUtf8(device_name) : ""));
    status.emplace(flutter::EncodableValue("error"), flutter::EncodableValue(error));
    LogLyricVoiceEvent(found
        ? "method-result hasRodeOutput ok=true device=" + WideToUtf8(device_name)
        : "method-result hasRodeOutput ok=false error=" + error);
    result->Success(flutter::EncodableValue(std::move(status)));
    return;
  }
  if (call.method_name() == "stop") { StopPlayback(); result->Success(); return; }
  if (call.method_name() == "playFile") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) { result->Error("invalid_args", "파일 경로가 없어요."); return; }
    const auto it = args->find(flutter::EncodableValue("path"));
    const auto* path = it == args->end() ? nullptr : std::get_if<std::string>(&it->second);
    if (!path) { result->Error("invalid_args", "파일 경로가 없어요."); return; }
    StopPlayback();
    playback_cancelled_.store(false);
    playback_worker_ = std::thread(
        [this, path = Utf8ToWide(*path), result = std::move(result)]() mutable {
          std::string error;
          bool was_cancelled = false;
          std::wstring device_name;
          if (PlayWaveFile(path, playback_cancelled_, &was_cancelled,
                           &device_name, &error)) {
            LogLyricVoiceEvent("method-result playFile status=" +
                std::string(was_cancelled ? "cancelled" : "played") +
                " device=" + WideToUtf8(device_name));
            flutter::EncodableMap status;
            status.emplace(flutter::EncodableValue("status"),
                           flutter::EncodableValue(was_cancelled ? "cancelled" : "played"));
            status.emplace(flutter::EncodableValue("device"),
                           flutter::EncodableValue(WideToUtf8(device_name)));
            result->Success(flutter::EncodableValue(std::move(status)));
          } else {
            LogLyricVoiceEvent("playback-failed error=" + error);
            LogLyricVoiceEvent("method-result playFile status=error");
            result->Error("play_failed", error);
          }
        });
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
      size_t ready_count = 0;
      std::string first_error;
      for (const auto& entry : entries) {
        std::error_code ec;
        const bool cache_hit = std::filesystem::exists(entry.path, ec) && !ec;
        bool ready = cache_hit && std::filesystem::file_size(entry.path, ec) > 44 &&
                     !ec && IsUsableWaveFile(entry.path);
        std::string error;
        if (!ready) {
          std::filesystem::create_directories(std::filesystem::path(entry.path).parent_path(), ec);
          if (ec) {
            error = "가사 음성 캐시 폴더를 만들지 못했어요.";
          } else {
            std::lock_guard<std::mutex> synthesis_lock(g_synthesis_mutex);
            ready = SynthesizeKorean(entry.text, entry.path, &error);
          }
        if (ready && !IsUsableWaveFile(entry.path)) {
            ready = false;
            error = "합성된 파일이 올바른 PCM WAV가 아니에요.";
          }
        }
        if (ready) {
          ++ready_count;
        } else if (first_error.empty()) {
          first_error = error.empty() ? "WAV cache unavailable" : error;
        }
        uint64_t bytes = 0;
        if (ready) bytes = std::filesystem::file_size(entry.path, ec);
        flutter::EncodableMap item;
        item.emplace(flutter::EncodableValue("ready"), flutter::EncodableValue(ready));
        item.emplace(flutter::EncodableValue("bytes"), flutter::EncodableValue(static_cast<int64_t>(bytes)));
        item.emplace(flutter::EncodableValue("error"), flutter::EncodableValue(error));
        done.emplace_back(std::move(item));
      }
      if (SUCCEEDED(com)) CoUninitialize();
      LogLyricVoiceEvent("sapi-cache ready=" + std::to_string(ready_count) +
          "/" + std::to_string(entries.size()) +
          (first_error.empty() ? "" : " first_error=" + first_error));
      result->Success(flutter::EncodableValue(std::move(done)));
    });
    return;
  }
  result->NotImplemented();
}
