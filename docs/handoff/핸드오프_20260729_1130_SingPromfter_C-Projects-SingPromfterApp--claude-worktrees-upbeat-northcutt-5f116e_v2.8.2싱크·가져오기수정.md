## 대상
- 프로젝트: SingPromfter
- 작업 폴더: C:\Projects\SingPromfterApp\.claude\worktrees\upbeat-northcutt-5f116e
- 세션 시각: 2026-07-29 11:00 (KST)

## 세션 요약
v2.8.1에서 사용자가 보고한 결함 3건을 추적해 고치고 v2.8.2로 올렸다. 이어서 유튜브로 곡 1건을 추가하려다 가져오기가 전면 실패하는 것을 발견해 원인까지 잡았다. PR #1 생성, CI analyze·test 통과.

## 완료된 작업

### 커밋 (브랜치 `claude/upbeat-northcutt-5f116e`)
- `8a779e0` fix: 가사 자동 맞춤 재작성 + 전체화면 조작판 상태 고정 해제
- `29645a4` fix: 한글 경로에서 유튜브 가져오기가 통째로 실패하던 문제
- `12e74b4` ci: Flutter 3.41 deprecated API 두 건 analyze 실패 해소
- `940781e` release: v2.8.2

### PR
- https://github.com/kuroicode-beep/SingPromfter/pull/1 (base `master`, 21커밋)
- CI: analyze 통과 · test 통과 · **build-windows 실패(기존 문제, 아래 참조)**

### 1. 가사 자동 맞춤 재작성 (`lib/services/lyrics_align_service.dart`)
v2.8.1 구현이 틀린 값을 냈다. 원인 셋:
- 원곡−MR 위상 반전 상쇄가 성립하지 않음(demucs 결과를 mp3로 재인코딩한 파일이라 샘플 정렬 안 됨). 실측: 반주 구간 차이 신호 −15.0dB로 원곡(−17.3dB)과 거의 같음. → **포락선끼리 뺀다**(반주 0.3dB / 노래 4.4dB로 분리)
- 줄 시작점이 탐색 창 경계를 그대로 답으로 냄(41730ms 줄 → 37720ms, 창 하한 37730ms). → **앞이 1.5초 조용했던 줄만** 표본
- 부호가 반대(−4260을 넣어 5~6초 더 빨라짐)

문턱 계산도 하위15%~상위85% → 하위20%~상위2% + 최소이득 1.5dB로 변경(노래가 15% 미만인 곡에서 문턱이 0이 되던 문제).

표본이 1.5초 넘게 흩어지면 값을 내지 않고 이유를 설명한다.

### 2. 전체화면 조작판 상태 고정 해제 (`lib/screens/prompter_screen.dart`)
`PrompterScreen`은 `Navigator.push` builder로 만들어지고 그 builder는 한 번만 돈다. `controlsDrawerOpen`을 `widget`에서 읽어 무대 진입 순간 값에 얼어붙었다 — 손잡이를 눌러도 화면이 안 바뀜. `_displayMode`와 같은 방식으로 로컬 소유 전환.

### 3. 한글 경로 유튜브 가져오기 실패 (`lib/services/process/process_runner.dart`)
증상: 데이터 폴더가 `OneDrive\문서\data`일 때 `ERROR: Unable to download video: [Errno 22] Invalid argument`로 **항상** 실패.

원인: `start()`가 엄격한 `utf8.decoder`를 사용. yt-dlp(파이썬)는 stdout이 파이프면 cp949로 인코딩하므로 `[download] Destination: ...\문서\...` 줄에서 `FormatException` → `catchError`가 삼키고 `forEach` 종료 → **파이프를 아무도 안 비움** → yt-dlp가 stdout 쓰기에서 막히다 OSError로 사망.

`fetchMetadata`만 멀쩡했던 이유: `Process.run`은 기본이 `systemEncoding`이고, `--dump-single-json`은 `\uXXXX` 이스케이프라 순수 ASCII.

수정: `Utf8Decoder(allowMalformed: true)` + 회귀 테스트 5건(`test/services/process_runner_decoder_test.dart`). 그중 하나는 같은 입력을 엄격한 디코더에 넣어 실제로 던지는지 확인(없으면 나머지 테스트가 무의미), 또 하나는 깨진 줄 **다음** 줄들이 계속 읽히는지 확인(진짜 증상이 "스트림이 죽는다"이므로).

진단은 yt-dlp 자리에 Dart로 컴파일한 로그 래퍼 exe를 끼워 실제 인자·cwd·환경·전체 stdout/stderr를 받아 했다. 경로 바이트는 정상이었다(`eb ac b8 ec 84 9c` = `문서`의 올바른 UTF-8).

### 4. CI analyze 실패 해소
CI는 `channel: stable`이라 현재 Flutter 3.44.8을 받고, 로컬 SDK는 3.38.5. 그 사이 deprecated된 두 API 때문에 exit 1:
- `SizeTransition.axisAlignment` → `alignment`
- `ReorderableListView.onReorder` → `onReorderItem`

새 인자가 로컬 3.38에 없어 바꾸면 로컬 검증이 전부 깨진다. `// ignore:` + 업그레이드 시 할 일을 주석에 남김.

### 5. 문서·배포
- 완료보고서: `docs/reports/완료보고서_20260729_v2.8.2_싱크수정과가져오기복구_ClaudeCode.md`
- Outline 프로젝트 위키 갱신: https://outline.svil.kr/doc/singpromfter-TaJiToeqIy (섹션 06 추가 — 위키가 v1.1.3에서 멈춰 있어 그 사이 변화도 함께 정리)
- 배포: `C:\Projects\SingPromfterApp\dist\SingPromfter\singpromfter_app.exe` (v2.8.2, 바탕화면 바로가기 연결 확인)
- 검증: analyze 통과 · test **553건** · build windows 통과

### 6. 환경 수정 (리포에 없음, 이 PC 한정)
`%APPDATA%\yt-dlp\config`에 `--js-runtimes node` 추가. yt-dlp가 YouTube 추출에 JS 런타임을 요구하는데 기본 활성은 deno뿐이고 이 PC엔 없어 android vr 클라이언트로 우회 중이었다(포맷 누락). Node v24 사용. **ASCII 주석만 쓸 것** — yt-dlp가 이 파일을 시스템 코드페이지(cp949)로 읽어 한글 주석이면 파싱이 깨진다.

### 7. 곡 추가 (미완료 — 아래 참조)
- 개인 스킬 `song-add` 생성·수정: `~/.claude/skills/song-add/SKILL.md`
  - 최초엔 "기본은 원곡만, 나머지는 물어보기"로 썼으나 사용자 지적으로 **기본 3슬롯(원곡/MR/MR −2키)** 으로 고침. 분리 서버가 꺼져 있으면 확인 없이 켠다.
- 분리 서버 기동: `C:\Projects\svil-ai-work\separator_system\start.bat` → `http://127.0.0.1:8771` (htdemucs, two_stems, RTX 5060 Ti). **아직 켜져 있음 — 안 쓸 거면 끌 것.**
- yt-dlp 전역 설정(`%APPDATA%\yt-dlp\config`): `--js-runtimes "node:C:/Program Files/nodejs/node.exe"`
  - 절대경로 고정 이유: 앱이 Explorer에서 뜨면 PATH에 node가 없을 수 있고, 그러면 android vr 클라이언트로 조용히 폴백해 미디어 URL이 403이 된다.
  - **주의 2가지**: 이 파일은 시스템 코드페이지(cp949)로 파싱되므로 ASCII 주석만. 공백 있는 경로는 따옴표 필수(공백으로 토큰이 갈린다).

## 진행 중 / 미완료 작업

### 「선물 / 윤후」가 목록에 없다 — 재등록 필요 (최우선)
링크: `https://www.youtube.com/watch?v=t53sLfizA54` (224초, 조성 B♭)

경위:
1. 원곡 1슬롯으로 등록됐으나, 제목이 `윤후 - 선물(가사첨부)`라 LRCLIB 검색이 실패 → 제목을 `선물`로 정리하고 재검색했더니 **동명의 크리스마스 곡 가사**가 붙었다. 앱의 LRCLIB 3차 폴백이 제목만으로 넓게 찾아 가수가 안 맞아도 통과한다.
2. 사용자가 원한 구성은 처음부터 **3슬롯(원곡/MR/MR −2키)** 이었다. 한 번에 만들려고 기존 항목을 지우고 `sp_add_song(mode=aiSeparate, make_original, make_instrumental, pitch_semitones=-2)`로 재등록 시도.
3. 재등록이 `HTTP Error 403: Forbidden`으로 실패. 한 시간 사이 같은 영상을 여러 번 받아 유튜브가 막은 것으로 보인다(셸 단독 다운로드는 그 시점에도 됐지만 앱 경로는 계속 403).

**지우기 전에 재다운로드 가능 여부를 먼저 확인했어야 했다.** 지금 이 곡은 앱에 없다.

다음에 할 일:
- 시간을 두고(수 시간 권장) `song-add` 스킬대로 3슬롯 재등록
- 가사는 자동 부착 결과를 **반드시 확인** — 「선물」은 동명 곡이 많다. 가수가 안 맞으면 붙이지 말 것
- 구조적 개선 후보: LRCLIB 폴백이 가수 불일치로 매칭됐을 때 자동 부착 대신 후보를 제시하거나 경고

### 「넌 언제나」 LRC 드리프트
`.lrc`가 곡과 속도가 다른 판본(약 1.7% 드리프트, +640ms→+3740ms). 오프셋 하나로 못 맞춰 `lyricsOffsetMs = +1800`을 넣어 뒀다(중간은 맞고 앞뒤 어긋남). `.lrc` 재타이밍 필요.

### CI build-windows 실패 (기존 문제)
`audioplayers_windows`가 `<experimental/coroutine>`을 쓰는데 러너의 MSVC 14.51(VS18)이 거부(STL1011). 이 브랜치에서 바뀐 빌드 관련 파일은 pubspec 버전 한 줄뿐이라 master에서도 동일하게 실패한다. audioplayers 업그레이드는 이 앱의 피치·템포 구조 전체가 그 제약(Windows에서 PCM 미노출, setPlaybackRate가 음정을 끌고 감) 위에 서 있어 별도 검토 필요.

### 전체화면 드로어 수정에 위젯 테스트 없음
`PrompterScreen` 생성에 `PlaybackController`(필수 의존성 9개)가 필요해 못 넣었다. 페이크를 하나 만들면 이후 무대 회귀 테스트가 전부 쉬워진다.

### 로컬 Flutter SDK 8개월 뒤처짐
3.38.5 vs CI stable 3.44.8. 올리면 위 deprecation 두 건을 제대로 고칠 수 있으나 553건 재검증 + 재빌드 동반.

## 주요 결정사항 / 규칙

- **저작권 확인 게이트는 앱 UI 전용을 유지한다.** HTTP·MCP로 세울 수 없고, 사용자가 "테스트니까 건너뛰자"고 해도 대신 눌러 주지 않는다(클릭 1회면 끝나고, 게이트의 존재 이유가 사람의 확인이므로).
- 외부 도구 출력은 **절대 엄격한 UTF-8로 디코드하지 않는다.** 파싱에 쓰는 값은 전부 ASCII이므로 `allowMalformed: true`가 옳다. 핵심은 던지지 않는 것.
- 시간축 규약은 `lyrics_sync_math.dart`가 단독 소유. 렌더 축(플레이어) ↔ 원본 축(LRC)은 `toRendered`/`toSource` 두 곳에서만 오간다. `lyricsOffsetMs`는 **원본 축**(0.85배에서 가사가 363ms 늦는 것을 화면으로 확인하고 계획에서 뒤집음).
- 가사 자동 맞춤은 **못 맞추면 못 맞춘다고 말한다.** 억지 중앙값 금지.

## 참고 정보

- 저장소: https://github.com/kuroicode-beep/SingPromfter (기본 브랜치 `master`)
- PR: https://github.com/kuroicode-beep/SingPromfter/pull/1
- 제어 API: `http://127.0.0.1:8772/api/...` (앱 실행 중일 때만)
- MCP: `singprompter` (`sp_add_song`, `sp_jobs`, `sp_get_song`, `sp_fetch_lyrics`, `sp_edit_song` 등)
- 데이터: `C:\Users\kuroi\OneDrive\문서\data` (`mp3/`, `lrc/`, `songs.json`)
- 설정: `%APPDATA%\com.svil\singpromfter_app\shared_preferences.json`
- 완료보고서: `docs/reports/완료보고서_20260729_v2.8.2_싱크수정과가져오기복구_ClaudeCode.md`
- 위키: https://outline.svil.kr/doc/singpromfter-TaJiToeqIy

## 다음 세션 시작 시 할 일

1. 「선물 / 윤후」 3슬롯 재등록 (403이 풀린 뒤) + 가사 정합성 확인
2. LRCLIB 폴백이 가수 불일치로 매칭될 때의 처리 개선 검토
2-1. 분리 서버가 아직 떠 있다 — 안 쓸 거면 종료(VRAM)
3. PR #1 머지 여부 결정 (build-windows는 기존 문제라 별건으로 다룰지 판단)
4. 「넌 언제나」 `.lrc` 재타이밍
5. (선택) Flutter SDK 업그레이드 → deprecated API 두 건 정식 교체
6. (선택) `PlaybackController` 페이크 도입 → 무대 위젯 테스트 확보
