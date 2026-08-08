// file: lib/widgets/prompter_bottom_bar.dart
//
// 메인 화면 하단 재생 바(항상 표시) + 표시 설정(접이식).
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../controllers/playback_controller.dart';
import '../models/prompter_settings.dart';
import '../models/song.dart';
import '../theme/app_theme.dart';
import '../utils/key_label.dart';
import '../utils/pitch_math.dart';
import '../utils/tempo_label.dart';
import '../utils/music_key.dart';
import 'compact_btn.dart';
import 'mini_slider.dart';
import 'prompter_drawer.dart';
import 'prompter_keyboard_scope.dart' show lyricsNudgeStepMs;
import 'prompter_progress_bar.dart';
import 'server_status_strip.dart';

class PrompterBottomBar extends StatefulWidget {
  final Song song;
  final bool playing;
  final bool audioReady;
  final bool hasQueuedSongs;
  final Duration duration;
  final PlaybackController playback;
  final PrompterSettings settings;

  /// 조작판을 펼쳐 둘지. 전송 버튼과 진행바는 접혀도 항상 보인다 —
  /// 닫힌 채로도 일시정지는 눌러야 한다.
  final bool drawerOpen;
  final ValueChanged<bool> onDrawerChanged;

  /// 펼친 조작판이 넘지 못하는 높이. 부모(패널)가 자기 높이의 몫으로 준다 —
  /// 없으면 조작판이 가사 뷰를 통째로 밀어낸다. [PrompterDrawer.maxBodyHeight]
  final double? maxDrawerBodyHeight;
  final VoidCallback onStop;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onRestart;
  final VoidCallback onSkipNext;
  final VoidCallback onOpenPrompter;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<PrompterSettings> onSettingsChanged;
  final ValueChanged<String> onMessage;
  final bool hasSyncedLyrics;
  final int lyricsOffsetMs;
  final VoidCallback onFetchSyncedLyrics;
  final VoidCallback onImportLrcFile;
  final ValueChanged<int> onAdjustLyricsOffset;

  /// 원곡·MR 비교로 가사 싱크를 자동으로 맞춘다. 조건이 안 되면 null.
  final VoidCallback? onAutoAlignLyrics;

  /// 재생 중에 "지금이 첫 줄"을 지정한다(단축키 T).
  final VoidCallback? onAnchorFirstLine;

  /// AI 받아쓰기(STT) — LRCLIB에 없는 곡의 싱크 가사를 만든다.
  final VoidCallback? onSttLyrics;
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

  /// v2.10.0: 우상단에 있던 곡 추가·서버 상태를 조작판으로 옮겼다 —
  /// 시선이 아래(조작판)에 머무는 앱이라 위로 손을 뻗을 일을 없앤다.
  final VoidCallback? onAddSong;
  final Future<bool> Function()? onStartSeparator;

  /// 지금 선택된 반주 mp3를 다운로드 폴더로 복사한다(외부 기기 반출용).
  final VoidCallback? onExportTrack;

  const PrompterBottomBar({
    super.key,
    required this.song,
    required this.playing,
    required this.audioReady,
    required this.hasQueuedSongs,
    required this.duration,
    required this.playback,
    required this.settings,
    this.drawerOpen = false,
    required this.onDrawerChanged,
    this.maxDrawerBodyHeight,
    required this.onStop,
    required this.onTogglePlayPause,
    required this.onRestart,
    required this.onSkipNext,
    required this.onOpenPrompter,
    required this.onSeek,
    required this.onSettingsChanged,
    required this.onMessage,
    required this.hasSyncedLyrics,
    required this.lyricsOffsetMs,
    required this.onFetchSyncedLyrics,
    required this.onImportLrcFile,
    required this.onAdjustLyricsOffset,
    this.onAutoAlignLyrics,
    this.onAnchorFirstLine,
    this.onSttLyrics,
    required this.pitchSemitones,
    required this.onAdjustPitch,
    this.soundingKey,
    this.tempoScale = 1,
    required this.onAdjustTempo,
    required this.isRecording,
    required this.recordingLevelLabel,
    required this.recordingElapsed,
    required this.onToggleRecording,
    this.onAddSong,
    this.onStartSeparator,
    this.onExportTrack,
  });

  @override
  State<PrompterBottomBar> createState() => _PrompterBottomBarState();
}

class _PrompterBottomBarState extends State<PrompterBottomBar> {
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
          // 손잡이 두 개(재생바·조작판)를 **한 줄에 나란히** 둔다.
          // 세로로 쌓으면 다 접어도 100px 넘게 남아, 드로어를 숨겨도
          // 가사 창이 커진 게 티가 안 났다(실사용 불만). 이제 접힌 상태의
          // 상시 크롬은 한 줄(50px+여백)뿐이다.
          Row(
            children: [
              Expanded(
                child: PrompterDrawerHandle(
                  open: widget.settings.playbackBarOpen,
                  label: '재생바',
                  palette: PrompterDrawerPalette.main,
                  margin: const EdgeInsets.fromLTRB(0, 4, 4, 0),
                  onTap: () => widget.onSettingsChanged(
                    widget.settings.copyWith(
                      playbackBarOpen: !widget.settings.playbackBarOpen,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PrompterDrawerHandle(
                  open: widget.drawerOpen,
                  label: '조작판',
                  palette: PrompterDrawerPalette.main,
                  margin: const EdgeInsets.fromLTRB(4, 4, 0, 0),
                  onTap: () => widget.onDrawerChanged(!widget.drawerOpen),
                ),
              ),
            ],
          ),
          // 재생바(재생 버튼 줄+진행바)도 조작판처럼 드로어다 — 기본 숨김.
          PrompterDrawer(
            open: widget.settings.playbackBarOpen,
            onOpenChanged: (open) => widget.onSettingsChanged(
              widget.settings.copyWith(playbackBarOpen: open),
            ),
            label: '재생바',
            externalHandle: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
          // Row가 아니라 Wrap이다. v2.10.0에서 [곡 시작]·[곡 추가]·서버 상태를
          // 이 줄로 옮기며 고정 폭 합계가 700px 가까이 늘었는데, 홈은 3열이라
          // 조작판이 받는 폭은 창 폭의 일부뿐이다(1280 창 + 큐 열림 = 738).
          // Row에서는 좁아지는 순간 오른쪽이 통째로 잘려 나갔다 — 저시력
          // 사용자에게 "화면 밖으로 나간 버튼"은 없는 버튼이다. 이제 두 줄로
          // 접힌다. spacing이 예전 SizedBox(width: 6) 자리를 대신한다.
          Wrap(
            spacing: 6,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CompactBtn(
                icon: Icons.stop,
                semanticsLabel: '정지',
                onTap: widget.onStop,
              ),
              CompactBtn(
                icon: widget.playing ? Icons.pause : Icons.play_arrow,
                semanticsLabel: widget.playing ? '일시정지' : '재생',
                toggled: widget.playing,
                onTap: widget.onTogglePlayPause,
                highlighted: true,
              ),
              CompactBtn(
                icon: Icons.replay,
                semanticsLabel: '처음부터 재생',
                onTap: widget.onRestart,
              ),
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
              // 우상단에서 옮겨 온 '곡 시작' — 아이콘 전용이던 전체화면 버튼을
              // 라벨 있는 버튼으로 바꿨다(저시력: 텍스트 라벨 원칙).
              FilledButton.icon(
                onPressed: widget.onOpenPrompter,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryContainer,
                  foregroundColor: AppColors.onPrimaryContainer,
                  minimumSize: const Size(96, AppConstants.minTouchTarget),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.fullscreen, size: 20),
                label: const Text('곡 시작'),
              ),
              CompactBtn(
                icon: widget.isRecording ? Icons.stop_circle : Icons.mic,
                semanticsLabel: widget.isRecording ? '녹음 정지 (R)' : '녹음 시작 (R)',
                toggled: widget.isRecording,
                onTap: widget.onToggleRecording,
              ),
              // 녹음 상태 세 조각은 한 덩어리로 접힌다 — 시간과 레벨이
              // 서로 다른 줄로 갈라지면 읽을 수 없다.
              if (widget.isRecording)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                ),
              // 우상단에서 옮겨 온 서버 상태·곡 추가.
              if (widget.onStartSeparator != null)
                ServerStatusChip(onStartServer: widget.onStartSeparator),
              if (widget.onAddSong != null)
                OutlinedButton.icon(
                  onPressed: widget.onAddSong,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(96, AppConstants.minTouchTarget),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  icon: const Icon(Icons.library_add_outlined, size: 20),
                  label: const Text('곡 추가'),
                ),
              if (widget.onExportTrack != null)
                OutlinedButton.icon(
                  onPressed: widget.onExportTrack,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(120, AppConstants.minTouchTarget),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  icon: const Icon(Icons.download, size: 20),
                  label: const Text('MR 내보내기'),
                ),
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
              ],
            ),
          ),
          PrompterDrawer(
            open: widget.drawerOpen,
            onOpenChanged: widget.onDrawerChanged,
            externalHandle: true,
            maxBodyHeight: widget.maxDrawerBodyHeight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                _TempoRow(
                  scale: widget.tempoScale,
                  onAdjust: widget.onAdjustTempo,
                ),
                const Divider(height: 16, thickness: 1),
                // 표시 설정(글자 크기·줄 간격·글꼴·굵게·표시 모드)은 v2.8.0에서
                // 설정 화면으로 옮겼다. 여기 남은 것은 노래하는 동안 손대야 하는
                // 값들뿐이다 — 키와 싱크 오프셋.
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
                  onAutoAlign: widget.onAutoAlignLyrics,
                  onAnchorFirstLine: widget.onAnchorFirstLine,
                  onSttLyrics: widget.onSttLyrics,
                ),
              ],
            ),
          ),
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

  /// 원곡과 MR을 비교해 오프셋을 자동으로 맞춘다. 조건이 안 되면 null.
  final VoidCallback? onAutoAlign;

  /// 재생 중에 "지금이 첫 줄"을 지정한다. 사람이 직접 맞추는 입구.
  final VoidCallback? onAnchorFirstLine;

  /// AI 받아쓰기 — 가사를 아무 데서도 못 구했을 때의 마지막 수단.
  final VoidCallback? onSttLyrics;

  const _SyncedLyricsRow({
    required this.hasSyncedLyrics,
    required this.offsetMs,
    required this.onFetch,
    required this.onImportFile,
    required this.onAdjust,
    this.onAutoAlign,
    this.onAnchorFirstLine,
    this.onSttLyrics,
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
                side: const BorderSide(color: AppColors.borderStrong, width: 2),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: onImportFile,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(110, AppConstants.minTouchTarget),
                side: const BorderSide(color: AppColors.borderStrong, width: 2),
              ),
              child: const Text('.lrc 파일'),
            ),
            if (onSttLyrics != null) ...[
              const SizedBox(width: 8),
              // 정밀 파이프라인 입구 — 보컬 분리 받아쓰기 + 환청 정리 +
              // (선택) 정답 가사 대조. 옵션은 다이얼로그에서 고른다.
              OutlinedButton.icon(
                onPressed: onSttLyrics,
                icon: const Icon(Icons.auto_fix_high, size: 20),
                label: const Text('가사 다시 생성'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(150, AppConstants.minTouchTarget),
                  side: const BorderSide(
                    color: AppColors.borderStrong,
                    width: 2,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        // 이 줄도 Wrap이다 — 자동 맞춤·앵커·오프셋이 다 들어가면 좁은 패널에서
        // Row로는 오른쪽이 잘린다.
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('가사 표시 시점', style: AppTypography.bodyMuted),
            if (onAutoAlign != null)
              OutlinedButton.icon(
                // 싱크 가사가 없으면 맞출 대상이 없다.
                onPressed: hasSyncedLyrics ? onAutoAlign : null,
                icon: const Icon(Icons.auto_fix_high, size: 20),
                label: const Text('자동 맞춤'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(120, AppConstants.minTouchTarget),
                  side: const BorderSide(
                    color: AppColors.borderStrong,
                    width: 2,
                  ),
                ),
              ),
            // 사람이 직접 맞추는 입구. 자동 맞춤이 실패하거나 LRC가 아예 없는
            // 곡(구간 배분)에서도 쓸 수 있어야 하므로 hasSyncedLyrics로 막지 않는다.
            if (onAnchorFirstLine != null)
              OutlinedButton.icon(
                onPressed: onAnchorFirstLine,
                icon: const Icon(Icons.my_location, size: 20),
                label: const Text('여기가 첫 줄'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(160, AppConstants.minTouchTarget),
                  side: const BorderSide(
                    color: AppColors.borderStrong,
                    width: 2,
                  ),
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 걸음은 . / 단축키와 같은 상수를 쓴다 — 걸음이 두 개면
                // 키보드로 맞춘 값과 버튼으로 맞춘 값이 서로 안 맞는다.
                _OffsetButton(
                  icon: Icons.remove,
                  semanticsLabel: '가사를 0.2초 앞당기기 (/ 또는 ])',
                  onTap: () => onAdjust(-lyricsNudgeStepMs),
                ),
                const SizedBox(width: 8),
                Text(formatOffset(offsetMs), style: AppTypography.mono),
                const SizedBox(width: 8),
                _OffsetButton(
                  icon: Icons.add,
                  semanticsLabel: '가사를 0.2초 늦추기 (. 또는 [)',
                  onTap: () => onAdjust(lyricsNudgeStepMs),
                ),
              ],
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
