// file: lib/widgets/prompter_bottom_bar.dart
//
// 메인 화면 하단 재생 바(항상 표시) + 표시 설정(접이식).
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../controllers/playback_controller.dart';
import '../models/prompter_display_mode.dart';
import '../models/prompter_settings.dart';
import '../models/song.dart';
import '../theme/app_theme.dart';
import '../utils/key_label.dart';
import '../utils/pitch_math.dart';
import '../utils/tempo_label.dart';
import '../utils/music_key.dart';
import 'compact_btn.dart';
import 'mini_slider.dart';
import 'preset_btn.dart';
import 'prompter_progress_bar.dart';

class PrompterBottomBar extends StatefulWidget {
  final Song song;
  final bool playing;
  final bool audioReady;
  final bool hasQueuedSongs;
  final Duration duration;
  final PlaybackController playback;
  final PrompterSettings settings;
  final Map<String, String?> fontOptions;
  final VoidCallback onStop;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onRestart;
  final VoidCallback onSkipNext;
  final VoidCallback onOpenPrompter;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<PrompterSettings> onSettingsChanged;
  final VoidCallback onCustomFontSize;
  final ValueChanged<String> onAccessibilityPreset;
  final ValueChanged<String> onMessage;
  final bool hasSyncedLyrics;
  final int lyricsOffsetMs;
  final VoidCallback onFetchSyncedLyrics;
  final VoidCallback onImportLrcFile;
  final ValueChanged<int> onAdjustLyricsOffset;
  final int pitchSemitones;
  final ValueChanged<int> onAdjustPitch;

  /// 곡 조성에 구운 키·사용자 키를 얹은 '지금 들리는' 조성.
  final MusicKey? soundingKey;

  /// 현재 반주의 템포(배). 1.0이면 원속도.
  final double tempoScale;

  /// 템포를 한 칸씩 민다. 렌더는 손을 멈춘 뒤 한 번만 돈다.
  final ValueChanged<double> onAdjustTempo;
  final bool isRecording;
  final String recordingLevelLabel;
  final Duration recordingElapsed;
  final VoidCallback onToggleRecording;

  const PrompterBottomBar({
    super.key,
    required this.song,
    required this.playing,
    required this.audioReady,
    required this.hasQueuedSongs,
    required this.duration,
    required this.playback,
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
    required this.hasSyncedLyrics,
    required this.lyricsOffsetMs,
    required this.onFetchSyncedLyrics,
    required this.onImportLrcFile,
    required this.onAdjustLyricsOffset,
    required this.pitchSemitones,
    required this.onAdjustPitch,
    this.soundingKey,
    this.tempoScale = 1,
    required this.onAdjustTempo,
    required this.isRecording,
    required this.recordingLevelLabel,
    required this.recordingElapsed,
    required this.onToggleRecording,
  });

  @override
  State<PrompterBottomBar> createState() => _PrompterBottomBarState();
}

class _PrompterBottomBarState extends State<PrompterBottomBar> {
  bool _displaySettingsExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: AppShapes.panel(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CompactBtn(
                icon: Icons.stop,
                semanticsLabel: '정지',
                onTap: widget.onStop,
              ),
              const SizedBox(width: 6),
              CompactBtn(
                icon: widget.playing ? Icons.pause : Icons.play_arrow,
                semanticsLabel: widget.playing ? '일시정지' : '재생',
                toggled: widget.playing,
                onTap: widget.onTogglePlayPause,
                highlighted: true,
              ),
              const SizedBox(width: 6),
              CompactBtn(
                icon: Icons.replay,
                semanticsLabel: '처음부터 재생',
                onTap: widget.onRestart,
              ),
              const SizedBox(width: 6),
              CompactBtn(
                icon: Icons.skip_next,
                semanticsLabel: '다음 예약곡',
                onTap: () {
                  if (!widget.hasQueuedSongs) {
                    widget.onMessage('다음 예약곡이 없습니다.');
                    return;
                  }
                  widget.onSkipNext();
                },
              ),
              const SizedBox(width: 6),
              CompactBtn(
                icon: Icons.fullscreen,
                semanticsLabel: '전체화면 프롬프터 열기',
                onTap: widget.onOpenPrompter,
              ),
              const SizedBox(width: 6),
              CompactBtn(
                icon: widget.isRecording ? Icons.stop_circle : Icons.mic,
                semanticsLabel: widget.isRecording ? '녹음 정지' : '녹음 시작',
                toggled: widget.isRecording,
                onTap: widget.onToggleRecording,
              ),
              if (widget.isRecording) ...[
                const SizedBox(width: 10),
                // 녹음 상태는 색이 아니라 글자로 알린다.
                Text('● 녹음 중', style: AppTypography.emphasis),
                const SizedBox(width: 8),
                Text(
                  _formatElapsed(widget.recordingElapsed),
                  style: AppTypography.mono,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.recordingLevelLabel,
                  style: AppTypography.bodyMuted,
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // 위치만 별도 구독해, 60Hz 갱신이 화면 전체를 리빌드하지 않게 한다.
          ValueListenableBuilder<Duration>(
            valueListenable: widget.playback.position,
            builder: (context, position, _) => PrompterProgressBar(
              position: position,
              duration: widget.duration,
              enabled: widget.audioReady,
              onSeek: widget.onSeek,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: MiniSlider(
                  label: '볼륨',
                  value: widget.settings.volume,
                  min: 0,
                  max: 1,
                  divisions: 10,
                  step: 0.1,
                  onChanged: (v) => widget.onSettingsChanged(
                    widget.settings.copyWith(volume: v),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _TempoRow(scale: widget.tempoScale, onAdjust: widget.onAdjustTempo),
          const Divider(height: 16, thickness: 1),
          Semantics(
            label: '표시 설정',
            button: true,
            expanded: _displaySettingsExpanded,
            child: InkWell(
              onTap: () => setState(
                () => _displaySettingsExpanded = !_displaySettingsExpanded,
              ),
              borderRadius: AppShapes.controlRadius,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Text('표시 설정', style: AppTypography.body),
                    const Spacer(),
                    Icon(
                      _displaySettingsExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_displaySettingsExpanded) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: MiniSlider(
                    label: '크기',
                    value: widget.settings.fontSizeLevel,
                    min: 1,
                    max: 7,
                    divisions: 6,
                    semanticValue:
                        '현재 ${widget.settings.effectiveFontSizePt.round()} 포인트',
                    onChanged: (v) => widget.onSettingsChanged(
                      widget.settings.copyWith(
                        fontSizeLevel: v,
                        clearCustomFontSize: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MiniSlider(
                    label: '줄간격',
                    value: widget.settings.lineHeightLevel,
                    min: 1,
                    max: 7,
                    divisions: 6,
                    onChanged: (v) => widget.onSettingsChanged(
                      widget.settings.copyWith(lineHeightLevel: v),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PresetBtn(
                  label: widget.settings.customFontSizePt == null
                      ? '직접'
                      : '${widget.settings.customFontSizePt!.round()}pt',
                  semanticsLabel: '사용자 정의 글자 크기',
                  onTap: widget.onCustomFontSize,
                ),
                PresetBtn(
                  label: '표준',
                  semanticsLabel: '표준 접근성 프리셋',
                  onTap: () => widget.onAccessibilityPreset('standard'),
                ),
                PresetBtn(
                  label: '저시력',
                  semanticsLabel: '저시력 추천 프리셋',
                  onTap: () => widget.onAccessibilityPreset('recommended'),
                ),
                PresetBtn(
                  label: '원거리',
                  semanticsLabel: '원거리 무대 프리셋',
                  onTap: () => widget.onAccessibilityPreset('stage'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: widget.fontOptions.containsKey(widget.settings.fontFamily)
                        ? widget.settings.fontFamily
                        : 'System Default',
                    dropdownColor: AppColors.surface,
                    style: AppTypography.body,
                    items: widget.fontOptions.keys
                        .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                        .toList(growable: false),
                    onChanged: (v) {
                      if (v == null) return;
                      widget.onSettingsChanged(
                        widget.settings.copyWith(fontFamily: v),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  label: '굵은 글씨',
                  checked: widget.settings.boldText,
                  child: SizedBox(
                    width: AppConstants.minTouchTarget,
                    height: AppConstants.minTouchTarget,
                    child: Checkbox(
                      value: widget.settings.boldText,
                      onChanged: (v) => widget.onSettingsChanged(
                        widget.settings.copyWith(boldText: v ?? false),
                      ),
                    ),
                  ),
                ),
                Text('굵게', style: AppTypography.body),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<PrompterDisplayMode>(
                    isExpanded: true,
                    value: widget.settings.displayMode,
                    dropdownColor: AppColors.surface,
                    style: AppTypography.body,
                    items: PrompterDisplayMode.values
                        .map(
                          (mode) => DropdownMenuItem(
                            value: mode,
                            child: Text(mode.label),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (mode) {
                      if (mode == null) return;
                      widget.onSettingsChanged(
                        widget.settings.copyWith(displayMode: mode),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 4),
                const Tooltip(
                  message: '줄 하이라이트는 재생 위치 기준 추정, 싱크 가사는 실제 타임스탬프로 이동합니다.',
                  child: Icon(
                    Icons.info_outline,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _PitchRow(
              semitones: widget.pitchSemitones,
              onAdjust: widget.onAdjustPitch,
              soundingKey: widget.soundingKey,
            ),
            const SizedBox(height: 8),
            _SyncedLyricsRow(
              hasSyncedLyrics: widget.hasSyncedLyrics,
              offsetMs: widget.lyricsOffsetMs,
              onFetch: widget.onFetchSyncedLyrics,
              onImportFile: widget.onImportLrcFile,
              onAdjust: widget.onAdjustLyricsOffset,
            ),
          ],
        ],
      ),
    );
  }
}


/// 싱크 가사 가져오기 + 선행/지연 오프셋 조절.
/// 슬라이더 대신 큰 -/+ 버튼을 쓰고 현재 값을 모노 숫자로 함께 보여준다.
class _SyncedLyricsRow extends StatelessWidget {
  final bool hasSyncedLyrics;
  final int offsetMs;
  final VoidCallback onFetch;
  final VoidCallback onImportFile;
  final ValueChanged<int> onAdjust;

  const _SyncedLyricsRow({
    required this.hasSyncedLyrics,
    required this.offsetMs,
    required this.onFetch,
    required this.onImportFile,
    required this.onAdjust,
  });

  /// 음수는 가사를 먼저 띄운다는 뜻이라 사용자 표현도 '먼저'로 쓴다.
  static String formatOffset(int ms) {
    if (ms == 0) return '동시';
    final seconds = (ms.abs() / 1000).toStringAsFixed(1);
    return ms < 0 ? '$seconds초 먼저' : '$seconds초 늦게';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                hasSyncedLyrics ? '싱크 가사 있음' : '싱크 가사 없음',
                style: AppTypography.bodyMuted,
              ),
            ),
            OutlinedButton.icon(
              onPressed: onFetch,
              icon: const Icon(Icons.lyrics_outlined, size: 20),
              label: const Text('가사 가져오기'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(150, AppConstants.minTouchTarget),
                side: const BorderSide(
                  color: AppColors.borderStrong,
                  width: 2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: onImportFile,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(110, AppConstants.minTouchTarget),
                side: const BorderSide(
                  color: AppColors.borderStrong,
                  width: 2,
                ),
              ),
              child: const Text('.lrc 파일'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('가사 표시 시점', style: AppTypography.bodyMuted),
            const SizedBox(width: 10),
            _OffsetButton(
              icon: Icons.remove,
              semanticsLabel: '가사를 0.2초 더 먼저 띄우기',
              onTap: () => onAdjust(-200),
            ),
            const SizedBox(width: 8),
            Text(formatOffset(offsetMs), style: AppTypography.mono),
            const SizedBox(width: 8),
            _OffsetButton(
              icon: Icons.add,
              semanticsLabel: '가사를 0.2초 더 늦게 띄우기',
              onTap: () => onAdjust(200),
            ),
          ],
        ),
      ],
    );
  }
}

class _OffsetButton extends StatelessWidget {
  final IconData icon;
  final String semanticsLabel;
  final VoidCallback onTap;

  const _OffsetButton({
    required this.icon,
    required this.semanticsLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      button: true,
      child: IconButton(
        icon: Icon(icon),
        tooltip: semanticsLabel,
        onPressed: onTap,
        constraints: const BoxConstraints(
          minWidth: AppConstants.minTouchTarget,
          minHeight: AppConstants.minTouchTarget,
        ),
      ),
    );
  }
}

/// 원곡 대비 키 조절. 슬라이더가 아니라 큰 -/+ 버튼을 쓰고
/// 현재 값을 '원키 / 2키 낮춤' 처럼 말로 함께 보여준다.
class _PitchRow extends StatelessWidget {
  final int semitones;
  final ValueChanged<int> onAdjust;

  /// 지금 실제로 들리는 조성. 모르면 표시하지 않는다.
  final MusicKey? soundingKey;

  const _PitchRow({
    required this.semitones,
    required this.onAdjust,
    this.soundingKey,
  });

  @override
  Widget build(BuildContext context) {
    final key = soundingKey;
    return Row(
      children: [
        Text('키', style: AppTypography.bodyMuted),
        const SizedBox(width: 10),
        _OffsetButton(
          icon: Icons.remove,
          semanticsLabel: '키 한 음 내리기',
          onTap: () => onAdjust(-1),
        ),
        const SizedBox(width: 8),
        Text(formatKeyLabel(semitones), style: AppTypography.mono),
        const SizedBox(width: 8),
        _OffsetButton(
          icon: Icons.add,
          semanticsLabel: '키 한 음 올리기',
          onTap: () => onAdjust(1),
        ),
        if (key != null) ...[
          const SizedBox(width: 12),
          Semantics(
            label: '현재 조성 ${key.label}',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.tertiary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                key.label,
                style: AppTypography.mono.copyWith(color: AppColors.tertiary),
              ),
            ),
          ),
        ],
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            semitones == 0 ? '' : '처음 재생 시 변환에 잠시 걸립니다',
            style: AppTypography.bodyMuted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// 템포 조절 줄. 슬라이더가 아니라 -/+ 인 이유는 키와 같다 —
/// 값을 바꾸면 곡 전체를 다시 굽는 비싼 작업이 돌기 때문이다.
class _TempoRow extends StatelessWidget {
  final double scale;
  final ValueChanged<double> onAdjust;

  const _TempoRow({required this.scale, required this.onAdjust});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('템포', style: AppTypography.bodyMuted),
        const SizedBox(width: 10),
        _OffsetButton(
          icon: Icons.remove,
          semanticsLabel: '템포 느리게',
          onTap: () => onAdjust(-tempoStep),
        ),
        const SizedBox(width: 8),
        Semantics(
          label: tempoSemanticLabel(scale),
          child: Text(formatTempoLabel(scale), style: AppTypography.mono),
        ),
        const SizedBox(width: 8),
        _OffsetButton(
          icon: Icons.add,
          semanticsLabel: '템포 빠르게',
          onTap: () => onAdjust(tempoStep),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            isDefaultTempo(scale) ? '' : '음정은 그대로 — 처음 재생 시 변환에 잠시 걸립니다',
            style: AppTypography.bodyMuted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

String _formatElapsed(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$sec';
}
