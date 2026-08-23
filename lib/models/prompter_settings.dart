import 'dart:convert';

import '../models/prompter_display_mode.dart';
import '../services/song_sort_service.dart';
import '../utils/pitch_math.dart';
import '../utils/platform_capabilities.dart';
import '../theme/prompter_levels.dart';

class PrompterSettings {
  final double fontSizeLevel;
  final double lineHeightLevel;
  final double volume;
  final int? lastSelectedTrackSlot;
  final String fontFamily;
  final bool boldText;
  final double? customFontSizePt;
  final Map<String, int> lastSelectedTrackSlotBySong;

  /// 곡·슬롯별 템포(배). 키와 마찬가지로 곡별 연습 취향이지 전역 설정이 아니다.
  ///
  /// v2.8.0에서 playbackRate(전역 재생 배속)를 대체했다. 그건 Windows에서
  /// 음정을 끌고 올라가 연습 키가 틀어졌다 — 키를 오프라인으로 뺀 이유와 같다.
  final Map<String, double> tempoScaleBySong;

  /// 곡·슬롯별 키(원곡 대비 반음). 키는 `songId:slot` 형태다.
  /// 재생 취향이라 songs.json이 아니라 설정에 둔다(제목을 바꿔도 유지된다).
  final Map<String, int> pitchSemitonesBySong;

  /// 4주 보컬 코스 시작일(yyyy-MM-dd). null이면 코스 미시작.
  final String? trainingCourseStart;

  /// 트레이닝 스케일 음역('male'|'female'). 기본 남성 — 피아노 런 범위를 정한다.
  final String trainingVoiceRange;

  /// 프롬프터 우주 배경 단계(0=끄기, 1~5=패턴). 단축키 B가 순환시킨다.
  final int spaceBackgroundLevel;

  /// 곡 목록 폴더의 표시 순서. 여기 있는 이름은 곡이 없어도 폴더로 보인다
  /// (새 폴더를 만들고 나중에 곡을 담는 흐름). 곡에만 적힌 폴더는 뒤에 붙는다.
  final List<String> folderOrder;

  /// 펼쳐 둔 폴더 이름들 — 재실행해도 열림 상태가 유지된다.
  final List<String> expandedFolders;

  /// MR 내보내기 대상 폴더.
  final String exportFolder;

  /// 녹음 입력 장치(DirectShow 이름). null이면 첫 장치를 쓴다.
  final String? recordingDevice;
  final PrompterDisplayMode displayMode;

  /// 홈 곡 목록의 정렬. '내 순서(manual)'는 드래그로 바꾼 저장 순서를
  /// 그대로 쓴다 — 재실행해도 유지돼야 하므로 설정에 남긴다.
  final SongSortMode songSortMode;

  /// 예약 큐 사이드바 열림. 기본 열림 — 드로어 아이콘으로 여닫는다.
  final bool queueSidebarOpen;

  /// 하단 재생바(재생 버튼 줄+진행바) 열림. 기본 숨김 — 조작판처럼 드로어다.
  final bool playbackBarOpen;

  /// 전체화면 프롬프터의 EQ 애니메이션 표시 여부.
  /// 움직임이 신경 쓰이는 사용자를 위해 끌 수 있어야 한다(저시력 배려).
  final bool showEqMeter;

  /// 현재 줄을 한 글자씩 밝히며 따라갈지.
  /// 움직임이 신경 쓰이면 끌 수 있다(EQ 미터와 같은 이유).
  final bool showSyllableSweep;

  /// 하단 조작판을 펼쳐 둘지. 기본은 닫힘 — 가사 자리를 먼저 준다.
  final bool controlsDrawerOpen;

  /// 녹음 입력 볼륨(0.0~2.0). 캡처 시점에 파일에 구워진다.
  final double recordingGain;

  /// AI 기능 전체 마스터 스위치. 끄면 로컬·클라우드 구분 없이 AI가 전부 멈추고
  /// AI 없이 쓸 수 있는 기능만 화면에 남는다. 하위 두 스위치는 이것이 켜져
  /// 있을 때만 의미가 있다 — 호출부는 raw 필드가 아니라 아래 파생 게터를 읽는다.
  final bool aiEnabled;

  /// 로컬 AI 기능(보컬 분리·작곡·프롬프트 다듬기) 사용 여부. 기본 꺼짐 —
  /// SAW 서버가 없어도 앱이 온전하도록, 켤 때 설치 안내를 거친다.
  final bool localAiEnabled;

  /// 클라우드 AI 기능(DeepSeek 가사 검증) 사용 여부. 기본 꺼짐 —
  /// 가사 텍스트가 외부로 나가므로 로컬과 따로 관리한다.
  final bool cloudAiEnabled;

  /// 프롬프트 다듬기에 쓸 Ollama 모델 이름.
  final String ollamaModel;

  const PrompterSettings({
    this.fontSizeLevel = 3,
    this.lineHeightLevel = 3,
    this.volume = 1,
    this.lastSelectedTrackSlot,
    this.fontFamily = '기본',
    this.boldText = false,
    this.customFontSizePt,
    this.lastSelectedTrackSlotBySong = const {},
    this.pitchSemitonesBySong = const {},
    this.trainingCourseStart,
    this.trainingVoiceRange = 'male',
    this.spaceBackgroundLevel = 1,
    this.folderOrder = const [],
    this.expandedFolders = const [],
    this.exportFolder = 'C:\\Downloads',
    this.recordingDevice,
    this.tempoScaleBySong = const {},
    this.displayMode = PrompterDisplayMode.full,
    this.songSortMode = SongSortMode.title,
    this.queueSidebarOpen = true,
    this.playbackBarOpen = false,
    this.showEqMeter = true,
    this.showSyllableSweep = true,
    this.controlsDrawerOpen = false,
    this.recordingGain = 1.0,
    this.aiEnabled = false,
    this.localAiEnabled = false,
    this.cloudAiEnabled = false,
    this.ollamaModel = 'gemma4:12b',
  });

  double get effectiveFontSizePt =>
      customFontSizePt ?? PrompterLevels.fontSizeForLevel(fontSizeLevel);

  double get effectiveLineHeight =>
      PrompterLevels.lineHeightForLevel(lineHeightLevel);

  /// 로컬 AI가 실제로 동작하는 상태인가. 마스터가 꺼져 있으면 하위 스위치가
  /// 켜져 있어도 false다. 화면·컨트롤러·제어 API는 전부 이 게터만 읽는다.
  ///
  /// 모바일에서는 설정과 무관하게 false다 — 폰의 127.0.0.1에는 PC의 SAW
  /// 서버가 없다. PC 설정을 백업으로 옮겨 와도 켜지지 않아야 한다.
  bool get localAiActive =>
      aiEnabled && localAiEnabled && PlatformCapabilities.hasLocalAi;

  /// 클라우드 AI(DeepSeek)가 실제로 동작하는 상태인가.
  bool get cloudAiActive => aiEnabled && cloudAiEnabled;

  PrompterSettings copyWith({
    double? fontSizeLevel,
    double? lineHeightLevel,
    double? volume,
    int? lastSelectedTrackSlot,
    String? fontFamily,
    bool? boldText,
    double? customFontSizePt,
    Map<String, int>? lastSelectedTrackSlotBySong,
    Map<String, int>? pitchSemitonesBySong,
    String? trainingCourseStart,
    String? trainingVoiceRange,
    int? spaceBackgroundLevel,
    List<String>? folderOrder,
    List<String>? expandedFolders,
    String? exportFolder,
    String? recordingDevice,
    Map<String, double>? tempoScaleBySong,
    PrompterDisplayMode? displayMode,
    SongSortMode? songSortMode,
    bool? queueSidebarOpen,
    bool? playbackBarOpen,
    bool? showEqMeter,
    bool? showSyllableSweep,
    bool? controlsDrawerOpen,
    double? recordingGain,
    bool? aiEnabled,
    bool? localAiEnabled,
    bool? cloudAiEnabled,
    String? ollamaModel,
    bool clearTrackSlot = false,
    bool clearCustomFontSize = false,
    bool clearRecordingDevice = false,
  }) {
    return PrompterSettings(
      fontSizeLevel: fontSizeLevel ?? this.fontSizeLevel,
      lineHeightLevel: lineHeightLevel ?? this.lineHeightLevel,
      volume: volume ?? this.volume,
      lastSelectedTrackSlot: clearTrackSlot
          ? null
          : (lastSelectedTrackSlot ?? this.lastSelectedTrackSlot),
      fontFamily: fontFamily ?? this.fontFamily,
      boldText: boldText ?? this.boldText,
      customFontSizePt: clearCustomFontSize
          ? null
          : (customFontSizePt ?? this.customFontSizePt),
      lastSelectedTrackSlotBySong:
          lastSelectedTrackSlotBySong ?? this.lastSelectedTrackSlotBySong,
      pitchSemitonesBySong: pitchSemitonesBySong ?? this.pitchSemitonesBySong,
      trainingCourseStart: trainingCourseStart ?? this.trainingCourseStart,
      trainingVoiceRange: trainingVoiceRange ?? this.trainingVoiceRange,
      spaceBackgroundLevel: spaceBackgroundLevel ?? this.spaceBackgroundLevel,
      folderOrder: folderOrder ?? this.folderOrder,
      expandedFolders: expandedFolders ?? this.expandedFolders,
      exportFolder: exportFolder ?? this.exportFolder,
      recordingDevice: clearRecordingDevice
          ? null
          : (recordingDevice ?? this.recordingDevice),
      tempoScaleBySong: tempoScaleBySong ?? this.tempoScaleBySong,
      displayMode: displayMode ?? this.displayMode,
      songSortMode: songSortMode ?? this.songSortMode,
      queueSidebarOpen: queueSidebarOpen ?? this.queueSidebarOpen,
      playbackBarOpen: playbackBarOpen ?? this.playbackBarOpen,
      showEqMeter: showEqMeter ?? this.showEqMeter,
      showSyllableSweep: showSyllableSweep ?? this.showSyllableSweep,
      controlsDrawerOpen: controlsDrawerOpen ?? this.controlsDrawerOpen,
      recordingGain: recordingGain ?? this.recordingGain,
      aiEnabled: aiEnabled ?? this.aiEnabled,
      localAiEnabled: localAiEnabled ?? this.localAiEnabled,
      cloudAiEnabled: cloudAiEnabled ?? this.cloudAiEnabled,
      ollamaModel: ollamaModel ?? this.ollamaModel,
    );
  }

  int? trackSlotForSong(String songId) => lastSelectedTrackSlotBySong[songId];

  static String pitchKey(String songId, int slot) => '$songId:$slot';

  int pitchForSong(String songId, int? slot) {
    if (slot == null) return 0;
    return pitchSemitonesBySong[pitchKey(songId, slot)] ?? 0;
  }

  PrompterSettings withSongPitch(String songId, int slot, int semitones) {
    final next = Map<String, int>.from(pitchSemitonesBySong);
    if (semitones == 0) {
      next.remove(pitchKey(songId, slot));
    } else {
      next[pitchKey(songId, slot)] = semitones;
    }
    return copyWith(pitchSemitonesBySong: next);
  }

  /// 곡·슬롯의 템포(배). 지정이 없으면 1.0(원속도).
  double tempoForSong(String songId, int? slot) {
    if (slot == null) return 1;
    return tempoScaleBySong[pitchKey(songId, slot)] ?? 1;
  }

  /// 템포를 바꾼 설정. 1.0이면 항목을 지워 저장 파일이 불어나지 않게 한다.
  PrompterSettings withSongTempo(String songId, int slot, double scale) {
    final next = Map<String, double>.from(tempoScaleBySong);
    if (isDefaultTempo(scale)) {
      next.remove(pitchKey(songId, slot));
    } else {
      next[pitchKey(songId, slot)] = quantizeTempo(scale);
    }
    return copyWith(tempoScaleBySong: next);
  }

  PrompterSettings withSongTrackSlot(String songId, int slot) {
    final next = Map<String, int>.from(lastSelectedTrackSlotBySong);
    next[songId] = slot;
    return copyWith(
      lastSelectedTrackSlot: slot,
      lastSelectedTrackSlotBySong: next,
    );
  }

  Map<String, dynamic> toJson() => {
    'fontSizeLevel': fontSizeLevel,
    'lineHeightLevel': lineHeightLevel,
    'volume': volume,
    'lastSelectedTrackSlot': lastSelectedTrackSlot,
    'fontFamily': fontFamily,
    'boldText': boldText,
    'customFontSizePt': customFontSizePt,
    'lastSelectedTrackSlotBySong': lastSelectedTrackSlotBySong,
    'pitchSemitonesBySong': pitchSemitonesBySong,
    'trainingCourseStart': trainingCourseStart,
    'trainingVoiceRange': trainingVoiceRange,
    'spaceBackgroundLevel': spaceBackgroundLevel,
    'folderOrder': folderOrder,
    'expandedFolders': expandedFolders,
    'exportFolder': exportFolder,
    'recordingDevice': recordingDevice,
    'tempoScaleBySong': tempoScaleBySong,
    'displayMode': displayMode.storageValue,
    'songSortMode': songSortMode.storageValue,
    'queueSidebarOpen': queueSidebarOpen,
    'playbackBarOpen': playbackBarOpen,
    'showEqMeter': showEqMeter,
    'showSyllableSweep': showSyllableSweep,
    'controlsDrawerOpen': controlsDrawerOpen,
    'recordingGain': recordingGain,
    'aiEnabled': aiEnabled,
    'localAiEnabled': localAiEnabled,
    'cloudAiEnabled': cloudAiEnabled,
    'ollamaModel': ollamaModel,
  };

  factory PrompterSettings.fromJson(Map<String, dynamic> json) {
    Map<String, int> readIntMap(Object? raw) {
      final result = <String, int>{};
      if (raw is Map) {
        raw.forEach((key, value) {
          final parsed = (value as num?)?.toInt();
          if (parsed != null) result['$key'] = parsed;
        });
      }
      return result;
    }

    Map<String, double> readDoubleMap(Object? raw) {
      final result = <String, double>{};
      if (raw is Map) {
        raw.forEach((key, value) {
          final parsed = (value as num?)?.toDouble();
          if (parsed != null) result['$key'] = parsed;
        });
      }
      return result;
    }

    final bySong = readIntMap(json['lastSelectedTrackSlotBySong']);
    final pitchBySong = readIntMap(json['pitchSemitonesBySong']);

    return PrompterSettings(
      fontSizeLevel: (json['fontSizeLevel'] as num?)?.toDouble() ?? 3,
      lineHeightLevel: (json['lineHeightLevel'] as num?)?.toDouble() ?? 3,
      volume: (json['volume'] as num?)?.toDouble() ?? 1,
      lastSelectedTrackSlot: (json['lastSelectedTrackSlot'] as num?)?.toInt(),
      fontFamily: json['fontFamily'] as String? ?? '기본',
      boldText: json['boldText'] as bool? ?? false,
      customFontSizePt: (json['customFontSizePt'] as num?)?.toDouble(),
      lastSelectedTrackSlotBySong: bySong,
      pitchSemitonesBySong: pitchBySong,
      trainingCourseStart: json['trainingCourseStart'] as String?,
      trainingVoiceRange: json['trainingVoiceRange'] as String? ?? 'male',
      // v4.1의 bool(spaceBackground)에서 이관 — false만 끄기로 존중한다.
      spaceBackgroundLevel:
          (json['spaceBackgroundLevel'] as num?)?.toInt() ??
          (json['spaceBackground'] == false ? 0 : 1),
      folderOrder:
          (json['folderOrder'] as List?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const [],
      expandedFolders:
          (json['expandedFolders'] as List?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const [],
      exportFolder: (json['exportFolder'] as String?)?.trim().isNotEmpty == true
          ? (json['exportFolder'] as String).trim()
          : 'C:\\Downloads',
      // recordingDeviceName은 v3.0.0(작곡 라인)의 옛 키 — 폴백으로 흡수한다.
      recordingDevice:
          json['recordingDevice'] as String? ??
          json['recordingDeviceName'] as String?,
      tempoScaleBySong: readDoubleMap(json['tempoScaleBySong']),
      queueSidebarOpen: json['queueSidebarOpen'] as bool? ?? true,
      playbackBarOpen: json['playbackBarOpen'] as bool? ?? false,
      songSortMode: SongSortModeInfo.fromStorage(
        json['songSortMode'] as String?,
      ),
      displayMode: PrompterDisplayModeCodec.fromStorage(
        json['displayMode'] as String?,
      ),
      showEqMeter: json['showEqMeter'] as bool? ?? true,
      showSyllableSweep: json['showSyllableSweep'] as bool? ?? true,
      controlsDrawerOpen: json['controlsDrawerOpen'] as bool? ?? false,
      recordingGain: ((json['recordingGain'] as num?)?.toDouble() ?? 1.0).clamp(
        0.0,
        2.0,
      ),
      // 마스터 스위치는 v5.6.0 신설. 옛 설정에는 키가 없으므로 하위 둘 중
      // 하나라도 켜져 있었으면 켜진 것으로 승계한다 — 업데이트했더니 AI가
      // 통째로 사라지는 사고를 막는 지점이다.
      aiEnabled:
          json['aiEnabled'] as bool? ??
          (json['localAiEnabled'] == true || json['cloudAiEnabled'] == true),
      localAiEnabled: json['localAiEnabled'] as bool? ?? false,
      cloudAiEnabled: json['cloudAiEnabled'] as bool? ?? false,
      ollamaModel: (json['ollamaModel'] as String?)?.trim().isNotEmpty == true
          ? (json['ollamaModel'] as String).trim()
          : 'gemma4:12b',
    );
  }

  static String encode(PrompterSettings settings) =>
      jsonEncode(settings.toJson());

  static PrompterSettings decode(String raw) {
    return PrompterSettings.fromJson(
      (jsonDecode(raw) as Map).cast<String, dynamic>(),
    );
  }
}
