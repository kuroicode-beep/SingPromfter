// file: lib/controllers/armed_transport.dart
//
// 녹음 고정 중의 스페이스가 **무엇을 할지**만 정하는 순수 부품.
//
// 화면(song_list_screen.dart)에서 떼어 낸 이유: 이 분기가 한 번 틀려서 「멈춘
// 화면에서 유령 녹음」이 돌았고(v5.15.x), 3000줄짜리 화면 안에 있으면 진리표로
// 고정할 수 없다. 프로세스·위젯·시계가 없으니 plain test()로 전 조합을 돈다.
//
// 설계: docs/architecture/설계_20260922_녹음고정_상시캡처세션_유미.md (3.3)
import 'package:flutter/foundation.dart';

/// 녹음 고정 중 스페이스 한 번의 처분.
enum ArmedSpaceAction {
  /// 앞선 스페이스의 재생·정지 호출이 아직 안 끝났다 — 버린다.
  ignore,

  /// 세션이 아직 마크를 못 받는다(여는 중·입력 점검 중). 재생도 걸지 않는다 —
  /// 음악만 나오고 녹음은 안 되는 조용한 실패를 막는다.
  refuseNotReady,

  /// 조각 시작: 마크를 찍고 같은 스택에서 재생을 건다.
  startTake,

  /// 조각 끝: 마크를 찍고 재생을 멈춘 뒤 저장을 줄에 올린다.
  endTake,

  /// 조각 없이 재생만 돌고 있다 — 그냥 멈춘다.
  pauseOnly,
}

/// 녹음 고정 중의 스페이스를 분류한다. (순수 함수 — 진리표 테스트 대상)
///
/// 🔴 분기의 기준은 [takeOpen]이다. `playing`은 네이티브 호출 **뒤**의 상태
/// 이벤트로 서는 거울이라 한 박자 늦다 — 그걸로 「시작이냐 정지냐」를 가르면
/// 재생 직후의 스페이스가 조각을 또 열거나, 멈춘 화면에서 녹음이 돈다.
/// [takeOpen]은 마크와 **같은 동기 스택**에서 뒤집히므로 어긋날 틈이 없다.
/// [playing]은 조각이 없을 때 「멈출 것이 있는가」를 볼 때만 쓴다.
ArmedSpaceAction armedSpaceAction({
  required bool busy,
  required bool sessionReady,
  required bool takeOpen,
  required bool playing,
}) {
  if (busy) return ArmedSpaceAction.ignore;
  // 열린 조각은 세션 상태와 무관하게 닫을 수 있어야 한다 — 부른 소리를 버리지 않는다.
  if (takeOpen) return ArmedSpaceAction.endTake;
  if (playing) return ArmedSpaceAction.pauseOnly;
  return sessionReady
      ? ArmedSpaceAction.startTake
      : ArmedSpaceAction.refuseNotReady;
}

/// 조각을 시작한 순간에 굳힌 컨텍스트. 저장은 한참 뒤(직렬 줄)에 돌기 때문에,
/// 그때의 화면 상태(다른 곡을 골랐을 수 있다)를 다시 읽으면 남의 곡에 붙는다.
///
/// JSON으로 오가는 이유: 세션 사이드카에 실려 나가, 앱이 죽어도 부팅 복구가
/// 「어느 곡의 조각이었는지」를 되찾는다. 그래서 JSON에 들어가는 값만 둔다.
@immutable
class ArmedTakeContext {
  const ArmedTakeContext({
    required this.songId,
    required this.songTitle,
    this.trackSlot,
    this.pitchSemitones = 0,
    this.activeAudioPath,
    this.tempoScale = 1.0,
  });

  final String songId;
  final String songTitle;

  /// 녹음할 때 물려 있던 반주 슬롯. 가사 전용 곡이면 null.
  final int? trackSlot;
  final int pitchSemitones;

  /// 그 순간 실제로 재생되던 파일(키·템포 변형본 포함) — 반주 조각을 여기서 자른다.
  final String? activeAudioPath;
  final double tempoScale;

  /// 어느 곡의 조각인지 모를 때 쓴다 — 소리는 버리지 않고 곡 없이 목록에 올린다.
  static const ArmedTakeContext unknown = ArmedTakeContext(
    songId: '',
    songTitle: '복구된 녹음',
  );

  /// [fromJson]이 못 읽으면 [unknown]으로 받는다(끊김·부팅 복구용).
  static ArmedTakeContext fromJsonOrUnknown(Map<String, Object?> json) =>
      fromJson(json) ?? unknown;

  /// 사이드카에 실을 맵. JSON으로 바로 나갈 수 있는 값만 담는다.
  Map<String, Object?> toJson() => {
    'songId': songId,
    'songTitle': songTitle,
    'trackSlot': trackSlot,
    'pitchSemitones': pitchSemitones,
    'activeAudioPath': activeAudioPath,
    'tempoScale': tempoScale,
  };

  /// 사이드카에서 되읽는다. 곡 id가 없으면 null — 어느 곡인지 모르는 조각이다.
  /// 나머지 값은 관대하게 읽는다(형이 어긋나면 기본값).
  static ArmedTakeContext? fromJson(Map<String, Object?> json) {
    final songId = json['songId'];
    if (songId is! String || songId.isEmpty) return null;
    final title = json['songTitle'];
    final slot = json['trackSlot'];
    final pitch = json['pitchSemitones'];
    final path = json['activeAudioPath'];
    final tempo = json['tempoScale'];
    return ArmedTakeContext(
      songId: songId,
      songTitle: title is String ? title : '',
      trackSlot: slot is num ? slot.toInt() : null,
      pitchSemitones: pitch is num ? pitch.toInt() : 0,
      activeAudioPath: path is String && path.isNotEmpty ? path : null,
      tempoScale: tempo is num && tempo > 0 ? tempo.toDouble() : 1.0,
    );
  }
}

/// 곡 위치(ms)를 `분:초`로. 조각을 알아보는 이름이 된다.
String formatSongPosition(int ms) {
  final total = (ms < 0 ? 0 : ms) ~/ 1000;
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// 고정 조각을 저장한 뒤의 안내 — 「조각 저장 — 1:23부터 2.4초」.
///
/// 사용자가 아는 숫자로 말한다: **스페이스를 누른 자리**와 **부른 길이**다.
/// 파일에는 그 앞에 리드인([leadInMs])이 붙어 있지만, 그건 저장 과정의 사정이라
/// 안내에서는 뺀다(파일 길이 [durationMs] − 리드인).
///
/// [truncated]·[filledGapMs]·[timelineSuspect]이면 한 줄씩 덧붙인다. 토스트는 새로
/// 뜨면 앞의 것을 지우므로 따로 띄우면 저장 안내가 안 보인다 — 한 장에 담는다.
String armedTakeSavedMessage({
  required int songPositionMs,
  required int leadInMs,
  required int durationMs,
  bool timelineSuspect = false,
  bool truncated = false,
  int filledGapMs = 0,
}) {
  final lead = leadInMs < 0 ? 0 : leadInMs;
  final contentMs = durationMs - lead < 0 ? 0 : durationMs - lead;
  final seconds = (contentMs / 1000).toStringAsFixed(1);
  final saved =
      '조각 저장 — ${formatSongPosition(songPositionMs + lead)}부터 $seconds초';
  final notes = [
    if (truncated) kArmedTruncatedNote,
    if (filledGapMs > 0) armedFilledGapNote(filledGapMs),
    if (timelineSuspect) kArmedTimelineSuspectNote,
  ];
  return notes.isEmpty ? saved : '$saved\n${notes.join('\n')}';
}

/// 개루프 좌표와 실측 좌표가 어긋났을 때 덧붙이는 안내(설계 3.5 — 표시만 한다).
const String kArmedTimelineSuspectNote = '이 조각은 곡 위치가 부정확할 수 있습니다';

/// 세션 파일이 덜 자라 조각의 끝이 계획보다 짧게 저장됐을 때 덧붙이는 안내.
/// 평소 토스트와 똑같이 뜨면 잘린 줄 모르고 넘어간다 — 그 자리에서 다시 받게 알린다.
const String kArmedTruncatedNote = '끝이 조금 잘렸을 수 있습니다 — 마이크가 잠깐 멈췄어요';

/// 조각 도중에 장치가 소리를 흘려(드롭) 그 자리를 무음으로 메웠을 때 덧붙이는 안내.
String armedFilledGapNote(int filledGapMs) =>
    '녹음 중 ${filledGapMs}ms가 끊겨 무음으로 메웠습니다';

/// 고정 스페이스에서 재생이 막혀 조각까지 취소했을 때의 안내.
///
/// 재생 쪽이 띄운 사유 토스트(「반주가 없어…」)만으로는 **녹음도 안 걸렸다**는 걸 알 수
/// 없다 — 예전(v5.15)에는 같은 조작으로 녹음이 걸렸다. 토스트는 새로 뜨면 앞의 것을
/// 지우므로 이 한 문장이 혼자서도 뜻이 통해야 한다.
const String kArmedPlaybackBlockedMessage =
    '반주를 재생할 수 없어 녹음도 시작하지 않았습니다 — 반주 없이 받으려면 R을 누르세요.';

/// Ctrl+R 가드에 남기는 사유 — 직전 시도가 목록에 못 올라간 까닭.
const String kTakeDroppedTooShortNote = '직전 조각은 너무 짧아 이미 버렸습니다';
const String kTakeDroppedSaveFailedNote = '직전 조각은 저장되지 않았습니다';
const String kRecordingDroppedTooShortNote = '직전 녹음은 너무 짧아 이미 버렸습니다';

/// Ctrl+R(직전 녹음 취소)이 **엉뚱한 테이크**를 물리지 않게 하는 가드.
///
/// Ctrl+R은 목록의 맨 앞을 물린다. 그런데 직전 시도가 목록에 못 올라갔으면(0.5초
/// 미만이라 버림·저장 실패) 맨 앞은 「그 앞의 멀쩡한 조각」이다 — 실수 조각을 지우려던
/// Ctrl+R이 멀쩡한 조각을 물리고, 6초 뒤 파일까지 지워진다.
///
/// 한 번만 막는다. 사용자가 정말 앞 조각을 물리려는 것이면 한 번 더 누르면 된다.
class LastTakeGuard {
  String? _dropNote;

  /// 직전 녹음 시도가 목록에 못 올라갔다. [reason]은 사용자에게 보일 사유다.
  void noteDropped(String reason) => _dropNote = reason;

  /// 새 테이크가 목록에 올라왔다 — 이제 목록의 맨 앞이 곧 「직전 녹음」이다.
  void noteCommitted() => _dropNote = null;

  /// Ctrl+R을 막아야 하면 안내 문구를 돌려주고 가드를 푼다. 막을 일이 없으면 null.
  String? consumeBlock() {
    final note = _dropNote;
    _dropNote = null;
    return note == null ? null : '$note — 취소할 것이 없습니다';
  }
}

/// 큰 경고(CenterAlert) 한 장의 글자.
typedef ArmedAlertText = ({String title, String detail});

/// 고정 세션이 죽어 고정을 껐을 때의 경고 글자. (순수 함수 — 테스트 대상)
///
/// 제목은 사유에 중립이다 — 이 길은 마이크 끊김뿐 아니라 45분 상한 도달·재기동한
/// 세션의 무음도 탄다. 저시력 사용자는 큰 제목부터 읽으므로, 제목이 「마이크가 끊겨」면
/// 마이크 고장으로 오해한다. 실제 사유는 [message]가 말한다.
/// 조각 줄도 완료형으로 쓰지 않는다 — 저장은 이 경고 **뒤에** 돈다.
ArmedAlertText armedSessionLostAlert({
  required String message,
  required bool hadOpenTake,
}) {
  return (
    title: '녹음 고정이 꺼졌습니다',
    detail:
        '$message\n\n'
        '${hadOpenTake ? '· 부르던 조각은 끊긴 데까지 저장하는 중입니다 — 결과는 곧 따로 알립니다\n' : ''}'
        '· Alt+R로 다시 켤 수 있습니다(마이크 연결을 먼저 확인해 주세요)\n'
        '· 설정 > 녹음에서 입력 장치가 그대로인지 보세요',
  );
}

/// 조각을 못 잘랐을 때의 경고 글자. (순수 함수 — 테스트 대상)
///
/// [lostMessage]가 있으면 「세션이 죽어 끊긴 데까지 살리던 조각」이다. 큰 경고는 한
/// 장뿐이라 이 경고가 끊김 경고를 덮는다 — 끊김 사유와 고정이 꺼졌다는 사실을
/// 여기에 다시 담아야 사용자가 놓치지 않는다.
ArmedAlertText armedSaveFailedAlert({
  required String reason,
  String? lostMessage,
}) {
  final lost = lostMessage != null;
  return (
    title: lost ? '녹음 고정이 꺼졌고, 조각도 저장하지 못했습니다' : '조각을 저장하지 못했습니다',
    detail:
        '${lost ? '$lostMessage\n\n' : ''}'
        '$reason\n\n'
        '· 부른 소리는 세션 파일에 그대로 남아 있습니다\n'
        '· 앱을 다시 켜면 이 조각을 「복구됨」으로 되살립니다\n'
        '· 디스크 공간과 녹음 폴더 쓰기 권한을 확인해 주세요'
        '${lost ? '\n· Alt+R로 고정을 다시 켜 주세요' : ''}',
  );
}
