# gen_audio — 음성 안내·피아노 에셋 생성기

앱에 내장되는 오디오 에셋을 개발 시점에 굽는 도구다. **런타임에는 서버가 필요 없다** — 생성된 WAV를 커밋해 빌드에 포함한다.

## TTS 클립 (`generate_tts.dart`)

- 정본: `lib/constants/voice_clips.dart` (`VoiceClips.all`) — 앱과 같은 파일을 import하므로 문구·파일이 어긋날 수 없다.
- 보이스: SVIL 로컬 TTS `female_calm` (Qwen3 제로샷).
- 출력: `assets/audio/tts/<id>.wav` (16bit mono 32kHz).

```bash
# 사전 조건: 8765 프록시 + 8770 Qwen3 백엔드 기동
#   C:\Projects\svil-ai-work\tts_system\start.bat
#   C:\ai-qwen3tts\start.bat
dart run tool/gen_audio/generate_tts.dart          # 없는 것만(멱등)
dart run tool/gen_audio/generate_tts.dart --force  # 전부 재생성
```

- 문구를 고치면 해당 wav를 지우고 다시 실행한다.
- GPU 직렬 처리라 병렬 요청 금지 — 스크립트가 한 개씩 보낸다.
- ComfyUI 등 다른 GPU 작업이 VRAM을 점유하면 8770이 502로 죽는다 — 큐가 빈 뒤 실행할 것.

## 피아노 런 (`generate_piano.dart`)

- 배음 합성(기음+5배음, 지수 감쇠) 피아노풍 톤. 서버 불필요, 순수 Dart.
- 런 하나 = 5음 스케일(도-레-미-파-솔-파-미-레-도, 120bpm).
- 출력: `assets/audio/piano/run_<midi>.wav`, MIDI 48(C3)~65(F4) 18개.
- 남성 음역은 48~60, 여성은 53~65를 쓴다(`TrainingVoiceRange`).

```bash
dart run tool/gen_audio/generate_piano.dart
```
