# 완료보고서 — v2.3.0 가져오기 개선·EQ 미터 / v2.4.0 AI 제어(MCP)

- 작성일: 2026-07-28
- 작업자: Claude Code
- 브랜치: `claude/upbeat-northcutt-5f116e`

## v2.3.0 — 진단 수정 + 전체화면 EQ 미터

### Stream A: 가져오기 진단 수정
| 항목 | 내용 |
|---|---|
| 제목 클리너 | `youtube_title_cleaner.dart` — `[MR]`/`(Inst.)`/노래방/KY·TJ/키 표기 제거, `가수 - 제목` 분리(업로더 유사 조각 우선). 등록·LRCLIB 검색 양쪽 적용. **가사 적중률 개선의 핵심** |
| 가사 3차 폴백 | 정확 조회 → 제목+가수 검색 → **제목만 검색** (채널명 오염 구제) |
| 가사 길이 가드 | `_pickBest` ±7초 허용 오차 — 초과 후보는 못 찾음 처리. 정확 조회 결과에도 동일 검증 |
| 재검색 결함 | `_registerImportedSong`의 제목 기반 재검색 → `AddSongResult.song` 직접 사용 |
| 실패 재시도 | `ImportJobController.retry` + 홈 스트립·작업 목록 "다시 시도" 버튼. 홈 스트립은 진행 중이 없어도 실패 작업을 남겨 보여줌 |
| yt-dlp 관리 | 설정 "외부 도구" 섹션(버전 표시 + 업데이트(-U)), 다운로드 실패 메시지에 업데이트 힌트 |
| 상태 갱신 | 30초 주기 도구·분리 서버 상태 자동 갱신 |

### Stream B: 전체화면 EQ 미터
- **분석**: `LevelAnalysisService` — 밴드별 6회 순차 ffmpeg 패스(highpass/lowpass + astats), 44100/1764 = **정확히 25fps**(4초 톤 100프레임 실측 검증), −60dB 플로어 0..100 정량화, `data/cache/levels/` 캐시. 가져오기 등록 직후 선분석.
- **표시**: `PrompterEqMeter` — 좌하단 6밴드, 자체 Ticker + `CustomPaint(repaint notifier)`로 **setState 없이** 60fps, 어택 즉시/릴리즈 감쇠 + 피크홀드, 그라데이션 `primary→accentMax→tertiary`. 분석 전·ffmpeg 부재 시 사인 펄스 폴백, 정지 시 Ticker 정지(CPU 0).
- **접근성**: `IgnorePointer`+`ExcludeSemantics`, 설정 "무대 EQ 애니메이션" 스위치(켜짐/꺼짐 텍스트 병기, 기본 켜짐).

### Stream D: SAW 분리 서버 (svil-ai-work `bb79f09`)
확인 결과 **two-stems와 VRAM 유휴 언로드는 이미 충족** — 서버가 `--two-stems vocals`를 쓰고 demucs를 작업마다 서브프로세스로 돌려 유휴 시 VRAM을 잡지 않는 구조. 대신 실제 문제였던 `output/` 무한 증식을 수리: 최근 30개만 유지(시작·완료 시 자동 정리), status에 `two_stems`/`vram_held_idle` 명시.

## v2.4.0 — AI 제어(MCP)

### 구조 (3계층)
```
프롬프트 → singprompter_mcp.py (stdio JSON-RPC)
        → 127.0.0.1:8772 제어 API (ControlServer, 앱 내부)
        → AppController (헤드리스 중심부)
```

### AppController 추출 (최대 리팩터)
`song_list_screen.dart` State(1,319줄)에 갇혀 있던 오케스트레이션을 BuildContext 없는 `AppController`(724줄)로 이전. 화면은 959줄로 축소되고 **위임 getter/setter로 기존 이름을 유지해 `SongListScreenContent` 이하 위젯 트리는 무변경**. 화면에는 대화상자·스낵바·FilePicker·녹음 UI만 남음. 신규 헤드리스 API: `setPitch(절대값)`, `removeSong`, `updateSongFields`, `fetchSyncedLyricsFor(songId)`, `enqueueImport`, `play()/pause()`(멱등).

### 제어 API (루프백 전용)
`GET /api/state·songs·queue·jobs`, `POST /api/songs`(가져오기), `PATCH/DELETE /api/songs/{id}`, `POST .../lyrics/fetch`, `POST .../pitch`, 큐 조작, `POST /api/playback/select|play|pause|toggle|stop|restart|seek|volume|rate`, 작업 취소·재시도. 포트 충돌 시 로그만 남기고 앱 정상 동작.

**저작권 게이트**: ack 미확인 시 곡 추가 → `409 notice_not_acked`. **ack를 세팅하는 엔드포인트는 없음** — 최초 1회 확인은 앱 화면 모달에서만(사용자 본인 확인 의미 보존, API 우회 불가).

### MCP 서버 (도구 24개)
`tool/mcp/singprompter_mcp.py` + 저장소 루트 `.mcp.json` 등록. 파괴적 도구(`sp_delete_song`, `sp_queue_clear`)는 `confirm=true` 필수. 앱 미실행 시 "앱이 실행 중인지 확인" 안내. Windows cp949 콘솔 대비 stdio UTF-8 고정.

## 검증

| 항목 | 결과 |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | **276 통과** (v2.2.0 대비 +59) |
| `flutter build windows --release` | 성공 |
| ffmpeg 분석 실측 | 4초 톤 → 100프레임(25fps) 확인 |
| E2E 스모크 | 앱 실행 → `GET /api/state` `{ok:true, version:2.4.0}` · 곡 6개 목록 · 404 처리 확인 |
| MCP E2E | 앱 실행 상태에서 `sp_state` → `ok:true, version:2.4.0` |
| MCP 가드 | confirm 미지정 삭제 거절 · 앱 미실행 연결 안내 확인 |

## 수동 확인 권장
1. MR 제목 영상 가져오기 → 정제된 제목·가사 적중 확인
2. 전체화면 EQ — 재생/일시정지/곡 전환, 설정에서 끄기
3. Claude Code를 이 저장소에서 열고(앱 켠 상태) "지금 상태 알려줘" → `sp_state` 동작 확인
4. `sp_add_song` 실전 사용 — 첫 사용이면 앱에서 저작권 확인 1회 필요
