// file: lib/widgets/settings_panel.dart
//
// 백업·일괄 등록·프롬프터 기본값·표시(글꼴·글자 크기)·앱 정보 설정 화면.
import 'package:flutter/material.dart';

import '../constants/app_version.dart';
import '../models/practice_session.dart';
import '../services/app_display_controller.dart';
import '../theme/app_theme.dart';
import '../utils/key_label.dart';
import 'preset_btn.dart';

class SettingsPanel extends StatelessWidget {
  final List<PracticeSummary> practiceSummaries;
  final VoidCallback onBatchRegister;
  final VoidCallback onExportBackup;
  final VoidCallback onImportBackup;
  final VoidCallback onRunMaintenance;
  final VoidCallback onCustomFontSize;
  final ValueChanged<String> onAccessibilityPreset;

  const SettingsPanel({
    super.key,
    this.practiceSummaries = const [],
    required this.onBatchRegister,
    required this.onExportBackup,
    required this.onImportBackup,
    required this.onRunMaintenance,
    required this.onCustomFontSize,
    required this.onAccessibilityPreset,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text('데이터 관리', style: AppTypography.listTitle),
        const SizedBox(height: 8),
        _SettingsTile(
          icon: Icons.playlist_add,
          title: '일괄 등록',
          subtitle: 'txt 가사와 반주 파일을 한 번에 등록',
          onTap: onBatchRegister,
        ),
        _SettingsTile(
          icon: Icons.archive_outlined,
          title: '백업보내기',
          subtitle: '곡·설정을 zip 파일로 저장',
          onTap: onExportBackup,
        ),
        _SettingsTile(
          icon: Icons.unarchive_outlined,
          title: '백업 가져오기',
          subtitle: '저장한 zip 백업 복원',
          onTap: onImportBackup,
        ),
        _SettingsTile(
          icon: Icons.cleaning_services_outlined,
          title: '라이브러리 정리',
          subtitle: '사용하지 않는 파일·임시 항목 정리, 중복 제목 확인',
          onTap: onRunMaintenance,
        ),
        const SizedBox(height: 24),
        Text('프롬프터 기본값', style: AppTypography.listTitle),
        const SizedBox(height: 8),
        Text(
          '접근성 프리셋을 선택하면 글자 크기·줄 간격·속도가 함께 적용됩니다.',
          style: AppTypography.bodyMuted,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PresetBtn(
              label: '기본',
              onTap: () => onAccessibilityPreset('standard'),
            ),
            PresetBtn(
              label: '추천',
              onTap: () => onAccessibilityPreset('recommended'),
            ),
            PresetBtn(label: '무대', onTap: () => onAccessibilityPreset('stage')),
            PresetBtn(
              label: '글자 크기',
              semanticsLabel: '사용자 지정 글자 크기',
              onTap: onCustomFontSize,
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _DisplaySettingsSection(),
        const SizedBox(height: 24),
        _PracticeLogSection(summaries: practiceSummaries),
        const SizedBox(height: 32),
        Text('앱 정보', style: AppTypography.listTitle),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('버전 ', style: AppTypography.bodyMuted),
            Text('v${AppVersion.current}', style: AppTypography.mono),
          ],
        ),
        const SizedBox(height: 8),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: Text('업데이트 히스토리', style: AppTypography.body),
            iconColor: AppColors.primary,
            collapsedIconColor: AppColors.onSurfaceVariant,
            children: AppVersion.history
                .map((e) => _HistoryRow(entry: e))
                .toList(growable: false),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Copyright SVIL. Powered by 디또 2026/03/10',
          style: AppTypography.bodyMuted.copyWith(height: 1.4),
        ),
      ],
    );
  }
}

/// SVIL 설정 표준: 앱 글꼴 선택 + 글자 크기 3단계.
class _DisplaySettingsSection extends StatelessWidget {
  const _DisplaySettingsSection();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppDisplaySettings>(
      valueListenable: AppDisplayController.notifier,
      builder: (context, display, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('표시', style: AppTypography.listTitle),
            const SizedBox(height: 8),
            Text('앱 글꼴', style: AppTypography.bodyMuted),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AppDisplayController.fontFamilies.entries
                  .map((entry) {
                    final selected = display.fontKey == entry.key;
                    return _SelectChip(
                      label: entry.key,
                      selected: selected,
                      // 각 옵션은 해당 글꼴로 미리보기.
                      labelStyle: TextStyle(
                        fontFamily: entry.value,
                        fontSize: 16,
                        color: selected
                            ? AppColors.onPrimaryContainer
                            : AppColors.onSurface,
                      ),
                      onTap: () => AppDisplayController.setFont(entry.key),
                    );
                  })
                  .toList(growable: false),
            ),
            const SizedBox(height: 16),
            Text('글자 크기', style: AppTypography.bodyMuted),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AppDisplayController.sizeSteps.entries
                  .map((entry) {
                    final selected =
                        (display.textScale - entry.value).abs() < 0.001;
                    return _SelectChip(
                      label: entry.key,
                      selected: selected,
                      onTap: () => AppDisplayController.setScale(entry.value),
                    );
                  })
                  .toList(growable: false),
            ),
          ],
        );
      },
    );
  }
}

class _SelectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final TextStyle? labelStyle;
  final VoidCallback onTap;

  const _SelectChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppShapes.controlRadius,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 50, minWidth: 72),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryContainer : AppColors.elevated,
              borderRadius: AppShapes.controlRadius,
              border: Border.all(
                color: selected
                    ? AppColors.primaryContainer
                    : AppColors.borderStrong,
                width: 2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.check,
                      size: 18,
                      color: AppColors.onPrimaryContainer,
                    ),
                  ),
                Text(
                  label,
                  style:
                      labelStyle ??
                      AppTypography.body.copyWith(
                        color: selected
                            ? AppColors.onPrimaryContainer
                            : AppColors.onSurface,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final AppVersionEntry entry;

  const _HistoryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text('v${entry.version}', style: AppTypography.monoMuted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.summary, style: AppTypography.body),
                Text(entry.date, style: AppTypography.monoMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: title,
      button: true,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        minVerticalPadding: 12,
        leading: Icon(icon, color: AppColors.primary, size: 26),
        title: Text(title, style: AppTypography.body),
        subtitle: Text(subtitle, style: AppTypography.bodyMuted),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
        onTap: onTap,
      ),
    );
  }
}

/// 연습 기록 — 곡별 누적 횟수·총 시간·최근 연습일·주 사용 키.
/// (기간별 추이 등 본격 분석 화면은 이후 버전에서 별도 제공)
class _PracticeLogSection extends StatelessWidget {
  final List<PracticeSummary> summaries;

  const _PracticeLogSection({required this.summaries});

  static String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours > 0) return '$hours시간 $minutes분';
    if (minutes > 0) return '$minutes분';
    return '${d.inSeconds}초';
  }

  static String _formatDate(DateTime at) {
    final y = at.year.toString().padLeft(4, '0');
    final m = at.month.toString().padLeft(2, '0');
    final d = at.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('연습 기록', style: AppTypography.listTitle),
        const SizedBox(height: 8),
        if (summaries.isEmpty)
          Text(
            '아직 기록이 없습니다. 곡을 30초 이상 연습하면 자동으로 기록됩니다.',
            style: AppTypography.bodyMuted,
          )
        else ...[
          Text(
            '곡을 30초 이상 재생하면 한 번의 연습으로 기록됩니다.',
            style: AppTypography.bodyMuted,
          ),
          const SizedBox(height: 12),
          ...summaries.map((s) => _PracticeRow(summary: s)),
        ],
      ],
    );
  }
}

class _PracticeRow extends StatelessWidget {
  final PracticeSummary summary;

  const _PracticeRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    // 상태를 색이 아니라 텍스트 라벨로 함께 드러낸다.
    final detail =
        '${summary.sessionCount}회 · '
        '${_PracticeLogSection._formatDuration(summary.totalDuration)} · '
        '${formatKeyLabel(summary.dominantPitchSemitones)}';

    return Semantics(
      label:
          '${summary.songTitle}, $detail, '
          '최근 연습 ${_PracticeLogSection._formatDate(summary.lastPracticedAt)}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              summary.songTitle,
              style: AppTypography.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(detail, style: AppTypography.monoMuted),
                ),
                Text(
                  _PracticeLogSection._formatDate(summary.lastPracticedAt),
                  style: AppTypography.monoMuted,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
