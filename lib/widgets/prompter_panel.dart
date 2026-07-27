// file: lib/widgets/prompter_panel.dart
//
// 선택된 곡의 가사, 재생 컨트롤, 예약 큐를 함께 표시하는 패널.
import 'package:flutter/material.dart';

import '../controllers/playback_controller.dart';

import '../models/prompter_settings.dart';
import '../models/queue_item.dart';
import '../models/song.dart';
import '../theme/app_theme.dart';
import 'prompter_bottom_bar.dart';
import 'prompter_lyrics_view.dart';
import 'queue_panel.dart';

class PrompterPanel extends StatelessWidget {
  final Song? song;
  final List<Song> songs;
  final List<QueueItem> queue;
  final ScrollController lyricsScrollController;
  final int highlightLineIndex;
  final double fontSize;
  final double lineHeight;
  final String? fontFamily;
  final bool playing;
  final bool audioReady;
  final Duration duration;
  final PlaybackController playback;
  final bool hasSyncedLyrics;
  final int lyricsOffsetMs;
  final VoidCallback onFetchSyncedLyrics;
  final VoidCallback onImportLrcFile;
  final ValueChanged<int> onAdjustLyricsOffset;
  final int pitchSemitones;
  final ValueChanged<int> onAdjustPitch;
  final bool isRecording;
  final String recordingLevelLabel;
  final Duration recordingElapsed;
  final VoidCallback onToggleRecording;
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
  final bool showQueue;

  const PrompterPanel({
    super.key,
    required this.song,
    required this.songs,
    required this.queue,
    required this.lyricsScrollController,
    required this.highlightLineIndex,
    required this.fontSize,
    required this.lineHeight,
    required this.fontFamily,
    required this.playing,
    required this.audioReady,
    required this.duration,
    required this.playback,
    required this.hasSyncedLyrics,
    required this.lyricsOffsetMs,
    required this.onFetchSyncedLyrics,
    required this.onImportLrcFile,
    required this.onAdjustLyricsOffset,
    required this.pitchSemitones,
    required this.onAdjustPitch,
    required this.isRecording,
    required this.recordingLevelLabel,
    required this.recordingElapsed,
    required this.onToggleRecording,
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
    this.showQueue = true,
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
              decoration: AppShapes.panel(),
              child: PrompterLyricsView(
                lyricsText: currentSong.lyricsText,
                timedLyrics: playback.timedLyrics.value,
                displayMode: settings.displayMode,
                fontSize: fontSize,
                lineHeight: lineHeight,
                fontFamily: fontFamily,
                boldText: settings.boldText,
                highlightLineIndex: highlightLineIndex,
                scrollController: lyricsScrollController,
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
              ),
            ),
          ),
          PrompterBottomBar(
            song: currentSong,
            playing: playing,
            audioReady: audioReady,
            hasQueuedSongs: queue.isNotEmpty,
            duration: duration,
            playback: playback,
            hasSyncedLyrics: hasSyncedLyrics,
            lyricsOffsetMs: lyricsOffsetMs,
            onFetchSyncedLyrics: onFetchSyncedLyrics,
            onImportLrcFile: onImportLrcFile,
            onAdjustLyricsOffset: onAdjustLyricsOffset,
            pitchSemitones: pitchSemitones,
            onAdjustPitch: onAdjustPitch,
            isRecording: isRecording,
            recordingLevelLabel: recordingLevelLabel,
            recordingElapsed: recordingElapsed,
            onToggleRecording: onToggleRecording,
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
          if (showQueue && queue.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: QueuePanel(
                queue: queue,
                songs: songs,
                playingSongId: currentSong.id,
                playing: playing,
                onClear: onClearQueue,
                onReorder: onReorderQueue,
                onRemove: onRemoveQueueItem,
              ),
            )
          else if (showQueue)
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}
