// file: lib/utils/ai_gate.dart
//
// AI 진입점을 화면에서 어떻게 다룰지 정하는 단일 결정점.
// 위젯은 "이 버튼을 숨길까 흐릴까"를 스스로 판단하지 않고 결과만 받는다.
//
// 규칙 하나만 지키면 된다 — AI가 아닌 기능에는 게터를 만들지 않는다.
// 게터가 없으면 실수로 게이트를 걸 수 없다. 도움말·트레이닝 낭독(사전 생성
// wav 재생), 가사 자동 맞춤·조성 감지·키 변주·보컬 줄이기·믹스·듀엣(전부
// ffmpeg), 유튜브 검색·다운로드, LRCLIB 가사는 AI가 아니다.
import '../models/prompter_settings.dart';

/// 진입점 표시 방식.
enum AiVisibility {
  /// 그대로 보인다.
  shown,

  /// 자리는 지키되 꺼짐을 글자로 알린다 — 고정 내비 탭처럼 공간 기준점이
  /// 되는 요소용. 사라지면 외운 배치가 흔들린다(저시력 사용자 실사용 근거).
  labeledOff,

  /// 화면에서 뺀다 — 형제가 많은 Wrap 안 액션 버튼처럼 기준점이 아닌 요소용.
  hidden,
}

class AiGate {
  final PrompterSettings settings;

  const AiGate(this.settings);

  /// 로컬 AI(보컬 분리·STT·음정 코치·작곡)를 지금 부를 수 있나.
  bool get local => settings.localAiActive;

  /// 클라우드 AI(DeepSeek 가사 검증)를 지금 부를 수 있나.
  bool get cloud => settings.cloudAiActive;

  /// 작곡 탭 — 라벨 병기(숨기지 않는다).
  AiVisibility get composeTab =>
      local ? AiVisibility.shown : AiVisibility.labeledOff;

  /// 프롬프터 조작판의 '가사 다시 생성'(STT).
  AiVisibility get sttLyricsButton =>
      local ? AiVisibility.shown : AiVisibility.hidden;

  /// 녹음 탭의 '음정 체크'.
  AiVisibility get pitchCheckButton =>
      local ? AiVisibility.shown : AiVisibility.hidden;

  /// 녹음 탭의 'AI 보정'.
  AiVisibility get correctButton =>
      local ? AiVisibility.shown : AiVisibility.hidden;

  /// 분리 서버 상태 칩 — 숨기면 폴링 타이머도 함께 멎는다.
  AiVisibility get separatorChip =>
      local ? AiVisibility.shown : AiVisibility.hidden;

  /// 가사 재생성 다이얼로그의 DeepSeek 검증 옵션 — 비AI 옵션과 섞여 있어
  /// 사라지면 "내가 켰던 게 왜 없지"가 된다. 사유를 붙여 비활성으로 둔다.
  AiVisibility get deepSeekOption =>
      cloud ? AiVisibility.shown : AiVisibility.labeledOff;

  /// 꺼져 있을 때 사용자에게 보여 줄 안내 문구.
  static const String offReason = '설정 > AI·작곡에서 AI 기능을 켜면 사용할 수 있습니다.';
}
