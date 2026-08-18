// file: test/widgets/settings_panel_test.dart
//
// 설정 > AI·작곡의 마스터 스위치. 마스터가 꺼져 있으면 하위 두 스위치를
// 만질 수 없어야 한다 — 켤 수 없는 스위치를 켜는 시늉만 하면 사용자는
// "켰는데 안 된다"로 읽는다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/prompter_settings.dart';
import 'package:singpromfter_app/theme/app_theme.dart';
import 'package:singpromfter_app/widgets/settings_panel.dart';

Widget _panel(
  PrompterSettings settings,
  ValueChanged<PrompterSettings> onChanged,
) => MaterialApp(
  theme: AppTheme.dark(),
  home: Scaffold(
    body: SettingsPanel(
      settings: settings,
      onSettingsChanged: onChanged,
      onUpdateYtDlp: () {},
      onExportBackup: () {},
      onImportBackup: () {},
      onRunMaintenance: () {},
      onCustomFontSize: () {},
      onAccessibilityPreset: (_) {},
    ),
  ),
);

/// AI 분류 탭으로 이동한다 — 설정 화면은 좌측 사이드 메뉴로 나뉜다.
Future<void> _openAiTab(WidgetTester tester) async {
  await tester.tap(find.text('AI·작곡'));
  await tester.pumpAndSettle();
}

SwitchListTile _switchTitled(WidgetTester tester, String title) =>
    tester.widget<SwitchListTile>(
      find.ancestor(
        of: find.text(title),
        matching: find.byType(SwitchListTile),
      ),
    );

void main() {
  testWidgets('마스터가 꺼져 있으면 하위 스위치가 비활성', (tester) async {
    await tester.pumpWidget(
      _panel(const PrompterSettings(aiEnabled: false), (_) {}),
    );
    await _openAiTab(tester);

    expect(_switchTitled(tester, 'AI 기능 전체 사용').onChanged, isNotNull);
    expect(_switchTitled(tester, '로컬AI 사용').onChanged, isNull);
    expect(_switchTitled(tester, '클라우드AI 사용').onChanged, isNull);
  });

  testWidgets('마스터를 켜면 하위 스위치를 만질 수 있다', (tester) async {
    await tester.pumpWidget(
      _panel(
        const PrompterSettings(aiEnabled: true, localAiEnabled: true),
        (_) {},
      ),
    );
    await _openAiTab(tester);

    expect(_switchTitled(tester, '로컬AI 사용').onChanged, isNotNull);
    expect(_switchTitled(tester, '클라우드AI 사용').onChanged, isNotNull);
  });

  testWidgets('마스터를 끄면 하위 값은 건드리지 않고 마스터만 내려간다', (tester) async {
    PrompterSettings? saved;
    await tester.pumpWidget(
      _panel(
        const PrompterSettings(
          aiEnabled: true,
          localAiEnabled: true,
          cloudAiEnabled: true,
        ),
        (s) => saved = s,
      ),
    );
    await _openAiTab(tester);

    await tester.tap(find.text('AI 기능 전체 사용'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.aiEnabled, isFalse);
    // 하위 값을 지우지 않는다 — 다시 켰을 때 쓰던 조합이 돌아와야 한다.
    expect(saved!.localAiEnabled, isTrue);
    expect(saved!.cloudAiEnabled, isTrue);
    expect(saved!.localAiActive, isFalse);
  });

  testWidgets('하위가 전부 꺼진 상태에서 마스터를 켜면 설치 안내를 거쳐 로컬이 함께 켜진다', (
    tester,
  ) async {
    PrompterSettings? saved;
    await tester.pumpWidget(
      _panel(const PrompterSettings(), (s) => saved = s),
    );
    await _openAiTab(tester);

    await tester.tap(find.text('AI 기능 전체 사용'));
    await tester.pumpAndSettle();

    // 확인 다이얼로그가 뜬다 — 서버가 필요하다는 안내를 건너뛰지 않는다.
    expect(find.text('로컬 AI 기능 안내'), findsOneWidget);
    expect(saved, isNull);

    await tester.tap(find.text('켜기'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.aiEnabled, isTrue);
    expect(saved!.localAiEnabled, isTrue);
    // 클라우드는 가사가 외부로 나가므로 자동으로 켜지 않는다.
    expect(saved!.cloudAiEnabled, isFalse);
  });
}
