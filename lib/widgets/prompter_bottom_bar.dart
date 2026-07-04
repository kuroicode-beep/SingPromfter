// file: lib/widgets/prompter_bottom_bar.dart
//
// 메인 화면 하단 재생 바(항상 표시) + 표시 설정(접이식).
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/prompter_display_mode.dart';
import '../models/prompter_settings.dart';
import '../models/song.dart';
import '../theme/app_theme.dart';
import 'compact_btn.dart';
import 'mini_slider.dart';
import 'preset_btn.dart';
import 'prompter_progress_bar.dart';

class PrompterBottomBar extends StatefulWidget {
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
            ],
          ),
          const SizedBox(height: 8),
          PrompterProgressBar(
            position: widget.position,
            duration: widget.duration,
            enabled: widget.audioReady,
            onSeek: widget.onSeek,
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
              const SizedBox(width: 12),
              Expanded(
                child: MiniSlider(
                  label: '재생속도',
                  value: widget.settings.playbackRate,
                  min: 0.5,
                  max: 1.5,
                  divisions: 10,
                  step: 0.1,
                  semanticValue:
                      '현재 ${widget.settings.playbackRate.toStringAsFixed(1)} 배속',
                  onChanged: (v) => widget.onSettingsChanged(
                    widget.settings.copyWith(playbackRate: v),
                  ),
                ),
              ),
            ],
          ),
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
                    Text('표시 설정', style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
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
            MiniSlider(
              label: '속도',
              value: widget.settings.speedLevel,
              min: 0,
              max: 10,
              divisions: 20,
              onChanged: (v) => widget.onSettingsChanged(
                widget.settings.copyWith(speedLevel: v),
              ),
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
                      widget.onSettingsChanged(
                        widget.settings.copyWith(displayMode: mode),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 4),
                const Tooltip(
                  message: '줄 하이라이트는 자동 스크롤 속도 기준으로 이동합니다.',
                  child: Icon(
                    Icons.info_outline,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
