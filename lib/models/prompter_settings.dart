import 'dart:convert';

import '../models/prompter_display_mode.dart';
import '../services/song_sort_service.dart';
import '../utils/pitch_math.dart';
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

  /// 곡 목록 폴더의 표시 순서. 여기 있는 이름은 곡이 없어도 폴더로 보인다
  /// (새 폴더를 만들고 나중에 곡을 담는 흐름). 곡에만 적힌 폴더는 뒤에 붙는다.
  final List<String> folderOrder;

  /// 펼쳐 둔 폴더 이름들 — 재실행해도 열림 상태가 유지된다.
  final List<String> expandedFolders;

  /// MR 내보내기 대상 폴더.
  final String exportFolder;
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
    this.folderOrder = const [],
    this.expandedFolders = const [],
    this.exportFolder = 'C:\\Downloads',
    this.tempoScaleBySong = const {},
    this.displayMode = PrompterDisplayMode.full,
    this.songSortMode = SongSortMode.title,
    this.queueSidebarOpen = true,
    this.playbackBarOpen = false,
    this.showEqMeter = true,
    this.showSyllableSweep = true,
    this.controlsDrawerOpen = false,
  });

  double get effectiveFontSizePt =>
      customFontSizePt ?? PrompterLevels.fontSizeForLevel(fontSizeLevel);

  double get effectiveLineHeight =>
      PrompterLevels.lineHeightForLevel(lineHeightLevel);

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
    List<String>? folderOrder,
    List<String>? expandedFolders,
    String? exportFolder,
    Map<String, double>? tempoScaleBySong,
    PrompterDisplayMode? displayMode,
    SongSortMode? songSortMode,
    bool? queueSidebarOpen,
    bool? playbackBarOpen,
    bool? showEqMeter,
    bool? showSyllableSweep,
    bool? controlsDrawerOpen,
    bool clearTrackSlot = false,
    bool clearCustomFontSize = false,
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
      pitchSemitonesBySong:
          pitchSemitonesBySong ?? this.pitchSemitonesBySong,
      trainingCourseStart: trainingCourseStart ?? this.trainingCourseStart,
      folderOrder: folderOrder ?? this.folderOrder,
      expandedFolders: expandedFolders ?? this.expandedFolders,
      exportFolder: exportFolder ?? this.exportFolder,
      tempoScaleBySong: tempoScaleBySong ?? this.tempoScaleBySong,
      displayMode: displayMode ?? this.displayMode,
      songSortMode: songSortMode ?? this.songSortMode,
      queueSidebarOpen: queueSidebarOpen ?? this.queueSidebarOpen,
      playbackBarOpen: playbackBarOpen ?? this.playbackBarOpen,
      showEqMeter: showEqMeter ?? this.showEqMeter,
      showSyllableSweep: showSyllableSweep ?? this.showSyllableSweep,
      controlsDrawerOpen: controlsDrawerOpen ?? this.controlsDrawerOpen,
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
    'folderOrder': folderOrder,
    'expandedFolders': expandedFolders,
    'exportFolder': exportFolder,
    'tempoScaleBySong': tempoScaleBySong,
    'displayMode': displayMode.storageValue,
    'songSortMode': songSortMode.storageValue,
    'queueSidebarOpen': queueSidebarOpen,
    'playbackBarOpen': playbackBarOpen,
    'showEqMeter': showEqMeter,
    'showSyllableSweep': showSyllableSweep,
    'controlsDrawerOpen': controlsDrawerOpen,
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
      folderOrder: (json['folderOrder'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const [],
      expandedFolders: (json['expandedFolders'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const [],
      exportFolder: (json['exportFolder'] as String?)?.trim().isNotEmpty == true
          ? (json['exportFolder'] as String).trim()
          : 'C:\\Downloads',
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
