// file: lib/dialogs/youtube_import_dialog.dart
//
// 유튜브 검색 결과의 [가져오기] 팝업 — 구성 프리셋 하나를 고른다.
//
//   기본    : 원곡 / MR / MR−2키          (새 곡, 3슬롯)
//   남자키  : 원곡 / MR−5키 / MR−7키      (새 곡, 3슬롯)
//   4번슬롯 : 노래방 반주를 기존 곡에 부착 (원음/−2/−5/−7 + 수동)
//
// 각 키는 기본값으로 두되 −/+ 버튼으로 수동 조절할 수 있다. 조절 범위는
// 렌더 규약(pitch_math)의 ±8을 그대로 쓴다.
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/import_plan.dart';
import '../theme/app_theme.dart';
import '../utils/key_label.dart';
import '../utils/pitch_math.dart';

/// 어떤 구성으로 가져올지.
enum YoutubeImportKind { basic, maleKey, karaoke }

/// 팝업의 결과.
class YoutubeImportChoice {
  final YoutubeImportKind kind;

  /// basic·maleKey일 때의 새 곡 구성.
  final ImportPlan? plan;

  /// karaoke일 때 4번 슬롯에 구워 넣을 반음. 0이면 원음.
  final int karaokeSemitones;

  const YoutubeImportChoice.newSong(this.kind, ImportPlan this.plan)
    : karaokeSemitones = 0;

  const YoutubeImportChoice.karaoke(this.karaokeSemitones)
    : kind = YoutubeImportKind.karaoke,
      plan = null;
}

class YoutubeImportDialog {
  YoutubeImportDialog._();

  static Future<YoutubeImportChoice?> show(
    BuildContext context, {
    required String videoTitle,
  }) {
    return showDialog<YoutubeImportChoice>(
      context: context,
      builder: (_) => _YoutubeImportDialogBody(videoTitle: videoTitle),
    );
  }
}

class _YoutubeImportDialogBody extends StatefulWidget {
  final String videoTitle;

  const _YoutubeImportDialogBody({required this.videoTitle});

  @override
  State<_YoutubeImportDialogBody> createState() =>
      _YoutubeImportDialogBodyState();
}

class _YoutubeImportDialogBodyState extends State<_YoutubeImportDialogBody> {
  YoutubeImportKind _kind = YoutubeImportKind.basic;

  // 각 프리셋의 기본 키 — 수동으로 바꿀 수 있다.
  int _basicPitch = -2;
  int _maleMr = -5;
  int _malePitch = -7;
  int _karaokeKey = 0;

  void _submit() {
    final choice = switch (_kind) {
      YoutubeImportKind.basic => YoutubeImportChoice.newSong(
        _kind,
        ImportPlan.full(semitones: _basicPitch),
      ),
      YoutubeImportKind.maleKey => YoutubeImportChoice.newSong(
        _kind,
        ImportPlan.maleKey(mrSemitones: _maleMr, pitchSemitones: _malePitch),
      ),
      YoutubeImportKind.karaoke => YoutubeImportChoice.karaoke(_karaokeKey),
    };
    Navigator.pop(context, choice);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('어떻게 가져올까요?'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.videoTitle,
                style: AppTypography.bodyMuted,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              _KindTile(
                selected: _kind == YoutubeImportKind.basic,
                title: '기본',
                description: '원곡 / MR / MR ${formatKeyLabel(_basicPitch)}',
                onTap: () => setState(() => _kind = YoutubeImportKind.basic),
                child: _kind == YoutubeImportKind.basic
                    ? _KeyStepper(
                        label: '키조절 슬롯',
                        value: _basicPitch,
                        onChanged: (v) => setState(() => _basicPitch = v),
                      )
                    : null,
              ),
              const SizedBox(height: 8),
              _KindTile(
                selected: _kind == YoutubeImportKind.maleKey,
                title: '남자키',
                description:
                    '원곡 / MR ${formatKeyLabel(_maleMr)} / '
                    'MR ${formatKeyLabel(_malePitch)}',
                onTap: () => setState(() => _kind = YoutubeImportKind.maleKey),
                child: _kind == YoutubeImportKind.maleKey
                    ? Column(
                        children: [
                          _KeyStepper(
                            label: 'MR 슬롯',
                            value: _maleMr,
                            onChanged: (v) => setState(() => _maleMr = v),
                          ),
                          const SizedBox(height: 6),
                          _KeyStepper(
                            label: '키조절 슬롯',
                            value: _malePitch,
                            onChanged: (v) => setState(() => _malePitch = v),
                          ),
                        ],
                      )
                    : null,
              ),
              const SizedBox(height: 8),
              _KindTile(
                selected: _kind == YoutubeImportKind.karaoke,
                title: '4번 슬롯 (노래방 반주)',
                description:
                    '기존 곡에 부착 · ${formatKeyLabel(_karaokeKey)}',
                onTap: () => setState(() => _kind = YoutubeImportKind.karaoke),
                child: _kind == YoutubeImportKind.karaoke
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final key in const [0, -2, -5, -7])
                                _KeyPresetChip(
                                  semitones: key,
                                  selected: _karaokeKey == key,
                                  onTap: () =>
                                      setState(() => _karaokeKey = key),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          _KeyStepper(
                            label: '수동',
                            value: _karaokeKey,
                            onChanged: (v) => setState(() => _karaokeKey = v),
                          ),
                        ],
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            minimumSize: const Size(120, AppConstants.minTouchTarget),
          ),
          child: const Text('가져오기'),
        ),
      ],
    );
  }
}

/// 프리셋 한 줄 — 라디오처럼 하나만 선택된다. 선택 상태는 색과 함께
/// 체크 아이콘·테두리로도 구분한다.
class _KindTile extends StatelessWidget {
  final bool selected;
  final String title;
  final String description;
  final VoidCallback onTap;
  final Widget? child;

  const _KindTile({
    required this.selected,
    required this.title,
    required this.description,
    required this.onTap,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$title, $description${selected ? ', 선택됨' : ''}',
      child: Material(
        color: selected ? AppColors.selectedSurface : AppColors.surfaceContainer,
        borderRadius: AppShapes.controlRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppShapes.controlRadius,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppConstants.minTouchTarget,
            ),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: AppShapes.controlRadius,
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.outline,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 20,
                      color: selected
                          ? AppColors.primary
                          : AppColors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(title, style: AppTypography.body),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 28),
                  child: Text(description, style: AppTypography.bodyMuted),
                ),
                if (child != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 28, top: 8),
                    child: child,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 반음 −/+ 조절 줄. 범위는 렌더 규약(±8)을 따른다.
class _KeyStepper extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _KeyStepper({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(label, style: AppTypography.bodyMuted),
        ),
        _StepBtn(
          icon: Icons.remove,
          tooltip: '$label 반음 내리기',
          onTap: value <= minPitchSemitones
              ? null
              : () => onChanged(value - 1),
        ),
        SizedBox(
          width: 92,
          child: Text(
            formatKeyLabel(value),
            textAlign: TextAlign.center,
            style: AppTypography.mono,
          ),
        ),
        _StepBtn(
          icon: Icons.add,
          tooltip: '$label 반음 올리기',
          onTap: value >= maxPitchSemitones
              ? null
              : () => onChanged(value + 1),
        ),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _StepBtn({required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(
              AppConstants.minTouchTarget,
              AppConstants.minTouchTarget,
            ),
            padding: EdgeInsets.zero,
          ),
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }
}

/// 노래방 키 프리셋 칩 — 원음/−2/−5/−7.
class _KeyPresetChip extends StatelessWidget {
  final int semitones;
  final bool selected;
  final VoidCallback onTap;

  const _KeyPresetChip({
    required this.semitones,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = semitones == 0 ? '원음' : formatKeyLabel(semitones);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label${selected ? ', 선택됨' : ''}',
      child: Material(
        color: selected ? AppColors.primaryContainer : AppColors.surfaceContainer,
        borderRadius: AppShapes.controlRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppShapes.controlRadius,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppConstants.minTouchTarget,
              minWidth: 72,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            child: Text(
              label,
              style: AppTypography.body.copyWith(
                color: selected ? AppColors.onPrimaryContainer : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
