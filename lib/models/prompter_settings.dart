import 'dart:convert';

class PrompterSettings {
  final double fontSizeLevel;
  final double lineHeightLevel;
  final double speedLevel;
  final double volume;
  final int? lastSelectedTrackSlot;
  final String fontFamily;
  final bool boldText;
  final Map<String, int> lastSelectedTrackSlotBySong;

  const PrompterSettings({
    this.fontSizeLevel = 3,
    this.lineHeightLevel = 3,
    this.speedLevel = 2,
    this.volume = 1,
    this.lastSelectedTrackSlot,
    this.fontFamily = '기본',
    this.boldText = false,
    this.lastSelectedTrackSlotBySong = const {},
  });

  PrompterSettings copyWith({
    double? fontSizeLevel,
    double? lineHeightLevel,
    double? speedLevel,
    double? volume,
    int? lastSelectedTrackSlot,
    String? fontFamily,
    bool? boldText,
    Map<String, int>? lastSelectedTrackSlotBySong,
    bool clearTrackSlot = false,
  }) {
    return PrompterSettings(
      fontSizeLevel: fontSizeLevel ?? this.fontSizeLevel,
      lineHeightLevel: lineHeightLevel ?? this.lineHeightLevel,
      speedLevel: speedLevel ?? this.speedLevel,
      volume: volume ?? this.volume,
      lastSelectedTrackSlot:
          clearTrackSlot ? null : (lastSelectedTrackSlot ?? this.lastSelectedTrackSlot),
      fontFamily: fontFamily ?? this.fontFamily,
      boldText: boldText ?? this.boldText,
      lastSelectedTrackSlotBySong:
          lastSelectedTrackSlotBySong ?? this.lastSelectedTrackSlotBySong,
    );
  }

  int? trackSlotForSong(String songId) => lastSelectedTrackSlotBySong[songId];

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
        'lastSelectedTrackSlot': lastSelectedTrackSlot,
        'fontFamily': fontFamily,
        'boldText': boldText,
        'lastSelectedTrackSlotBySong': lastSelectedTrackSlotBySong,
      };

  factory PrompterSettings.fromJson(Map<String, dynamic> json) {
    final rawMap = json['lastSelectedTrackSlotBySong'];
    final bySong = <String, int>{};
    if (rawMap is Map) {
      rawMap.forEach((key, value) {
        final parsed = (value as num?)?.toInt();
        if (parsed != null) {
          bySong['$key'] = parsed;
        }
      });
    }

    return PrompterSettings(
      fontSizeLevel: (json['fontSizeLevel'] as num?)?.toDouble() ?? 3,
      lineHeightLevel: (json['lineHeightLevel'] as num?)?.toDouble() ?? 3,
      speedLevel: (json['speedLevel'] as num?)?.toDouble() ?? 2,
      volume: (json['volume'] as num?)?.toDouble() ?? 1,
      lastSelectedTrackSlot: (json['lastSelectedTrackSlot'] as num?)?.toInt(),
      fontFamily: json['fontFamily'] as String? ?? '기본',
      boldText: json['boldText'] as bool? ?? false,
      lastSelectedTrackSlotBySong: bySong,
    );
  }

  static String encode(PrompterSettings settings) => jsonEncode(settings.toJson());

  static PrompterSettings decode(String raw) {
    return PrompterSettings.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
  }
}
