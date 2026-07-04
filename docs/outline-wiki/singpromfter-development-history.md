# SingPromfter 개발 히스토리

작성일: 2026-07-04  
기준 버전: `1.1.3+1`

## 01. 릴리스 타임라인

| 버전 | 태그 | 날짜 | 핵심 내용 |
|---|---|---|---|
| `v1.1.3` | `v1.1.3` | 2026-07-04 | 키보드 단축키 Focus/Shortcuts 기반 재구현 (`PrompterKeyboardScope`) |
| `v1.1.2` | `v1.1.2` | 2026-07-04 | 화살표 키 볼륨·프롬프터 속도 단축키 추가 |
| `v1.1.1` | `v1.1.1` | 2026-07-04 | UI 개선 2차 — 상단 탭, 카드 버튼, 하단 바, 접이식 큐 |
| `v1.1.0` | `bbf7998` | 2026-07-04 | Sprint 6~8 디자인 리뉴얼 및 기능 개선 |
| `v1.0.1` | — | 2026-07-04 | Outline 위키 갱신, 문서 정합성 패치 |
| `v1.0.0` | `2f2168a` | 2026-07-04 | Sprint 5 품질 보증, CI 구축 |

## 02. Sprint 진행 요약

| Sprint | 버전 | 상태 | 핵심 결과 |
|---|---|---|---|
| Sprint 1 | `v0.5.1` | 완료 | 키 핸들러 충돌, 큐 재정렬, 가사 전용 자동재생/스크롤, 예외 처리 |
| Sprint 2 | `v0.6.0` | 완료 | 저시력 접근성 강화, 터치 타겟, Semantics 라벨, 색 대비 |
| Sprint 3 | `v0.7.0` | 완료 | `SongListScreen` God Widget 분해, 서비스/코디네이터 모듈화 |
| Sprint 4 | `v0.9.0` | 완료 | 검색/즐겨찾기, 백업/복원, 트리밍/라벨, 재생 속도, 일괄 등록 |
| Sprint 5 | `v1.0.0` | 완료 | 테스트 20개, GitHub Actions CI, 분석 옵션 강화, 상수화 |
| Sprint 6 | `v1.1.0-beta` | 완료 | Core Precision Dark 테마, `AppShapes`/`AppTypography`, 16px 미만 제거 |
| Sprint 7 | `v1.1.0-beta` | 완료 | 3열 홈 레이아웃, 곡 검색/즐겨찾기/설정, `AppNavRail` (후속 v1.1.1에서 상단 탭으로 교체) |
| Sprint 8 | `v1.1.0` | 완료 | 가수 필드, 줄 하이라이트, 예약/시작 버튼, 큐 NOW, 진행률 바 |
| UI 개선 2차 | `v1.1.1` | 완료 | 상단 탭 네비, 카드 버튼 정리, 하단 바 2계층, 접이식 큐, `minTouchTarget` 50 |
| 키보드 핫픽스 | `v1.1.2`~`v1.1.3` | 완료 | ↑↓ 볼륨, ←→ 속도, `PrompterKeyboardScope` |

## 03. 현재 릴리스 상태

- 앱 버전: `1.1.3+1`
- GitHub 기본 브랜치: `master`
- Windows 빌드: `flutter build windows --release`
- 배포 폴더: `dist/SingPromfter-v1.1.3/`

## 04. 검증 기준

```powershell
flutter analyze
flutter test
flutter build windows --release
```

2026-07-04 기준: analyze 통과, 테스트 32개, Windows 릴리스 빌드 성공.

## 05. 남은 운영 메모

- `audioplayers` 6.x, `file_picker` 11.x 메이저 업데이트는 별도 브랜치에서 진행한다.
- mp3 재생, 파일 선택, 백업/복원, 삭제 실행 취소는 수동 회귀 테스트가 필요하다.
- Outline 문서 원본은 `docs/outline-wiki/`에 유지하며, Outline 문서가 손상되면 이 원본으로 재게시한다.
