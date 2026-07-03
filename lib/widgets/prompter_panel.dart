// file: lib/widgets/prompter_panel.dart
//
// 선택된 곡의 가사, 재생 컨트롤, 예약 큐를 함께 표시하는 패널.
import 'package:flutter/material.dart';

import '../models/prompter_settings.dart';
import '../models/queue_item.dart';
import '../models/song.dart';
import '../theme/app_theme.dart';
import 'prompter_bottom_bar.dart';
import 'queue_panel.dart';

class PrompterPanel extends StatelessWidget {
  final Song? song;
  final List<Song> songs;
  final List<QueueItem> queue;
  final ScrollController lyricsScrollController;
  final double fontSize;
  final double lineHeight;
  final String? fontFamily;
  final bool playing;
  final bool audioReady;
  final Duration position;
  final Duration duration;
  final PrompterSettings settings;
  final Map<String, String?> fontOptions;
  final VoidCallback onStop;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onRestart;
  final VoidCallback onSkipNext;
  final ValueChanged<Song> onOpenPrompter;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<PrompterSettings> onSettingsChanged;
  final VoidCallback onCustomFontSize;
  final ValueChanged<String> onAccessibilityPreset;
  final ValueChanged<String> onMessage;
  final VoidCallback onClearQueue;
  final void Function(int oldIndex, int newIndex) onReorderQueue;
  final ValueChanged<int> onRemoveQueueItem;

  const PrompterPanel({
    super.key,
    required this.song,
    required this.songs,
    required this.queue,
    required this.lyricsScrollController,
    required this.fontSize,
    required this.lineHeight,
    required this.fontFamily,
    required this.playing,
    required this.audioReady,
    required this.position,
    required this.duration,
    required this.settings,
    required this.fontOptions,
    required this.onStop,
    required this.onTogglePlayPause,
    required this.onRestart,
    required this.onSkipNext,
    required this.onOpenPrompter,
    required this.onSeek,
    required this.onSettingsChanged,
    required this.onCustomFontSize,
    required this.onAccessibilityPreset,
    required this.onMessage,
    required this.onClearQueue,
    required this.onReorderQueue,
    required this.onRemoveQueueItem,
  });

  @override
  Widget build(BuildContext context) {
    final currentSong = song;
    if (currentSong == null) {
      return const Center(
        child: Text(
          '곡을 선택해 주세요',
          style: TextStyle(color: AppColors.textMuted, fontSize: 18),
        ),
      );
    }

    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: SingleChildScrollView(
                controller: lyricsScrollController,
                child: Text(
                  currentSong.lyricsText.isEmpty
                      ? '(가사가 없습니다)'
                      : currentSong.lyricsText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: fontSize,
                    height: lineHeight,
                    fontFamily: fontFamily,
                    fontWeight: settings.boldText
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          PrompterBottomBar(
            song: currentSong,
            playing: playing,
            audioReady: audioReady,
            hasQueuedSongs: queue.isNotEmpty,
            position: position,
            duration: duration,
            settings: settings,
            fontOptions: fontOptions,
            onStop: onStop,
            onTogglePlayPause: onTogglePlayPause,
            onRestart: onRestart,
            onSkipNext: onSkipNext,
            onOpenPrompter: () => onOpenPrompter(currentSong),
            onSeek: onSeek,
            onSettingsChanged: onSettingsChanged,
            onCustomFontSize: onCustomFontSize,
            onAccessibilityPreset: onAccessibilityPreset,
            onMessage: onMessage,
          ),
          if (queue.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: QueuePanel(
                queue: queue,
                songs: songs,
                onClear: onClearQueue,
                onReorder: onReorderQueue,
                onRemove: onRemoveQueueItem,
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}
