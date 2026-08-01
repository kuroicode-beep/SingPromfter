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
import 'prompter_drawer.dart';
import '../theme/prompter_levels.dart';
import '../utils/pitch_math.dart';
import '../utils/tempo_label.dart';
import '../utils/music_key.dart';
import 'pitch_hud.dart';
import 'prompter_eq_meter.dart';
import 'prompter_line_list_view.dart' show LineEditRequest;
import 'prompter_lyrics_view.dart';
import 'prompter_sweep_line.dart';
import 'prompter_wheel_scope.dart';
import 'queue_panel.dart';
import 'recording_badge.dart';
import 'sync_lock_badge.dart';

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

  /// 원곡·MR 비교로 가사 싱크를 자동으로 맞춘다.
  final VoidCallback? onAutoAlignLyrics;

  /// 재생 중에 "지금이 첫 줄"을 지정한다(단축키 T).
  final VoidCallback? onAnchorFirstLine;

  /// AI 받아쓰기(STT)로 싱크 가사를 만든다. null이면 버튼을 감춘다.
  final VoidCallback? onSttLyrics;

  /// 가사 줄을 길게 눌러 고쳤을 때. null이면 편집 불가.
  final void Function(int index, String text)? onEditLyricsLine;

  /// 단축키(E)로 들어오는 인라인 편집 요청.
  final LineEditRequest? lineEditRequest;
  final int pitchSemitones;
  final ValueChanged<int> onAdjustPitch;

  /// 현재 반주의 템포(배)와 조절 콜백.
  final double tempoScale;
  final ValueChanged<double> onAdjustTempo;

  /// Alt+휠용 — 굴리는 동안은 화면만 바꾸고 렌더는 미루는 경로.
  /// 없으면 하단 바와 같은 즉시 적용 경로를 쓴다.
  final void Function(int delta)? onStepPitch;

  /// 적용을 기다리는 키 값. HUD가 이 값을 크게 띄운다.
  final ValueListenable<int?>? pendingPitch;

  /// 적용을 기다리는 템포 값. 키와 같은 카드로 띄운다.
  final ValueListenable<double?>? pendingTempo;

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

  /// 우상단에서 조작판으로 옮겨 온 곡 추가·서버 상태(v2.10.0).
  final VoidCallback? onAddSong;
  final Future<bool> Function()? onStartSeparator;

  /// 현재 반주 mp3를 다운로드 폴더로 복사.
  final VoidCallback? onExportTrack;
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
    this.onAutoAlignLyrics,
    this.onAnchorFirstLine,
    this.onSttLyrics,
    this.onEditLyricsLine,
    this.lineEditRequest,
    required this.pitchSemitones,
    required this.onAdjustPitch,
    this.tempoScale = 1,
    required this.onAdjustTempo,
    this.onStepPitch,
    this.pendingPitch,
    this.pendingTempo,
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
    this.onAddSong,
    this.onStartSeparator,
    this.onExportTrack,
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

    // 펼친 조작판이 가사 뷰를 통째로 밀어내지 못하게 패널 높이의 절반까지만
    // 준다. 조작판을 다 펼치면 300px이 넘어(실측: 바 전체 197→514) 좁은 창에서
    // 가사가 사라지고 아래가 잘렸다 — 손잡이를 눌렀는데 화면이 망가지니
    // "안 열린다"로 보인다. 남는 높이는 가사가 갖는다.
    return LayoutBuilder(
      builder: (context, constraints) => _build(
        context,
        currentSong,
        maxDrawerBodyHeight: constraints.maxHeight.isFinite
            ? drawerBodyBudget(constraints.maxHeight)
            : null,
      ),
    );
  }

  Widget _build(
    BuildContext context,
    Song currentSong, {
    required double? maxDrawerBodyHeight,
  }) {
    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          // 메인 창에서도 무대와 같은 조작을 쓴다 —
          // 휠=줄 이동, Ctrl+휠=글자 크기, Alt+휠=키.
          Expanded(
            child: PrompterWheelScope(
              onStepFontSize: _stepFontSize,
              onStepPitch: onStepPitch ?? onAdjustPitch,
              onStepTempo: (delta) => onAdjustTempo(delta * tempoStep),
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
                        onEditLine: onEditLyricsLine,
                        editRequest: lineEditRequest,
                      ),
                    ),
                    // 키·템포를 굴리는 동안 가사 위에 크게 띄운다.
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
                    if (pendingTempo != null)
                      Positioned.fill(
                        child: ValueListenableBuilder<double?>(
                          valueListenable: pendingTempo!,
                          builder: (context, value, _) => PitchHud(
                            semitones: value == null ? null : 0,
                            headline: value == null
                                ? null
                                : formatTempoLabel(value),
                            caption: '템포',
                          ),
                        ),
                      ),
                    // 싱크 잠금(L) 배지 — "눌렸는지 모르겠다"는 실사용 요청.
                    // 좌상단은 가사 첫 글자와 겹쳐 거슬린다는 피드백으로 우상단.
                    Positioned(
                      top: 10,
                      right: 10,
                      child: SyncLockBadge(locked: playback.syncLockedView),
                    ),
                    // 녹음 중(R) 배지 — 우하단.
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: RecordingBadge(recording: playback.recordingView),
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
            onAutoAlignLyrics: onAutoAlignLyrics,
            onAnchorFirstLine: onAnchorFirstLine,
            onSttLyrics: onSttLyrics,
            pitchSemitones: pitchSemitones,
            onAdjustPitch: onAdjustPitch,
            soundingKey: soundingKey,
            tempoScale: tempoScale,
            onAdjustTempo: onAdjustTempo,
            isRecording: isRecording,
            recordingLevelLabel: recordingLevelLabel,
            recordingElapsed: recordingElapsed,
            onToggleRecording: onToggleRecording,
            settings: settings,
            drawerOpen: settings.controlsDrawerOpen,
            onDrawerChanged: (open) =>
                onSettingsChanged(settings.copyWith(controlsDrawerOpen: open)),
            maxDrawerBodyHeight: maxDrawerBodyHeight,
            onStop: onStop,
            onTogglePlayPause: onTogglePlayPause,
            onRestart: onRestart,
            onSkipNext: onSkipNext,
            onOpenPrompter: () => onOpenPrompter(currentSong),
            onAddSong: onAddSong,
            onStartSeparator: onStartSeparator,
            onExportTrack: onExportTrack,
            onSeek: onSeek,
            onSettingsChanged: onSettingsChanged,
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
