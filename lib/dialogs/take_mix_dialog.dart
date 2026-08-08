// file: lib/dialogs/take_mix_dialog.dart
//
// 테이크별 믹스 설정 — 보컬/반주 밸런스·리버브·노이즈 제거·보컬 분리.
// 설정은 테이크에 저장되어 "다시 합치기"에 반영된다.
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/recording_take.dart';
import '../theme/app_theme.dart';

/// 다이얼로그 결과 — 갱신된 테이크와 후속 동작.
class TakeMixDialogResult {
  final RecordingTake take;

  /// 저장 후 바로 다시 합치기.
  final bool remix;

  /// 분리 서버로 보컬 정리 실행(닫힌 뒤 화면이 진행).
  final bool separate;

  const TakeMixDialogResult({
    required this.take,
    this.remix = false,
    this.separate = false,
  });
}

class TakeMixDialog extends StatefulWidget {
  final RecordingTake take;

  /// 로컬AI 스위치가 꺼져 있으면 보컬 분리 버튼을 비활성화한다.
  final bool localAiEnabled;

  const TakeMixDialog({
    super.key,
    required this.take,
    required this.localAiEnabled,
  });

  static Future<TakeMixDialogResult?> show(
    BuildContext context, {
    required RecordingTake take,
    required bool localAiEnabled,
  }) {
    return showDialog<TakeMixDialogResult>(
      context: context,
      builder: (_) => TakeMixDialog(
        take: take,
        localAiEnabled: localAiEnabled,
      ),
    );
  }

  @override
  State<TakeMixDialog> createState() => _TakeMixDialogState();
}

class _TakeMixDialogState extends State<TakeMixDialog> {
  late double _balance = widget.take.mixBalance;
  late ReverbPreset _reverb = widget.take.reverbPreset;
  late bool _noiseReduction = widget.take.noiseReduction;

  RecordingTake get _updatedTake => widget.take.copyWith(
    mixBalance: _balance,
    reverbPreset: _reverb,
    noiseReduction: _noiseReduction,
  );

  @override
  Widget build(BuildContext context) {
    final vocalPercent = (_balance * 100).round();
    return AlertDialog(
      title: const Text('믹스 설정'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('밸런스', style: AppTypography.bodyMuted),
                  const SizedBox(width: 8),
                  Text(
                    '보컬 $vocalPercent% · 반주 ${100 - vocalPercent}%',
                    style: AppTypography.mono,
                  ),
                ],
              ),
              Slider(
                value: _balance,
                min: 0,
                max: 1,
                divisions: 20,
                label: '보컬 $vocalPercent%',
                onChanged: (v) => setState(() => _balance = v),
              ),
              const SizedBox(height: 8),
              Text('리버브 (보컬)', style: AppTypography.bodyMuted),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ReverbPreset.values.map((preset) {
                  final selected = _reverb == preset;
                  return ChoiceChip(
                    label: Text(preset.label, style: AppTypography.body),
                    selected: selected,
                    onSelected: (_) => setState(() => _reverb = preset),
                  );
                }).toList(growable: false),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('노이즈 제거', style: AppTypography.body),
                subtitle: Text(
                  '보컬 트랙의 배경 잡음을 줄입니다 (afftdn)',
                  style: AppTypography.bodyMuted,
                ),
                value: _noiseReduction,
                onChanged: (v) => setState(() => _noiseReduction = v),
              ),
              const Divider(height: 24),
              Text('보컬 정리 (AI 분리)', style: AppTypography.bodyMuted),
              const SizedBox(height: 6),
              if (widget.take.hasSeparatedVocal)
                Text(
                  '분리된 보컬을 사용 중입니다 — 믹스·내보내기에 정리본이 쓰입니다.',
                  style: AppTypography.body,
                )
              else ...[
                Text(
                  '스피커로 녹음해 반주가 섞였다면, 분리 서버로 순수 보컬만 남길 수 있습니다.',
                  style: AppTypography.bodyMuted,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: widget.localAiEnabled
                      ? () => Navigator.of(context).pop(
                            TakeMixDialogResult(
                              take: _updatedTake,
                              separate: true,
                            ),
                          )
                      : null,
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('보컬 분리 실행'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(140, AppConstants.minTouchTarget),
                  ),
                ),
                if (!widget.localAiEnabled)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '설정에서 로컬AI를 켜면 사용할 수 있습니다.',
                      style: AppTypography.bodyMuted,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(context)
              .pop(TakeMixDialogResult(take: _updatedTake)),
          child: const Text('저장'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context)
              .pop(TakeMixDialogResult(take: _updatedTake, remix: true)),
          child: const Text('저장 후 다시 합치기'),
        ),
      ],
    );
  }
}
