## 대상
- 프로젝트: SingPromfter
- 작업 폴더: C:\Projects\SingPromfterApp\.claude\worktrees\upbeat-northcutt-5f116e
- 세션 시각: 2026-07-30 08:32 (KST)

## 세션 요약
직전 핸드오프(20260730_0530, v2.10.0) 이후 증분. 사용자 보고 4건(선물 싱크·조작판·글자·밝기)을 잡으며 수동 싱크 체계를 만들고(v2.11.0), 검수에서 자동 싱크 규약 위반을 고치고(v2.11.1), 곡 검색 탭에 유튜브 검색기를 붙이고(v2.12.0), 가져오기를 구성 팝업 하나로 재편했다(v2.13.0). 전부 PR #2에 있고 실기 배포 완료.

## 완료된 작업

### 커밋 (브랜치 `claude/upbeat-northcutt-5f116e`, PR #2)
- `d9ac353` release: v2.11.0 — 싱크를 직접 맞추는 길 + 조작판 레이아웃 수리
- `21a17e4` fix: 오프셋 버튼 걸음을 `.`/`/` 단축키와 같은 상수로
- `9c9c040` fix: v2.11.1 — 자동 싱크가 노래방 슬롯의 수동 싱크를 지우던 규약 위반
- `180ea91` feat: v2.12.0 — 곡 검색에 유튜브 검색기
- `cab8a5b` feat: v2.13.0 — 유튜브 가져오기를 구성 팝업 하나로

### v2.11.0 — 수동 싱크
- T = "여기가 첫 줄"(재생 중 앵커, ±10초 가드), `.`/`/` = 0.2초 당기기/밀기(즉시 저장), 홈·무대 양쪽
- 슬롯 그룹 규약: 1·2·3(같은 녹음) 싱크 연동, 4(노래방) 별도 — `Song.withLyricsOffsetForSlot`/`lyricsSyncSlotGroup`(track_variant.dart) 소유
- 구간 배분 곡(LRC 없음)에서 오프셋이 무시되던 결함 수정
- 조작판: 첫 줄 Wrap(가로 잘림), `drawerBodyBudget`(세로 — 가사 뷰 30% 보장, 초과분 스크롤)
- 무대 위·아래 줄 +2pt(0.76/0.86), 미도달 가사 밝기 0.70
- 「선물 / 윤후」(id 551b1efe): 로컬 faster-whisper(large-v3-turbo, word_timestamps, VAD 끔)로 25줄 LRC 생성·부착. LRCLIB에 없는 곡의 유일한 경로

### v2.11.1 — 검수 수확
- `_applyAlignedOffset`이 전 슬롯(4번 포함)에 덮어쓰던 것 → 1·2·3만. 화면 반영도 듣는 슬롯이 그 녹음일 때만
- `replaceSongInList` 저장 직렬화(사슬) — 연타 시 낡은 스냅샷이 나중에 디스크에 남던 틈

### v2.12.0 — 유튜브 검색기
- 곡 검색 탭 [내 곡|유튜브] 전환(SearchHubPanel). 검색은 Enter/버튼만(search.list 100유닛/회)
- 차트 2개: KR 인기 음악(videos.list mostPopular, 1유닛) / TJ노래방 공식 채널(`UCZUhx8ClCv6paFW7qi3qljg`) 최근 8주 조회수순. 세션 캐시
- `YoutubeDataClient`(lib/services/youtube_data_client.dart) — `YOUTUBE_API_KEY` 환경변수(사용자 수준 등록 확인), 키 없으면 missingKey 안내, 403은 할당량 안내
- `PickSongDialog` — 4번 점유 곡은 "4번 사용 중" 배지 + 덮어쓰기 확인(repo.addBackingTrack이 파일 교체)

### v2.13.0 — 가져오기 구성 팝업
- 버튼 하나 → `YoutubeImportDialog`: 기본(원곡/MR/MR−2키) · 남자키(원곡/MR−5키/MR−7키) · 4번슬롯(원음·−2·−5·−7 칩+수동)
- `ImportPlan.instrumentalSemitones` 신설(MR 슬롯 자체가 키조절본). 파이프라인은 원본 MR로 키조절 슬롯을 먼저 굽고 그다음 MR 슬롯을 자기 자리에서 렌더 교체 — 순서 바뀌면 −7이 −5 위에 얹힘(주석 명시)
- `ImportJob.trackSemitones` — 노래방 슬롯 부착 후 같은 자리 키 굽기. 렌더 실패 시 원키로 남고 라벨 일치
- 키 범위 ±6→±8(pitch_math.dart)

### 검증·배포
- analyze 0건 · 테스트 677건 · Windows 빌드 · dist\SingPromfter 배포(v2.13.0 실기 확인)
- 완료보고서: docs/reports/완료보고서_20260730_v2.11-v2.13_수동싱크와유튜브검색_ClaudeCode.md
- Outline 위키 섹션 07 추가: https://outline.svil.kr/doc/singpromfter-TaJiToeqIy

## 진행 중 / 미완료 작업
- **남자키 구성 실사용 미검증** — 한 곡 가져와서 −5/−7 슬롯 실청 필요 (코드·테스트는 통과, 귀 검증만 남음)
- 「선물」 LRC 싱크 실청 (Whisper 시각이 발성보다 ~1초 이름 — 실질 선행. 어긋나면 T 또는 `.`/`/`)
- PR #2 머지 대기 (18커밋, CI 초록)
- 이월: 「봄이 와도」 싱크 실청, 「넌 언제나」 슬롯3 사용자 키 −2 의도 확인

## 주요 결정사항 / 규칙 (증분)
- 싱크 오프셋: 1·2·3 연동 / 4 별도. 자동 싱크는 1·2·3만 만진다(측정 근거가 그 녹음)
- 싱크 걸음 200ms는 `lyricsNudgeStepMs`(prompter_keyboard_scope.dart) 단독 소유 — 버튼·키 공유
- 유튜브 검색은 증분 검색 금지(할당량). 차트는 세션 캐시
- "앱 내 유튜브 검색 안 함" 로드맵 결정은 2026-07-30 사용자 지시로 번복(문서 갱신됨)
- 키조절 범위 ±8 — UI 기본값은 여전히 작은 값

## 참고 정보
- 저장소: https://github.com/kuroicode-beep/SingPromfter · PR #2: https://github.com/kuroicode-beep/SingPromfter/pull/2
- 데이터: C:\Users\kuroi\OneDrive\문서\data (mp3/, lrc/, songs.json)
- TJ 채널 ID는 실키 조회로 확정(구독 181만) — YoutubeDataClient.karaokeChannelId 주석 참조
- 분리 서버: 현재 꺼짐

## 다음 세션 시작 시 할 일
1. 남자키 구성으로 한 곡 가져와 −5/−7 실청 검증
2. 「선물」·「봄이 와도」 싱크 실청 (필요시 T/`.`/`/`)
3. PR #2 머지 여부 결정
4. (후보) LRCLIB 영어 부제 폴백, audioplayers 업그레이드 별도 브랜치
