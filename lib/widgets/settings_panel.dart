// file: lib/widgets/settings_panel.dart
//
// 백업·라이브러리 정리·무대 가사 표시·앱 화면·연습 기록·앱 정보 설정 화면.
//
// v2.8.0에서 무대의 표시 설정(글자 크기·줄 간격·글꼴·굵게·표시 모드)이
// 하단 조작판에서 이리로 왔다. 노래하는 동안 만질 값이 아니기 때문이다.
// 조작판에는 볼륨·템포·키·싱크 오프셋·녹음만 남는다.
//
// 섹션 이름 주의: '앱 화면'은 앱 전체 글꼴·배율(AppDisplayController)이고,
// '무대 가사 표시'는 프롬프터 가사(PrompterSettings)다. 둘 다 '표시'라고
// 부르면 구분이 안 돼 이름을 실체대로 바꿨다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_version.dart';
import '../models/practice_session.dart';
import '../models/prompter_display_mode.dart';
import '../models/prompter_settings.dart';
import '../services/app_display_controller.dart';
import '../theme/app_theme.dart';
import '../theme/prompter_levels.dart';
import '../utils/key_label.dart';
import 'preset_btn.dart';

class SettingsPanel extends StatelessWidget {
  final List<PracticeSummary> practiceSummaries;
  final String? ytDlpVersion;
  /// 무대 가사 표시 설정 전체. showEqMeter 하나만 따로 받던 것을 대체한다 —
  /// 쓰기 경로가 둘이면 반드시 어긋난다.
  final PrompterSettings settings;
  final ValueChanged<PrompterSettings> onSettingsChanged;

  /// 글꼴 이름 → 폰트 패밀리. 없으면 시스템 기본.
  final Map<String, String?> fontOptions;

  final String separatorStatusLabel;
  final VoidCallback onUpdateYtDlp;
  final VoidCallback onExportBackup;
  final VoidCallback onImportBackup;
  final VoidCallback onRunMaintenance;
  final VoidCallback onCustomFontSize;
  final ValueChanged<String> onAccessibilityPreset;

  const SettingsPanel({
    super.key,
    this.practiceSummaries = const [],
    this.ytDlpVersion,
    this.settings = const PrompterSettings(),
    required this.onSettingsChanged,
    this.fontOptions = const {},
    this.separatorStatusLabel = '',
    required this.onUpdateYtDlp,
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
        Text('외부 도구', style: AppTypography.listTitle),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('yt-dlp ', style: AppTypography.bodyMuted),
            Expanded(
              child: Text(
                ytDlpVersion == null ? '찾을 수 없음' : '버전 $ytDlpVersion',
                style: AppTypography.mono,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '유튜브 가져오기가 갑자기 실패하면 대부분 오래된 yt-dlp가 원인입니다.',
          style: AppTypography.bodyMuted,
        ),
        _SettingsTile(
          icon: Icons.system_update_alt,
          title: 'yt-dlp 업데이트 실행',
          subtitle: 'yt-dlp -U 로 최신 버전을 받습니다',
          onTap: onUpdateYtDlp,
        ),
        if (separatorStatusLabel.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(separatorStatusLabel, style: AppTypography.bodyMuted),
        ],
        const SizedBox(height: 24),
        _StageDisplaySection(
          settings: settings,
          onChanged: onSettingsChanged,
          fontOptions: fontOptions,
          onCustomFontSize: onCustomFontSize,
          onAccessibilityPreset: onAccessibilityPreset,
        ),
        const SizedBox(height: 24),
        const _AppDisplaySection(),
        const SizedBox(height: 24),
        const _ShortcutHelpSection(),
        const SizedBox(height: 24),
        const _KeyDiagSection(),
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

/// 단축키 안내 — 종류가 많아져서(사용자 요청) 한 곳에 정리한다.
/// 홈·즐겨찾기·전체화면에서만 동작하고, 텍스트 입력 중에는 자동으로 꺼진다.
class _ShortcutHelpSection extends StatelessWidget {
  const _ShortcutHelpSection();

  static const _shortcuts = <(String, String)>[
    ('Space', '재생 / 일시정지'),
    ('F5', '전체화면 무대 열기'),
    ('ESC', '무대 닫기'),
    ('R', '녹음 시작 / 중지'),
    ('← / →', '가사 0.2초 늦추기 / 앞당기기 (꾹 누르면 연속)'),
    ('Ctrl+← / →', '가사 1초 늦추기 / 앞당기기'),
    ('Alt+← / →', '다음 줄부터 아래만 보정 — 간주 뒤 어긋남용 (위는 그대로)'),
    ('[', '싱크 리셋 — 처음 상태로 (T와 같음)'),
    (']', '싱크 대기 — 가사를 멈췄다가, 나올 타이밍에 다시 누르면 그만큼 늦춰 이어감'),
    ('L', '싱크 잠금 토글 — 잠그면 싱크 조절 키가 전부 꺼진다'),
    ('↑ / ↓', '이전 줄 / 다음 줄 (꾹 누르면 연속)'),
    ('Shift+← / →', '30초 뒤로 / 앞으로 이동'),
    ('Shift+↑ / ↓', '볼륨'),
    ('O / P', '이전 줄 / 다음 줄 (꾹 누르면 연속)'),
    ('T', '가사 싱크를 원래대로 리셋'),
    ('. / /', '가사 0.2초 늦추기 / 앞당기기 (꾹 누르면 연속)'),
    ('E', '현재 가사 줄 편집 — ESC로 저장'),
    ('D', '현재 가사 줄 삭제 — 곡 끝의 환청 줄 지우기 (원본 .bak 백업)'),
    ('F', '가사 편집 실행취소 — D 삭제·부분 보정·줄 편집을 되돌림 (20단계)'),
    ('G', '가사를 보관된 원본(.bak)으로 복구 — 확인창을 거침'),
    ('Home / End', '곡 처음 / 끝으로'),
    ('Ctrl+휠', '글자 크기'),
    ('Alt+휠', '키(피치)'),
    ('Shift+휠', '템포'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('단축키', style: AppTypography.listTitle),
        const SizedBox(height: 4),
        Text(
          '홈·즐겨찾기·전체화면에서 동작합니다. 글자를 입력하는 중에는 꺼집니다.',
          style: AppTypography.bodyMuted,
        ),
        const SizedBox(height: 8),
        for (final (key, description) in _shortcuts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(key, style: AppTypography.mono),
                ),
                Expanded(
                  child: Text(description, style: AppTypography.body),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 단축키 진단 — "키가 안 먹는다"는 보고가 자판/IME 환경마다 달라서,
/// 이 기기에서 키가 실제로 어떻게 들어오는지 눈으로 확인하는 도구.
/// 이벤트는 화면에 최근 순으로 쌓이고 exe 옆 key_diag.log에도 기록된다.
class _KeyDiagSection extends StatefulWidget {
  const _KeyDiagSection();

  @override
  State<_KeyDiagSection> createState() => _KeyDiagSectionState();
}

class _KeyDiagSectionState extends State<_KeyDiagSection> {
  final FocusNode _node = FocusNode(debugLabel: 'keyDiag');
  final List<String> _events = [];
  bool _focused = false;

  static const int _maxLines = 10;

  @override
  void initState() {
    super.initState();
    _node.addListener(() => setState(() => _focused = _node.hasFocus));
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  String _describe(KeyEvent event) {
    final kind = switch (event) {
      KeyDownEvent() => '↓',
      KeyRepeatEvent() => '↻',
      _ => '↑',
    };
    final ch = event.character;
    final chText = (ch == null || ch.isEmpty)
        ? '문자 없음'
        : "'$ch'(U+${ch.codeUnitAt(0).toRadixString(16).toUpperCase()})";
    return '$kind 논리=${event.logicalKey.debugName} · '
        '물리=${event.physicalKey.debugName} · $chText';
  }

  void _appendLog(String line) {
    try {
      final dir = File(Platform.resolvedExecutable).parent.path;
      File('$dir${Platform.pathSeparator}key_diag.log').writeAsStringSync(
        '${DateTime.now().toIso8601String()} $line\n',
        mode: FileMode.append,
      );
    } catch (_) {
      // 진단 로그가 못 써져도 화면 표시는 계속한다.
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.handled;
    final line = _describe(event);
    setState(() {
      _events.insert(0, line);
      if (_events.length > _maxLines) _events.removeLast();
    });
    _appendLog(line);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('단축키 진단', style: AppTypography.listTitle),
        const SizedBox(height: 4),
        Text(
          '단축키가 안 먹을 때 원인을 찾는 도구예요. 아래 상자를 클릭한 뒤 '
          '문제의 키(예: O, P, [, ])를 눌러 보세요. 키가 어떻게 들어오는지 '
          '표시되고 key_diag.log 파일에도 남습니다.',
          style: AppTypography.bodyMuted.copyWith(height: 1.4),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _node.requestFocus,
          borderRadius: BorderRadius.circular(10),
          child: Focus(
            focusNode: _node,
            onKeyEvent: _onKey,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(
                  color: _focused ? AppColors.primary : AppColors.borderStrong,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _focused ? '입력 대기 중 — 키를 눌러 보세요' : '여기를 클릭해서 진단 시작',
                style: AppTypography.body,
              ),
            ),
          ),
        ),
        if (_events.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final line in _events)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(line, style: AppTypography.mono),
            ),
        ],
      ],
    );
  }
}

/// SVIL 설정 표준: 앱 글꼴 선택 + 글자 크기 3단계.
/// 무대 가사 표시 — 프롬프터에서 가사가 어떻게 보일지.
///
/// 컨트롤은 슬라이더가 아니라 칩이다. 저시력에는 "지금 몇 단계인지"가
/// 눈금이 아니라 **글자**로 보이는 쪽이 훨씬 낫고, 터치 타깃도 커진다.
class _StageDisplaySection extends StatelessWidget {
  final PrompterSettings settings;
  final ValueChanged<PrompterSettings> onChanged;
  final Map<String, String?> fontOptions;
  final VoidCallback onCustomFontSize;
  final ValueChanged<String> onAccessibilityPreset;

  const _StageDisplaySection({
    required this.settings,
    required this.onChanged,
    required this.fontOptions,
    required this.onCustomFontSize,
    required this.onAccessibilityPreset,
  });

  @override
  Widget build(BuildContext context) {
    final level = settings.customFontSizePt == null
        ? settings.fontSizeLevel.round()
        : PrompterLevels.levelForFontSize(settings.customFontSizePt!).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('무대 가사 표시', style: AppTypography.listTitle),
        const SizedBox(height: 8),
        Text(
          '프롬프터에서 가사가 보이는 방식입니다. '
          '무대에서는 Ctrl+휠로 글자 크기를 바로 바꿀 수도 있습니다.',
          style: AppTypography.bodyMuted,
        ),
        const SizedBox(height: 12),

        Text('접근성 프리셋', style: AppTypography.body),
        const SizedBox(height: 6),
        Text(
          '고르면 글자 크기·줄 간격·글꼴이 함께 적용됩니다.',
          style: AppTypography.bodyMuted,
        ),
        const SizedBox(height: 8),
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
              label: '직접 지정',
              semanticsLabel: '사용자 지정 글자 크기',
              onTap: onCustomFontSize,
            ),
          ],
        ),
        const SizedBox(height: 20),

        Text('글자 크기', style: AppTypography.body),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = PrompterLevels.minLevel.toInt();
                i <= PrompterLevels.maxLevel.toInt();
                i++)
              _SelectChip(
                label: '${PrompterLevels.fontSizeForLevel(i.toDouble()).round()}pt',
                selected: settings.customFontSizePt == null && level == i,
                onTap: () => onChanged(
                  settings.copyWith(
                    fontSizeLevel: i.toDouble(),
                    clearCustomFontSize: true,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),

        Text('줄 간격', style: AppTypography.body),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = PrompterLevels.minLevel.toInt();
                i <= PrompterLevels.maxLevel.toInt();
                i++)
              _SelectChip(
                label: PrompterLevels.lineHeightForLevel(
                  i.toDouble(),
                ).toStringAsFixed(2),
                selected: settings.lineHeightLevel.round() == i,
                onTap: () =>
                    onChanged(settings.copyWith(lineHeightLevel: i.toDouble())),
              ),
          ],
        ),
        if (fontOptions.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('글꼴', style: AppTypography.body),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in fontOptions.entries)
                _SelectChip(
                  label: entry.key,
                  selected: settings.fontFamily == entry.key,
                  labelStyle: TextStyle(fontFamily: entry.value),
                  onTap: () =>
                      onChanged(settings.copyWith(fontFamily: entry.key)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 20),

        Text('표시 모드', style: AppTypography.body),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in PrompterDisplayMode.values)
              _SelectChip(
                label: mode.label,
                selected: settings.displayMode == mode,
                onTap: () => onChanged(settings.copyWith(displayMode: mode)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '줄 하이라이트는 앞·현재·뒤 세 줄만 크게 보여 줍니다.',
          style: AppTypography.bodyMuted,
        ),
        const SizedBox(height: 8),

        _SettingSwitch(
          title: '굵게',
          value: settings.boldText,
          onLabel: '켜짐 — 가사를 더 굵게 표시',
          offLabel: '꺼짐 — 기본 굵기',
          onChanged: (v) => onChanged(settings.copyWith(boldText: v)),
        ),
        _SettingSwitch(
          title: '한 글자씩 따라가기',
          value: settings.showSyllableSweep,
          onLabel: '켜짐 — 부른 글자가 왼쪽부터 밝아집니다(싱크 가사 필요)',
          offLabel: '꺼짐 — 줄 단위로만 표시',
          onChanged: (v) => onChanged(settings.copyWith(showSyllableSweep: v)),
        ),
        _SettingSwitch(
          title: '무대 EQ 애니메이션',
          value: settings.showEqMeter,
          onLabel: '켜짐 — 가사 아래에 음악 반응 미터 표시',
          offLabel: '꺼짐 — 움직임이 신경 쓰이면 꺼 둘 수 있습니다',
          onChanged: (v) => onChanged(settings.copyWith(showEqMeter: v)),
        ),
      ],
    );
  }
}

/// 상태를 색·스위치만으로 구분하지 않도록 켜짐/꺼짐 텍스트를 병기한다.
class _SettingSwitch extends StatelessWidget {
  final String title;
  final bool value;
  final String onLabel;
  final String offLabel;
  final ValueChanged<bool> onChanged;

  const _SettingSwitch({
    required this.title,
    required this.value,
    required this.onLabel,
    required this.offLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: title,
      toggled: value,
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text(title, style: AppTypography.body),
        subtitle: Text(
          value ? onLabel : offLabel,
          style: AppTypography.bodyMuted,
        ),
        value: value,
        activeThumbColor: AppColors.primary,
        onChanged: onChanged,
      ),
    );
  }
}

class _AppDisplaySection extends StatelessWidget {
  const _AppDisplaySection();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppDisplaySettings>(
      valueListenable: AppDisplayController.notifier,
      builder: (context, display, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('앱 화면', style: AppTypography.listTitle),
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
