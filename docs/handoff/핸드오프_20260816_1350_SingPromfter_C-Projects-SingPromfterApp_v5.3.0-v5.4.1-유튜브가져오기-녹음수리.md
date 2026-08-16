# 핸드오프_20260816_1350_SingPromfter_C-Projects-SingPromfterApp_v5.3.0-v5.4.1-유튜브가져오기-녹음수리

## 대상
- 프로젝트: SingPromfter
- 작업 폴더: C:\Projects\SingPromfterApp (워크트리 youtube-search-import-no-response-58eaef에서 작업 후 master 병합·정리 완료)
- 세션 시각: 2026-08-16 13:50 (KST)

## 세션 요약
- 사용자 신고 2건("유튜브 가져오기 무반응", "녹음이 파일 없이 끝남")을 추적해 원인 규명·수리하고 v5.2.0 → v5.4.1로 3회 릴리스했다.
- 버튼 위치 개선(제목 뒤 아이콘) 1건도 반영. 전부 master 병합·dist 배포·실기 검증 완료.

## 완료된 작업
- **v5.3.0 (커밋 095d9a7)** 유튜브 가져오기 403 대응 — 근본 원인은 yt-dlp의 JS 챌린지 해석기(pip 패키지 **yt-dlp-ejs**) 부재. `py -3.13 -m pip install -U yt-dlp yt-dlp-ejs`(0.8.0)로 해결. 앱에는 ① 실패 시 전 탭 스낵바 알림(`_failJob`에서 `_emit`) ② 403 안내에 "다른 영상 시도" 팁 ③ 설정 외부도구에 JS 해석기 진단 표시(`parseYtDlpEjsVersion`, `/api/state tools.ytDlp.ejs`) 추가.
- **v5.4.0 (커밋 a457562)** 검색 결과 [가져오기]를 제목 바로 뒤 아이콘 버튼(⬇)으로 이동. 접근성 유지(50px·툴팁·Semantics). 스크린샷 검증.
- **v5.4.1 (커밋 f595135)** 녹음 무음 실패 수리 — Dart `Process.run` 기본 디코딩(cp949)이 ffmpeg의 UTF-8 장치 목록을 깨뜨려("마이크(RØDE...)" → mojibake) 캡처 즉사 → 유령 "녹음 중" → 0초 판정 삭제. `RecordingController.refreshDevices`를 start() 스트리밍(UTF-8)으로 전환, 캡처 즉사 감시(`onError`) 추가. R 키 주입 E2E로 테이크 등록까지 확인(검증 테이크는 정리).
- 곡 등록: "비처럼 음악처럼"(김현식 공식 음원, id 03af7246 → 사용자가 삭제한 듯 목록에 없음) / "비처럼 음악처럼 (가사영상)"(id d1404590) — 원래 시도 영상 2개는 반복 실패로 영상 단위 일시 차단됐다가 시간 경과 후 해제됨.
- 36.7GB 폭주 녹음 파일(recordings/b5c4cbb4-…wav, 8/1~4 미등록) 사용자 승인 후 삭제 — C: 여유 147→182GB.
- flutter analyze 0건 · test 883개 통과. dist 배포(robocopy /MIR) 후 실행 앱 v5.4.1 확인. 바탕화면 SingPromfter.lnk → dist exe 확인.
- 워크트리·브랜치: master 병합 → 로컬·원격 브랜치 삭제 → `git worktree list`에 main만 남음 확인.
- 문서: docs/reports/완료보고서_20260816_v5.3.0-v5.4.1_유튜브가져오기와녹음수리_ClaudeCode.md · Outline "SingPromfter 프로젝트 위키"(TaJiToeqIy) 2026-08-16 절 append(rev 24).
- 메모리: `ytdlp-403-ejs-and-pervideo-block` 신규, `encoding-pitfalls`에 12번(Dart Process.run cp949 vs ffmpeg UTF-8) 추가.

## 진행 중 / 미완료 작업
- 워크트리 폴더 껍데기 `C:\Projects\SingPromfterApp\.claude\worktrees\youtube-search-import-no-response-58eaef` — 세션 프로세스가 cwd로 점유해 삭제 불가. 세션 종료 후 `rm -rf`로 제거(내용물은 이미 비움, git 참조 없음).
- 옛 워크트리 폴더 `upbeat-northcutt-5f116e` — 다른 세션 산출물이라 미삭제. git 등록은 없음. 사용자 판단 대기.

## 주요 결정사항 / 규칙
- 유튜브 403 진단 시 같은 영상을 반복 다운로드하지 말 것 — 영상 단위 일시 차단을 스스로 만든다. 우회는 같은 곡의 다른 업로드.
- 앱이 띄우는 외부 도구의 stderr가 필요하면 래퍼 exe(-v/tee) + `shared_preferences.json`의 `flutter.tool_path_<tool>` 주입(앱 완전 종료 상태에서 편집, 끝나면 키 제거).
- Dart에서 외부 도구 출력을 읽을 땐 Process.run 기본 인코딩 금지 — 스트리밍 + `Utf8Decoder(allowMalformed: true)` (도구별 인코딩: ffmpeg=UTF-8, python 파이프=cp949, where=OEM).

## 참고 정보
- 실행 앱: C:\Projects\SingPromfterApp\dist\SingPromfter\singpromfter_app.exe (v5.4.1, 제어 API 127.0.0.1:8772)
- 저장 데이터: C:\Users\kuroi\OneDrive\문서\data\ (songs.json·recordings.json·recordings/)
- Outline 위키: /doc/singpromfter-TaJiToeqIy · 완료보고서: docs/reports/완료보고서_20260816_….md
- 랜딩페이지: site/ 존재, 이번 변경(UX·버그픽스)으로는 미갱신(사용자 회신 없어 그대로 둠)

## 다음 세션 시작 시 할 일
1. 워크트리 껍데기 폴더 삭제 확인(위 경로) — 1분
2. 사용자 MR 청취 피드백 확인 — 공식 음원 곡 MR이 GPU 겹침 시점에 분리됨, 잡음 있으면 재분리
3. (선택) 미리듣기 버튼 아이콘화로 행 높이 축소 · 홈 실패 카드에 EJS 진단 연동
