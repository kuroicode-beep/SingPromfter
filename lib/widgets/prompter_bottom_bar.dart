// file: lib/widgets/prompter_bottom_bar.dart
//
// 메인 화면 하단의 재생/접근성 컨트롤 바.
import 'package:flutter/material.dart';

import '../models/prompter_display_mode.dart';
import '../models/prompter_settings.dart';
import '../models/song.dart';
import '../theme/app_theme.dart';
import 'compact_btn.dart';
import 'mini_slider.dart';
import 'preset_btn.dart';

class PrompterBottomBar extends StatelessWidget {
  final Song song;
  final bool playing;
  final bool audioReady;
  final bool hasQueuedSongs;
  final Duration position;
  final Duration duration;
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

  const PrompterBottomBar({
    super.key,
    required this.song,
    required this.playing,
    required this.audioReady,
    required this.hasQueuedSongs,
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
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: AppShapes.panel(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                CompactBtn(
                  icon: Icons.stop,
                  semanticsLabel: '정지',
                  onTap: onStop,
                ),
                const SizedBox(width: 6),
                CompactBtn(
                  icon: playing ? Icons.pause : Icons.play_arrow,
                  semanticsLabel: playing ? '일시정지' : '재생',
                  toggled: playing,
                  onTap: onTogglePlayPause,
                  highlighted: true,
                ),
                const SizedBox(width: 6),
                CompactBtn(
                  icon: Icons.replay,
                  semanticsLabel: '처음부터 재생',
                  onTap: onRestart,
                ),
                const SizedBox(width: 6),
                CompactBtn(
                  icon: Icons.skip_next,
                  semanticsLabel: '다음 예약곡',
                  onTap: () {
                    if (!hasQueuedSongs) {
                      onMessage('다음 예약곡이 없습니다.');
                      return;
                    }
                    onSkipNext();
                  },
                ),
                const SizedBox(width: 6),
                CompactBtn(
                  icon: Icons.fullscreen,
                  semanticsLabel: '전체화면 프롬프터 열기',
                  onTap: onOpenPrompter,
                ),
                const SizedBox(width: 10),
                _DurationLabel(value: position),
                SizedBox(
                  width: 220,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 6,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 10,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 16,
                      ),
                    ),
                    child: Slider(
                      min: 0,
                      max: duration.inMilliseconds.toDouble().clamp(
                        1,
                        double.infinity,
                      ),
                      value: position.inMilliseconds.toDouble().clamp(
                        0,
                        duration.inMilliseconds.toDouble().clamp(
                          1,
                          double.infinity,
                        ),
                      ),
                      semanticFormatterCallback: (value) =>
                          '재생 위치 ${formatDuration(Duration(milliseconds: value.toInt()))}',
                      onChanged: audioReady
                          ? (v) => onSeek(Duration(milliseconds: v.toInt()))
                          : null,
                    ),
                  ),
                ),
                _DurationLabel(value: duration),
                const SizedBox(width: 10),
                SizedBox(
                  width: 210,
                  child: MiniSlider(
                    label: '볼륨',
                    value: settings.volume,
                    min: 0,
                    max: 1,
                    divisions: 10,
                    step: 0.1,
                    onChanged: (v) =>
                        onSettingsChanged(settings.copyWith(volume: v)),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 210,
                  child: MiniSlider(
                    label: '재생속도',
                    value: settings.playbackRate,
                    min: 0.5,
                    max: 1.5,
                    divisions: 10,
                    step: 0.1,
                    semanticValue:
                        '현재 ${settings.playbackRate.toStringAsFixed(1)} 배속',
                    onChanged: (v) =>
                        onSettingsChanged(settings.copyWith(playbackRate: v)),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 210,
                  child: MiniSlider(
                    label: '크기',
                    value: settings.fontSizeLevel,
                    min: 1,
                    max: 7,
                    divisions: 6,
                    semanticValue:
                        '현재 ${settings.effectiveFontSizePt.round()} 포인트',
                    onChanged: (v) => onSettingsChanged(
                      settings.copyWith(
                        fontSizeLevel: v,
                        clearCustomFontSize: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 210,
                  child: MiniSlider(
                    label: '줄간격',
                    value: settings.lineHeightLevel,
                    min: 1,
                    max: 7,
                    divisions: 6,
                    onChanged: (v) => onSettingsChanged(
                      settings.copyWith(lineHeightLevel: v),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 210,
                  child: MiniSlider(
                    label: '속도',
                    value: settings.speedLevel,
                    min: 0,
                    max: 10,
                    divisions: 20,
                    onChanged: (v) =>
                        onSettingsChanged(settings.copyWith(speedLevel: v)),
                  ),
                ),
                const SizedBox(width: 8),
                PresetBtn(
                  label: settings.customFontSizePt == null
                      ? '직접'
                      : '${settings.customFontSizePt!.round()}pt',
                  semanticsLabel: '사용자 정의 글자 크기',
                  onTap: onCustomFontSize,
                ),
                const SizedBox(width: 8),
                PresetBtn(
                  label: '표준',
                  semanticsLabel: '표준 접근성 프리셋',
                  onTap: () => onAccessibilityPreset('standard'),
                ),
                const SizedBox(width: 6),
                PresetBtn(
                  label: '저시력',
                  semanticsLabel: '저시력 추천 프리셋',
                  onTap: () => onAccessibilityPreset('recommended'),
                ),
                const SizedBox(width: 6),
                PresetBtn(
                  label: '원거리',
                  semanticsLabel: '원거리 무대 프리셋',
                  onTap: () => onAccessibilityPreset('stage'),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: fontOptions.containsKey(settings.fontFamily)
                      ? settings.fontFamily
                      : 'System Default',
                  dropdownColor: AppColors.surface,
                  isDense: false,
                  style: AppTypography.body,
                  items: fontOptions.keys
                      .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                      .toList(growable: false),
                  onChanged: (v) {
                    if (v == null) return;
                    onSettingsChanged(settings.copyWith(fontFamily: v));
                  },
                ),
                const SizedBox(width: 8),
                Semantics(
                  label: '굵은 글씨',
                  checked: settings.boldText,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Checkbox(
                      value: settings.boldText,
                      onChanged: (v) => onSettingsChanged(
                        settings.copyWith(boldText: v ?? false),
                      ),
                      visualDensity: VisualDensity.standard,
                    ),
                  ),
                ),
                Text('굵게', style: AppTypography.body),
                const SizedBox(width: 8),
                DropdownButton<PrompterDisplayMode>(
                  value: settings.displayMode,
                  dropdownColor: AppColors.surface,
                  style: AppTypography.body,
                  items: const [
                    DropdownMenuItem(
                      value: PrompterDisplayMode.full,
                      child: Text('전체 가사'),
                    ),
                    DropdownMenuItem(
                      value: PrompterDisplayMode.highlight,
                      child: Text('줄 하이라이트'),
                    ),
                  ],
                  onChanged: (mode) {
                    if (mode == null) return;
                    onSettingsChanged(settings.copyWith(displayMode: mode));
                  },
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: '줄 하이라이트는 자동 스크롤 속도 기준으로 이동합니다.',
                  child: Icon(
                    Icons.info_outline,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _DurationLabel extends StatelessWidget {
  final Duration value;

  const _DurationLabel({required this.value});

  @override
  Widget build(BuildContext context) {
    return Text(
      PrompterBottomBar.formatDuration(value),
      style: AppTypography.bodyMuted,
    );
  }
}
