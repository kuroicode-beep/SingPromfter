import 'dart:convert';

import '../models/prompter_display_mode.dart';
import '../theme/prompter_levels.dart';

class PrompterSettings {
  final double fontSizeLevel;
  final double lineHeightLevel;
  final double speedLevel;
  final double volume;
  final double playbackRate;
  final int? lastSelectedTrackSlot;
  final String fontFamily;
  final bool boldText;
  final double? customFontSizePt;
  final Map<String, int> lastSelectedTrackSlotBySong;

  /// 곡·슬롯별 키(원곡 대비 반음). 키는 `songId:slot` 형태다.
  /// 재생 취향이라 songs.json이 아니라 설정에 둔다(제목을 바꿔도 유지된다).
  final Map<String, int> pitchSemitonesBySong;
  final PrompterDisplayMode displayMode;

  const PrompterSettings({
    this.fontSizeLevel = 3,
    this.lineHeightLevel = 3,
    this.speedLevel = 2,
    this.volume = 1,
    this.playbackRate = 1,
    this.lastSelectedTrackSlot,
    this.fontFamily = '기본',
    this.boldText = false,
    this.customFontSizePt,
    this.lastSelectedTrackSlotBySong = const {},
    this.pitchSemitonesBySong = const {},
    this.displayMode = PrompterDisplayMode.full,
  });

  double get effectiveFontSizePt =>
      customFontSizePt ?? PrompterLevels.fontSizeForLevel(fontSizeLevel);

  double get effectiveLineHeight =>
      PrompterLevels.lineHeightForLevel(lineHeightLevel);

  PrompterSettings copyWith({
    double? fontSizeLevel,
    double? lineHeightLevel,
    double? speedLevel,
    double? volume,
    double? playbackRate,
    int? lastSelectedTrackSlot,
    String? fontFamily,
    bool? boldText,
    double? customFontSizePt,
    Map<String, int>? lastSelectedTrackSlotBySong,
    Map<String, int>? pitchSemitonesBySong,
    PrompterDisplayMode? displayMode,
    bool clearTrackSlot = false,
    bool clearCustomFontSize = false,
  }) {
    return PrompterSettings(
      fontSizeLevel: fontSizeLevel ?? this.fontSizeLevel,
      lineHeightLevel: lineHeightLevel ?? this.lineHeightLevel,
      speedLevel: speedLevel ?? this.speedLevel,
      volume: volume ?? this.volume,
      playbackRate: playbackRate ?? this.playbackRate,
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
      displayMode: displayMode ?? this.displayMode,
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
    'speedLevel': speedLevel,
    'volume': volume,
    'playbackRate': playbackRate,
    'lastSelectedTrackSlot': lastSelectedTrackSlot,
    'fontFamily': fontFamily,
    'boldText': boldText,
    'customFontSizePt': customFontSizePt,
    'lastSelectedTrackSlotBySong': lastSelectedTrackSlotBySong,
    'pitchSemitonesBySong': pitchSemitonesBySong,
    'displayMode': displayMode.storageValue,
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

    final bySong = readIntMap(json['lastSelectedTrackSlotBySong']);
    final pitchBySong = readIntMap(json['pitchSemitonesBySong']);

    return PrompterSettings(
      fontSizeLevel: (json['fontSizeLevel'] as num?)?.toDouble() ?? 3,
      lineHeightLevel: (json['lineHeightLevel'] as num?)?.toDouble() ?? 3,
      speedLevel: (json['speedLevel'] as num?)?.toDouble() ?? 2,
      volume: (json['volume'] as num?)?.toDouble() ?? 1,
      playbackRate: (json['playbackRate'] as num?)?.toDouble() ?? 1,
      lastSelectedTrackSlot: (json['lastSelectedTrackSlot'] as num?)?.toInt(),
      fontFamily: json['fontFamily'] as String? ?? '기본',
      boldText: json['boldText'] as bool? ?? false,
      customFontSizePt: (json['customFontSizePt'] as num?)?.toDouble(),
      lastSelectedTrackSlotBySong: bySong,
      pitchSemitonesBySong: pitchBySong,
      displayMode: PrompterDisplayModeCodec.fromStorage(
        json['displayMode'] as String?,
      ),
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
