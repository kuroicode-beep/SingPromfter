# 핸드오프 — SingPromfter v5.0.0 두 개발 라인 통합 완료

- 일시: 2026-08-08 22:00 KST · 작업자: Claude Code (Opus 5)
- 프로젝트: SingPromfter · 작업 폴더: `C:\Projects\SingPromfterApp` (master 직접)
- 직전 핸드오프(20260808_2100, v3.0.0 완료) 이후 증분

## 무슨 일이 있었나

v3.0.0 릴리스 직후 사용자가 "버튼·레이아웃이 롤백됐다"고 보고. 원인: **이번 세션이 Outline 최신 핸드오프를 확인하지 않고 master(v2.8.3) 기준으로 작업** — 실사용 앱은 미병합 브랜치(v2.9~v4.3, PR #2, 79커밋)의 dist 빌드였다. 사용자 승인 하에 두 라인을 통합했다.

## 완료된 작업

1. **즉시 복구**: 바로가기를 dist v4.3로 되돌림, songs.json(11곡, v4.x 필드) 무손상 확인
2. **통합 병합** ([PR #4](https://github.com/kuroicode-beep/SingPromfter/pull/4) → master `3649679`): v4.3 브랜치 기준 + master(작곡 라인) 병합, 충돌 13파일 해소 — 양쪽 기능 전부 보존
   - 녹음 장치 설정: `recordingDevice`로 통일(구 `recordingDeviceName`은 fromJson 폴백)
   - 설정 녹음 섹션: `_RecordingSection`(장치+입력 볼륨+마이크 테스트)으로 단일화
   - 버전 **v5.0.0** — 양쪽이 서로 다른 v3.x를 썼던 번호 충돌 회피. VERSION_HISTORY는 브랜치 전체 이력 + v5.0.0 통합 엔트리
3. **검증**: analyze 0건 · 테스트 874개 통과 · 실기 스모크(v5.0.0, 11곡 로드)
4. **배포**: dist\SingPromfter=v5.0.0(v4.3 백업: dist\SingPromfter-v4.3.0) · [Release v5.0.0](https://github.com/kuroicode-beep/SingPromfter/releases/tag/v5.0.0)(zip 53.6MB) · 홈페이지 v5.0.0+AI 카드 5개 언어(gh-pages 반영, 커스텀 도메인은 캐시 지연 중)
5. **정리**: PR #2 자동 머지 처리됨, 작업 브랜치 전부 삭제(로컬·리모트), 남은 브랜치는 master·gh-pages뿐

## 미결 / 사용자 판단 대기

- **v3.0.0 GitHub 릴리스 삭제 여부** — 기능이 전부 v5.0.0에 포함되고 데이터 필드가 좁아 실행 비권장 빌드. 삭제 여부는 소장님 결정 대기
- 청취 검증: v4.3 기능 전반이 v5.0.0에서 그대로인지 + 작곡/믹싱 E2E (완료보고서 체크리스트)
- 홈페이지 소스는 이제 **repo `site/` + publish_site.ps1**이 정본 — gh-pages 직접 수정 금지

## 교훈 (다음 세션 필수)

- **세션 시작 시 Outline 최신 핸드오프부터 확인** — 워크트리 docs만 보면 브랜치별 이력이 안 보인다. 브랜치 목록·열린 PR 확인도 계획 단계 필수
- 완료보고서: `docs/reports/완료보고서_20260808_v5.0.0_두라인통합_ClaudeCode.md`
