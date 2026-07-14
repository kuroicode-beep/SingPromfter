// file: lib/widgets/settings_panel.dart
//
// 백업·일괄 등록·프롬프터 기본값·표시(글꼴·글자 크기)·앱 정보 설정 화면.
import 'package:flutter/material.dart';

import '../constants/app_version.dart';
import '../services/app_display_controller.dart';
import '../theme/app_theme.dart';
import 'preset_btn.dart';

class SettingsPanel extends StatelessWidget {
  final VoidCallback onBatchRegister;
  final VoidCallback onExportBackup;
  final VoidCallback onImportBackup;
  final VoidCallback onCustomFontSize;
  final ValueChanged<String> onAccessibilityPreset;

  const SettingsPanel({
    super.key,
    required this.onBatchRegister,
    required this.onExportBackup,
    required this.onImportBackup,
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
