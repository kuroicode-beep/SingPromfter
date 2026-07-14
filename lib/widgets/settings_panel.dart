// file: lib/widgets/settings_panel.dart
//
// 백업·일괄 등록·프롬프터 기본값·저작권 정보 설정 화면.
import 'package:flutter/material.dart';

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
            PresetBtn(
              label: '무대',
              onTap: () => onAccessibilityPreset('stage'),
            ),
            PresetBtn(
              label: '글자 크기',
              semanticsLabel: '사용자 지정 글자 크기',
              onTap: onCustomFontSize,
            ),
          ],
        ),
        const SizedBox(height: 32),
        Text('앱 정보', style: AppTypography.listTitle),
        const SizedBox(height: 8),
        Text(
          'Copyright SVIL. Powered by 디또 2026/03/10',
          style: AppTypography.bodyMuted.copyWith(height: 1.4),
        ),
      ],
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
        title: Text(
          title,
          style: AppTypography.body,
        ),
        subtitle: Text(subtitle, style: AppTypography.bodyMuted),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
        onTap: onTap,
      ),
    );
  }
}
