// file: lib/constants/voice_clips.dart
//
// 사전 생성 TTS 클립의 정본 — 앱은 id로 에셋을 재생하고,
// tool/gen_audio/generate_tts.dart 는 text를 읽어 female_calm 음성으로 굽는다.
// 같은 파일을 양쪽이 쓰므로 문구와 파일이 어긋날 수 없다.
//
// 문구를 고치면: 해당 wav 삭제 후 generate_tts.dart 재실행(또는 --force).
import 'app_shortcuts.dart';

/// TTS 클립 하나 — id가 곧 에셋 파일명(`assets/audio/tts/<id>.wav`).
class VoiceClip {
  final String id;
  final String text;

  const VoiceClip(this.id, this.text);
}

/// 앱의 모든 TTS 클립.
class VoiceClips {
  VoiceClips._();

  /// audioplayers AssetSource 경로(기본 프리픽스 assets/ 는 생략).
  static String assetPath(String id) => 'audio/tts/$id.wav';

  /// 루틴 스텝 안내 클립 id.
  static String stepClipId(String stepId) => 'step_$stepId';

  /// 코스 주차 브리핑 클립 id (1~4).
  static String courseWeekClipId(int weekNumber) => 'course_week$weekNumber';

  // ── 루틴 스텝 안내(17) — vocal_routine.dart 의 guide 를 낭독형으로 ──
  static const List<VoiceClip> _steps = [
    VoiceClip('step_mini10-breathing',
        '호흡, 3분. 복식호흡입니다. 코로 4박 들이마시고, 스 소리로 8박 내쉬기를 네 번 반복합니다. 음성 안내에 맞춰 따라해 보세요.'),
    VoiceClip('step_mini10-warmup',
        '워밍업, 3분. 허밍과 립트릴입니다. 편한 중음역에서 작게. 크게가 아니라 편하게 하는 게 중요해요.'),
    VoiceClip('step_mini10-scale',
        '스케일링, 2분. 사이렌 연습입니다. 낮은 음에서 높은 음까지 올렸다가 다시 내려오세요. 무리 없는 범위에서 부드럽게.'),
    VoiceClip('step_mini10-diction',
        '딕션, 2분. 다다다, 가가가를 빠르게 반복하고, 혀와 턱의 힘을 뺍니다. 간장공장 공장장을 두 번 말해 보세요.'),
    VoiceClip('step_short30-breathing',
        '호흡, 5분. 복식호흡입니다. 4박 들이마시고, 8박 동안 스 소리로 천천히 내쉬기를 네 번 반복합니다. 안내에 맞춰 따라해 보세요.'),
    VoiceClip('step_short30-warmup',
        '워밍업, 4분. 립트릴, 입술 털기와 허밍입니다. 편한 중음역에서 위아래로 부드럽게 움직여 보세요.'),
    VoiceClip('step_short30-scale',
        '스케일링, 5분. 5음 스케일, 마, 메, 미, 모, 무입니다. 피아노를 따라 무리하지 않는 범위에서 반음씩 올리고 내립니다.'),
    VoiceClip('step_short30-diction',
        '딕션, 3분. 레드 레더 옐로 레더, 그리고 다다다 가가가. 혀와 턱을 깨워 발음을 또렷하게 만듭니다.'),
    VoiceClip('step_short30-routine',
        '루틴곡, 7분. 편하게 부를 수 있는 곡으로 호흡과 발성을 적용해 보세요. 30초 이상 부르면 자동으로 체크됩니다.'),
    VoiceClip('step_short30-target',
        '목표곡, 6분. 도전 중인 곡입니다. 어려운 구간만 끊어서 반복해 보세요.'),
    VoiceClip('step_long60-breathing',
        '호흡, 8분. 복식호흡과 지속음입니다. 4박 들이마시고 8박 내쉬는 것부터 시작해, 점차 날숨을 12박까지 늘립니다.'),
    VoiceClip('step_long60-warmup',
        '워밍업, 7분. 립트릴, 허밍, 사이렌으로 성대를 천천히 깨웁니다.'),
    VoiceClip('step_long60-scale',
        '스케일링, 10분. 5음 스케일과 아르페지오입니다. 흉성, 믹스, 두성을 오가며 음역을 넓혀 보세요.'),
    VoiceClip('step_long60-diction',
        '딕션, 5분. 텅트위스터와 모음 연결입니다. 마, 메, 미, 모, 무를 가사처럼 이어 부르고, 자음은 짧고 또렷하게.'),
    VoiceClip('step_long60-routine',
        '루틴곡, 14분. 익숙한 곡으로 전체를 부르며 호흡 지점과 모음 처리를 점검해 보세요. 30초 이상 부르면 자동으로 체크됩니다.'),
    VoiceClip('step_long60-target',
        '목표곡, 13분. 목표곡에 집중합니다. 키를 바꿔 보며 편한 지점을 찾아도 좋아요.'),
    VoiceClip('step_long60-cooldown',
        '쿨다운, 3분. 가벼운 허밍으로 마무리합니다. 성대를 식혀 주세요.'),
  ];

  // ── 호흡 큐 ──
  static const List<VoiceClip> _breathing = [
    VoiceClip('breath_inhale', '들이쉬고.'),
    VoiceClip('breath_hold', '멈추고.'),
    VoiceClip('breath_exhale', '스, 하고 내쉬세요.'),
    VoiceClip('breath_again', '한 번 더.'),
    VoiceClip('breath_last', '마지막 한 번.'),
    VoiceClip('breath_done', '잘하셨어요.'),
  ];

  // ── 스케일 큐 ──
  static const List<VoiceClip> _scale = [
    VoiceClip('scale_intro_five', '피아노를 잘 듣고, 마, 메, 미, 모, 무로 따라 불러 보세요.'),
    VoiceClip('scale_intro_siren',
        '낮은 음에서 높은 음까지, 사이렌처럼 우 하고 부드럽게 올렸다가 내려 보세요.'),
    VoiceClip('scale_up', '반음 올라갑니다.'),
    VoiceClip('scale_down', '반음 내려갑니다.'),
    VoiceClip('scale_top', '가장 높은 음이에요. 이제 내려갑니다.'),
    VoiceClip('scale_done', '스케일 끝. 잘하셨어요.'),
  ];

  // ── 세션 진행 큐 ──
  static const List<VoiceClip> _session = [
    VoiceClip('session_start', '트레이닝을 시작합니다.'),
    VoiceClip('session_next', '다음 단계입니다.'),
    VoiceClip('session_step_done', '단계 완료. 자동으로 체크했어요.'),
    VoiceClip('session_half', '절반 지났습니다.'),
    VoiceClip('session_30s', '30초 남았습니다.'),
    VoiceClip('session_all_done', '오늘의 루틴을 모두 마쳤습니다. 수고하셨어요.'),
    VoiceClip('session_paused', '일시정지합니다.'),
    VoiceClip('session_resume', '다시 시작합니다.'),
    VoiceClip('session_skipped', '이 단계를 건너뜁니다.'),
    VoiceClip('session_restart_step', '이 단계를 처음부터 다시 시작합니다.'),
    VoiceClip('session_stopped', '트레이닝을 마칩니다.'),
  ];

  // ── 코스 주차 브리핑(4) — vocal_course.dart 의 theme/focus/tip 낭독형 ──
  static const List<VoiceClip> _course = [
    VoiceClip('course_week1',
        '1주차, 호흡과 지지. 복식호흡을 몸에 붙이는 주입니다. 루틴의 호흡 단계에 가장 정성을 들여 보세요. 어깨가 아니라 배가 움직여야 해요. 날숨을 조금씩 길게 늘려 봅시다.'),
    VoiceClip('course_week2',
        '2주차, 음정과 음역. 스케일과 사이렌에 집중하는 주입니다. 무리하지 않는 범위에서 반음씩 넓혀 보세요. 높은 음은 크게가 아니라 가볍게.'),
    VoiceClip('course_week3',
        '3주차, 딕션과 리듬. 가사가 또렷하게 들리는 주입니다. 딕션 단계와 박자 맞추기에 집중해 보세요. 혀와 턱의 힘 빼기가 절반이에요.'),
    VoiceClip('course_week4',
        '4주차, 곡 완성. 목표곡 통합 주입니다. 배운 것을 곡 하나에 전부 얹어 완성도를 올려 보세요. 어려운 구간만 끊어 반복한 뒤, 전체를 이어 부르세요.'),
  ];

  // ── 도움말 진입·마침 ──
  static const List<VoiceClip> _help = [
    VoiceClip('help_intro',
        '싱프롬터 단축키 안내입니다. 홈, 즐겨찾기, 전체화면에서 동작하며, 글자를 입력하는 중에는 꺼집니다.'),
    VoiceClip('help_training_intro', '트레이닝 따라하기 중에는 다음 키를 쓸 수 있어요.'),
    VoiceClip('help_done', '단축키 안내를 마칩니다.'),
  ];

  /// 전체 클립 — 단축키 항목별 클립은 app_shortcuts.dart 에서 자동 파생.
  static final List<VoiceClip> all = List.unmodifiable([
    ..._steps,
    ..._breathing,
    ..._scale,
    ..._session,
    ..._course,
    ..._help,
    for (final e in AppShortcuts.entries) VoiceClip(e.clipId, e.spokenText),
    for (final e in AppShortcuts.trainingEntries)
      VoiceClip(e.clipId, e.spokenText),
  ]);

  /// id로 클립을 찾는다. 없으면 null.
  static VoiceClip? byId(String id) {
    for (final clip in all) {
      if (clip.id == id) return clip;
    }
    return null;
  }
}
