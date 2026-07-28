// file: lib/widgets/prompter_panel.dart
//
// 선택된 곡의 가사, 재생 컨트롤, 예약 큐를 함께 표시하는 패널.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../controllers/playback_controller.dart';

import '../models/prompter_settings.dart';
import '../models/queue_item.dart';
import '../models/song.dart';
import '../theme/app_theme.dart';
import 'prompter_bottom_bar.dart';
import '../theme/prompter_levels.dart';
import '../utils/music_key.dart';
import 'pitch_hud.dart';
import 'prompter_eq_meter.dart';
import 'prompter_lyrics_view.dart';
import 'prompter_sweep_line.dart';
import 'prompter_wheel_scope.dart';
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

  /// Alt+휠용 — 굴리는 동안은 화면만 바꾸고 렌더는 미루는 경로.
  /// 없으면 하단 바와 같은 즉시 적용 경로를 쓴다.
  final void Function(int delta)? onStepPitch;

  /// 적용을 기다리는 키 값. HUD가 이 값을 크게 띄운다.
  final ValueListenable<int?>? pendingPitch;

  /// 지금 들리는 조성. 하단 바 키 줄에 배지로 뜬다.
  final MusicKey? soundingKey;

  /// 사용자 키를 얹기 전의 슬롯 조성. HUD가 여기에 조절값을 더해 띄운다.
  final MusicKey? pitchBaseKey;
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
    this.onStepPitch,
    this.pendingPitch,
    this.soundingKey,
    this.pitchBaseKey,
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

  /// Ctrl+휠 글자 크기. 커스텀 pt가 잡혀 있으면 레벨로 환산한 뒤 옮긴다.
  void _stepFontSize(int delta) {
    final base = settings.customFontSizePt != null
        ? PrompterLevels.levelForFontSize(settings.customFontSizePt!)
        : settings.fontSizeLevel;
    final next = (base + delta).clamp(
      PrompterLevels.minLevel.toDouble(),
      PrompterLevels.maxLevel.toDouble(),
    );
    onSettingsChanged(
      settings.copyWith(fontSizeLevel: next, clearCustomFontSize: true),
    );
  }

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
          // 메인 창에서도 무대와 같은 조작을 쓴다 —
          // 휠=줄 이동, Ctrl+휠=글자 크기, Alt+휠=키.
          Expanded(
            child: PrompterWheelScope(
              onStepLine: playback.stepLine,
              onStepFontSize: _stepFontSize,
              onStepPitch: onStepPitch ?? onAdjustPitch,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                decoration: AppShapes.panel(),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    AnimatedBuilder(
                      animation: Listenable.merge([
                        playback.lineIndex,
                        playback.timedLyrics,
                        playback.autoScrollPaused,
                      ]),
                      builder: (context, _) => PrompterLyricsView(
                        lyricsText: currentSong.lyricsText,
                        timedLyrics: playback.timedLyrics.value,
                        displayMode: settings.displayMode,
                        fontSize: fontSize,
                        lineHeight: lineHeight,
                        fontFamily: fontFamily,
                        boldText: settings.boldText,
                        highlightLineIndex: playback.lineIndex.value,
                        scrollController: lyricsScrollController,
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                        onLineTap: playback.seekToLine,
                        autoFollow: !playback.autoScrollPaused.value,
                        trackEnd: playback.lyricsTrackEnd,
                        sweepBuilder: prompterSweepBuilder(
                          playback: playback,
                          enabled: settings.showSyllableSweep,
                        ),
                      ),
                    ),
                    // 키를 굴리는 동안 가사 위에 크게 띄운다.
                    if (pendingPitch != null)
                      Positioned.fill(
                        child: ValueListenableBuilder<int?>(
                          valueListenable: pendingPitch!,
                          builder: (context, value, _) => PitchHud(
                            semitones: value,
                            songKey: pitchBaseKey,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // EQ는 가사와 하단 바 사이의 형제 — 구조적으로 겹치지 않는다.
          if (settings.showEqMeter)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: LayoutBuilder(
                builder: (context, constraints) => SizedBox(
                  height: 56,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: (constraints.maxWidth * 0.45).clamp(
                        160.0,
                        420.0,
                      ),
                      child: PrompterEqMeter(playback: playback),
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
            duration: duration,
            playback: playback,
            hasSyncedLyrics: hasSyncedLyrics,
            lyricsOffsetMs: lyricsOffsetMs,
            onFetchSyncedLyrics: onFetchSyncedLyrics,
            onImportLrcFile: onImportLrcFile,
            onAdjustLyricsOffset: onAdjustLyricsOffset,
            pitchSemitones: pitchSemitones,
            onAdjustPitch: onAdjustPitch,
            soundingKey: soundingKey,
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
