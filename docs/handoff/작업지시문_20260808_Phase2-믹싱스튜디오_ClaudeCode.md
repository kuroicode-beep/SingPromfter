# 작업지시문 — Phase 2: 믹싱 스튜디오 (v3.0.0)

- 작성일: 2026-08-08 · 담당: Claude Code · 정본 스펙: docs/스펙 §1.1·§3.3 · 선행: Phase 1 완료

## 목표

테이크별 믹스 설정(밸런스·리버브·노이즈 제거)과 테이크 보컬 분리를 붙여 "다시 합치기" 재믹스를 완성한다.

## 작업 항목

1. **믹스 체인 확장** — `lib/services/take_mix_service.dart`
   - 게인 계산 순수 함수: `mixGains(balance)` → acc=(1-b)*2, vocal=b*2, 각 clamp 0~1.6 (0.5=1.0/1.0).
   - `buildMixArgs` 확장: `[0:a]volume=<acc>[b];[1:a]adelay,<afftdn,><aecho,>volume=<vocal>[v];[b][v]amix…` — 순서: 노이즈→리버브→볼륨.
   - aecho 프리셋 상수: karaoke `0.8:0.85:60:0.35` / hall `0.8:0.88:220:0.4` / studio `0.7:0.8:40:0.25`.
2. **테이크 보컬 분리** (로컬AI 게이트 — Phase 4 전까지는 게이트 스텁 true 허용)
   - `AppController`에 `separateTake(RecordingTake)`: 보컬 wav를 8771 `POST /api/separator/separate` → `vocals_path` 결과를 `<id>_sep.wav`로 복사 → `separatedFileName` 기록.
   - 믹스·내보내기에서 sep 존재+사용 토글 시 보컬 소스로 sep 사용.
3. **믹스 설정 다이얼로그** — `lib/dialogs/take_mix_dialog.dart` 신규
   - 밸런스 슬라이더(보컬↔반주, % 텍스트 병기) / 리버브 칩 4개 / 노이즈 제거 스위치 / `보컬 분리` 버튼(진행 중 표시) / `다시 합치기` 버튼.
   - 저장 시 take.copyWith(mixBalance·reverbPreset·noiseReduction) → 라이브러리 update → 재믹스 실행.
4. **녹음 탭 배선** — recordings_panel 행에 `믹스 설정` 버튼 추가(기존 prop-drilling 패턴).

## 테스트

- take_mix_service_test 확장: mixGains 경계(0·0.5·1)·리버브/노이즈 체인 문자열·필터 순서.

## 완료 기준

- 밸런스 80% 보컬 + 노래방 리버브 + 노이즈 제거로 재믹스 청취 확인 · 분리(8771 기동 시) 후 sep 사용 믹스 동작 · analyze/test 통과.

## 주의

- 재믹스는 기존 `<id>_mix.m4a`를 덮어쓴다(실패 시 기존 파일 보존 — 임시 파일로 만들고 성공 시 교체).
- 분리 서버 busy면 대기 안내 문구, 취소 가능하게.
