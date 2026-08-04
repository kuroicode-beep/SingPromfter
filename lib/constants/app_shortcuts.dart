// file: lib/constants/app_shortcuts.dart
//
// 단축키 표의 정본 — 설정 탭 안내와 도움말 탭(텍스트+음성)이 함께 소비한다.
// 표시용(keys/description)과 낭독용(spokenKeys/spokenDescription)을 분리해
// 기호("←/→", ".bak")가 음성에서 자연스럽게 읽히게 한다.

/// 단축키 한 항목 — 표시 텍스트와 TTS 낭독 텍스트, 음성 클립 id.
class ShortcutHelpEntry {
  final String keys;
  final String description;

  /// 사전 생성 음성 클립 id (`assets/audio/tts/<clipId>.wav`).
  final String clipId;
  final String spokenKeys;
  final String spokenDescription;

  const ShortcutHelpEntry({
    required this.keys,
    required this.description,
    required this.clipId,
    required this.spokenKeys,
    required this.spokenDescription,
  });

  /// TTS 생성기가 쓰는 낭독 전문.
  String get spokenText => '$spokenKeys. $spokenDescription';
}

/// 앱 전체 단축키 목록.
class AppShortcuts {
  AppShortcuts._();

  /// 재생 화면(홈·즐겨찾기·전체화면) 단축키.
  static const List<ShortcutHelpEntry> entries = [
    ShortcutHelpEntry(
      keys: 'Space',
      description: '재생 / 일시정지',
      clipId: 'help_space',
      spokenKeys: '스페이스 바',
      spokenDescription: '재생하거나 일시정지합니다.',
    ),
    ShortcutHelpEntry(
      keys: 'F5',
      description: '전체화면 무대 열기',
      clipId: 'help_f5',
      spokenKeys: '에프 파이브',
      spokenDescription: '전체화면 무대를 엽니다.',
    ),
    ShortcutHelpEntry(
      keys: 'ESC',
      description: '무대 닫기',
      clipId: 'help_esc',
      spokenKeys: '이스케이프',
      spokenDescription: '무대를 닫습니다.',
    ),
    ShortcutHelpEntry(
      keys: 'R',
      description: '녹음 시작 / 중지',
      clipId: 'help_r',
      spokenKeys: '알',
      spokenDescription: '녹음을 시작하거나 중지합니다.',
    ),
    ShortcutHelpEntry(
      keys: '← / →',
      description: '가사 0.2초 늦추기 / 앞당기기 (꾹 누르면 연속)',
      clipId: 'help_arrows_lr',
      spokenKeys: '왼쪽, 오른쪽 화살표',
      spokenDescription: '가사를 0.2초 늦추거나 앞당깁니다. 꾹 누르면 연속으로 움직입니다.',
    ),
    ShortcutHelpEntry(
      keys: 'Ctrl+← / →',
      description: '가사 1초 늦추기 / 앞당기기',
      clipId: 'help_ctrl_arrows',
      spokenKeys: '컨트롤과 왼쪽, 오른쪽 화살표',
      spokenDescription: '가사를 1초 늦추거나 앞당깁니다.',
    ),
    ShortcutHelpEntry(
      keys: 'Alt+← / →',
      description: '다음 줄부터 아래만 보정 — 간주 뒤 어긋남용 (위는 그대로)',
      clipId: 'help_alt_arrows',
      spokenKeys: '알트와 왼쪽, 오른쪽 화살표',
      spokenDescription: '다음 줄부터 아래쪽 가사만 보정합니다. 간주 뒤에 가사가 어긋날 때 씁니다. 위쪽 줄은 그대로 둡니다.',
    ),
    ShortcutHelpEntry(
      keys: '[',
      description: '싱크 리셋 — 처음 상태로 (T와 같음)',
      clipId: 'help_bracket_open',
      spokenKeys: '여는 대괄호',
      spokenDescription: '가사 싱크를 처음 상태로 리셋합니다. 티 키와 같습니다.',
    ),
    ShortcutHelpEntry(
      keys: ']',
      description: '싱크 대기 — 가사를 멈췄다가, 나올 타이밍에 다시 누르면 그만큼 늦춰 이어감',
      clipId: 'help_bracket_close',
      spokenKeys: '닫는 대괄호',
      spokenDescription: '싱크 대기입니다. 가사를 멈췄다가, 가사가 나와야 할 타이밍에 다시 누르면 기다린 만큼 늦춰서 이어 갑니다.',
    ),
    ShortcutHelpEntry(
      keys: 'L',
      description: '싱크 잠금 토글 — 잠그면 싱크 조절 키가 전부 꺼진다',
      clipId: 'help_l',
      spokenKeys: '엘',
      spokenDescription: '싱크 잠금을 켜고 끕니다. 잠그면 싱크 조절 키가 전부 꺼집니다.',
    ),
    ShortcutHelpEntry(
      keys: '↑ / ↓',
      description: '이전 줄 / 다음 줄 (꾹 누르면 연속)',
      clipId: 'help_arrows_ud',
      spokenKeys: '위, 아래 화살표',
      spokenDescription: '이전 줄이나 다음 줄로 이동합니다. 꾹 누르면 연속으로 움직입니다.',
    ),
    ShortcutHelpEntry(
      keys: 'Shift+← / →',
      description: '30초 뒤로 / 앞으로 이동',
      clipId: 'help_shift_arrows_lr',
      spokenKeys: '시프트와 왼쪽, 오른쪽 화살표',
      spokenDescription: '30초 뒤로 가거나 앞으로 이동합니다.',
    ),
    ShortcutHelpEntry(
      keys: 'Shift+↑ / ↓',
      description: '볼륨',
      clipId: 'help_shift_arrows_ud',
      spokenKeys: '시프트와 위, 아래 화살표',
      spokenDescription: '볼륨을 키우거나 줄입니다.',
    ),
    ShortcutHelpEntry(
      keys: 'O / P',
      description: '이전 줄 / 다음 줄 (꾹 누르면 연속)',
      clipId: 'help_o_p',
      spokenKeys: '오와 피',
      spokenDescription: '이전 줄이나 다음 줄로 이동합니다. 꾹 누르면 연속으로 움직입니다.',
    ),
    ShortcutHelpEntry(
      keys: 'T',
      description: '가사 싱크를 원래대로 리셋',
      clipId: 'help_t',
      spokenKeys: '티',
      spokenDescription: '가사 싱크를 원래대로 리셋합니다.',
    ),
    ShortcutHelpEntry(
      keys: '. / /',
      description: '가사 0.2초 늦추기 / 앞당기기 (꾹 누르면 연속)',
      clipId: 'help_dot_slash',
      spokenKeys: '마침표와 슬래시',
      spokenDescription: '가사를 0.2초 늦추거나 앞당깁니다. 꾹 누르면 연속으로 움직입니다.',
    ),
    ShortcutHelpEntry(
      keys: 'E',
      description: '현재 가사 줄 편집 — ESC로 저장',
      clipId: 'help_e',
      spokenKeys: '이',
      spokenDescription: '현재 가사 줄을 편집합니다. 이스케이프 키로 저장합니다.',
    ),
    ShortcutHelpEntry(
      keys: 'D',
      description: '현재 가사 줄 삭제 — 곡 끝의 환청 줄 지우기 (원본 .bak 백업)',
      clipId: 'help_d',
      spokenKeys: '디',
      spokenDescription: '현재 가사 줄을 삭제합니다. 곡 끝의 잘못 들어간 줄을 지울 때 씁니다. 원본은 백 파일로 백업됩니다.',
    ),
    ShortcutHelpEntry(
      keys: 'F',
      description: '가사 편집 실행취소 — D 삭제·부분 보정·줄 편집을 되돌림 (20단계)',
      clipId: 'help_f',
      spokenKeys: '에프',
      spokenDescription: '가사 편집을 실행취소합니다. 줄 삭제, 부분 보정, 줄 편집을 최대 20단계까지 되돌립니다.',
    ),
    ShortcutHelpEntry(
      keys: 'G',
      description: '가사를 보관된 원본(.bak)으로 복구 — 확인창을 거침',
      clipId: 'help_g',
      spokenKeys: '지',
      spokenDescription: '가사를 보관된 원본으로 복구합니다. 확인창을 거칩니다.',
    ),
    ShortcutHelpEntry(
      keys: 'Home / End',
      description: '곡 처음 / 끝으로',
      clipId: 'help_home_end',
      spokenKeys: '홈과 엔드',
      spokenDescription: '곡의 처음이나 끝으로 이동합니다.',
    ),
    ShortcutHelpEntry(
      keys: '+ / -',
      description: '볼륨 키우기 / 줄이기',
      clipId: 'help_plus_minus',
      spokenKeys: '플러스와 마이너스',
      spokenDescription: '볼륨을 키우거나 줄입니다.',
    ),
    ShortcutHelpEntry(
      keys: 'PgUp / PgDn',
      description: '10초 뒤로 / 앞으로 이동',
      clipId: 'help_page_updown',
      spokenKeys: '페이지 업과 페이지 다운',
      spokenDescription: '10초 뒤로 가거나 앞으로 이동합니다.',
    ),
    ShortcutHelpEntry(
      keys: 'Ctrl+휠',
      description: '글자 크기',
      clipId: 'help_ctrl_wheel',
      spokenKeys: '컨트롤과 마우스 휠',
      spokenDescription: '글자 크기를 조절합니다.',
    ),
    ShortcutHelpEntry(
      keys: 'Alt+휠',
      description: '키(피치)',
      clipId: 'help_alt_wheel',
      spokenKeys: '알트와 마우스 휠',
      spokenDescription: '노래 키를 조절합니다.',
    ),
    ShortcutHelpEntry(
      keys: 'Shift+휠',
      description: '템포',
      clipId: 'help_shift_wheel',
      spokenKeys: '시프트와 마우스 휠',
      spokenDescription: '템포를 조절합니다.',
    ),
  ];

  /// 트레이닝 탭 전용 단축키(따라하기 세션 중에만).
  static const List<ShortcutHelpEntry> trainingEntries = [
    ShortcutHelpEntry(
      keys: 'Space',
      description: '따라하기 일시정지 / 재개',
      clipId: 'help_training_space',
      spokenKeys: '스페이스 바',
      spokenDescription: '트레이닝 따라하기를 일시정지하거나 다시 시작합니다.',
    ),
    ShortcutHelpEntry(
      keys: 'Home',
      description: '현재 섹션 처음부터 다시',
      clipId: 'help_training_home',
      spokenKeys: '홈',
      spokenDescription: '지금 하고 있는 섹션을 처음부터 다시 시작합니다.',
    ),
  ];
}
