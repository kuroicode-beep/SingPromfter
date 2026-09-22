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

import '../fakes/semantics_count.dart';

Widget _panel(
  PrompterSettings settings,
  ValueChanged<PrompterSettings> onChanged, {
  List<String> recordingDevices = const [],
  String? recordingDeviceStatus,
  bool micTesting = false,
  bool backingTesting = false,
}) => MaterialApp(
  theme: AppTheme.dark(),
  home: Scaffold(
    body: SettingsPanel(
      settings: settings,
      onSettingsChanged: onChanged,
      recordingDevices: recordingDevices,
      recordingDeviceStatus: recordingDeviceStatus,
      micTesting: micTesting,
      micLevel: 0.5,
      micLevelLabel: '입력 좋음',
      backingTesting: backingTesting,
      backingLevel: 0.4,
      backingLevelLabel: '입력 좋음',
      onUpdateYtDlp: () {},
      onExportBackup: () {},
      onImportBackup: () {},
      onRunMaintenance: () {},
      onCustomFontSize: () {},
      onAccessibilityPreset: (_) {},
    ),
  ),
);

/// 녹음 탭으로 이동한다.
Future<void> _openRecordingTab(WidgetTester tester) async {
  await tester.tap(find.text('녹음'));
  await tester.pumpAndSettle();
}

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

  group('녹음 > 2채널 (v5.11.0)', () {
    const mic = '마이크(RØDE NT-USB Mini)';
    const pc = 'MAIN L/R(BEHRINGER FLOW 8 (Streaming))';

    testWidgets('반주 입력 장치는 기본이 「사용 안 함」', (tester) async {
      await tester.pumpWidget(
        _panel(
          const PrompterSettings(recordingDevice: mic),
          (_) {},
          recordingDevices: const [mic, pc],
        ),
      );
      await _openRecordingTab(tester);

      expect(find.text('반주(PC 재생) 입력 장치 — 2채널 녹음'), findsOneWidget);
      expect(find.text('사용 안 함 (보컬 1채널)'), findsWidgets);
    });

    testWidgets('테스트 중이면 채널 이름을 글자로 붙인 미터가 둘', (tester) async {
      await tester.pumpWidget(
        _panel(
          const PrompterSettings(
            recordingDevice: mic,
            recordingBackingDevice: pc,
          ),
          (_) {},
          recordingDevices: const [mic, pc],
          micTesting: true,
          backingTesting: true,
        ),
      );
      await _openRecordingTab(tester);

      expect(find.text('보컬'), findsOneWidget);
      expect(find.text('반주'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    });

    testWidgets('반주 채널이 안 열리면 그 사실을 글자로 알린다', (tester) async {
      await tester.pumpWidget(
        _panel(
          const PrompterSettings(
            recordingDevice: mic,
            recordingBackingDevice: pc,
          ),
          (_) {},
          recordingDevices: const [mic, pc],
          micTesting: true,
          backingTesting: false,
        ),
      );
      await _openRecordingTab(tester);

      expect(find.textContaining('반주 채널을 열지 못했습니다'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });

  group('녹음 > 녹음 지연 보정 (v5.17.0)', () {
    const minusKey = Key('recordingLatencyMinus');
    const plusKey = Key('recordingLatencyPlus');
    const resetKey = Key('recordingLatencyReset');
    const valueKey = Key('recordingLatencyValue');

    /// 누른 결과가 다시 패널로 돌아오는 호스트 — 실제 화면처럼 값이 쌓인다.
    Widget host(PrompterSettings initial, List<PrompterSettings> changes) {
      var current = initial;
      return StatefulBuilder(
        builder: (context, setState) => _panel(current, (next) {
          changes.add(next);
          setState(() => current = next);
        }),
      );
    }

    Future<void> tapKey(WidgetTester tester, Key key) async {
      await tester.ensureVisible(find.byKey(key));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
    }

    String valueText(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(valueKey)).data!;

    testWidgets('기본은 「0 ms (보정 없음)」 — +5 ms를 누를 때마다 5씩 오른다', (tester) async {
      final changes = <PrompterSettings>[];
      await tester.pumpWidget(host(const PrompterSettings(), changes));
      await _openRecordingTab(tester);

      expect(find.text('녹음 지연 보정'), findsOneWidget);
      expect(valueText(tester), '0 ms (보정 없음)');

      await tapKey(tester, plusKey);
      expect(changes.single.recordingLatencyMs, 5);
      expect(valueText(tester), '+5 ms');

      for (var i = 0; i < 6; i++) {
        await tapKey(tester, plusKey);
      }
      expect(changes.last.recordingLatencyMs, 35);
      expect(valueText(tester), '+35 ms');
      // 다른 녹음 설정은 건드리지 않는다.
      expect(changes.last.recordingGain, 1.0);
      expect(changes.last.recordingDevice, isNull);
    });

    testWidgets('−5 ms는 5씩 내리고(음수까지), [0으로 되돌리기]는 한 번에 0으로', (tester) async {
      final changes = <PrompterSettings>[];
      await tester.pumpWidget(
        host(const PrompterSettings(recordingLatencyMs: 5), changes),
      );
      await _openRecordingTab(tester);

      await tapKey(tester, minusKey);
      expect(valueText(tester), '0 ms (보정 없음)');
      await tapKey(tester, minusKey);
      expect(changes.last.recordingLatencyMs, -5);
      expect(valueText(tester), '−5 ms');

      await tapKey(tester, resetKey);
      expect(changes.last.recordingLatencyMs, 0);
      expect(valueText(tester), '0 ms (보정 없음)');
    });

    testWidgets('범위 끝 — 값은 그대로고 저장도 돌지 않는다. 이유는 글자로 말한다', (tester) async {
      final changes = <PrompterSettings>[];
      await tester.pumpWidget(
        host(const PrompterSettings(recordingLatencyMs: 300), changes),
      );
      await _openRecordingTab(tester);
      expect(valueText(tester), '+300 ms (최대)');

      await tapKey(tester, plusKey);
      expect(changes, isEmpty);
      expect(valueText(tester), '+300 ms (최대)');

      await tapKey(tester, minusKey);
      expect(changes.single.recordingLatencyMs, 295);
    });

    testWidgets('이미 0이면 [0으로 되돌리기]는 저장을 돌리지 않는다', (tester) async {
      final changes = <PrompterSettings>[];
      await tester.pumpWidget(host(const PrompterSettings(), changes));
      await _openRecordingTab(tester);
      await tapKey(tester, resetKey);
      expect(changes, isEmpty);
    });

    testWidgets('버튼 셋 다 높이 50px 이상·글자 12px 이상, 글자 라벨', (tester) async {
      await tester.pumpWidget(_panel(const PrompterSettings(), (_) {}));
      await _openRecordingTab(tester);

      for (final key in [minusKey, plusKey, resetKey]) {
        final size = tester.getSize(find.byKey(key));
        expect(size.height, greaterThanOrEqualTo(50), reason: '$key');
        expect(size.width, greaterThanOrEqualTo(50), reason: '$key');
        final label = tester.widget<Text>(
          find.descendant(of: find.byKey(key), matching: find.byType(Text)),
        );
        expect(label.style!.fontSize, greaterThanOrEqualTo(12), reason: '$key');
        expect(label.style!.color, AppColors.onSurface, reason: '$key');
      }
      expect(find.text('−5 ms'), findsOneWidget);
      expect(find.text('+5 ms'), findsOneWidget);
      expect(find.text('0으로 되돌리기'), findsOneWidget);
    });

    testWidgets('도움말 — 언제 올리는지, 언제부터 먹는지 글자로 적는다', (tester) async {
      await tester.pumpWidget(_panel(const PrompterSettings(), (_) {}));
      await _openRecordingTab(tester);
      expect(
        find.textContaining('이어붙인 보컬이 반주보다 늦게 들리면 값을 올리세요'),
        findsOneWidget,
      );
      expect(find.textContaining('새로 받는 녹음부터 적용됩니다'), findsOneWidget);
    });

    testWidgets('화면 읽기 라벨은 기호(+·−)를 말로 푼다', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _panel(const PrompterSettings(recordingLatencyMs: -20), (_) {}),
      );
      await _openRecordingTab(tester);
      // 패널의 글자들은 한 노드로 합쳐 읽힌다 — 제목 바로 뒤에 값이 말로 이어진다.
      expect(
        find.bySemanticsLabel(RegExp('녹음 지연 보정\n마이너스 20 밀리초')),
        findsWidgets,
      );
      expect(find.bySemanticsLabel(RegExp('−20 ms')), findsNothing);
      expect(find.bySemanticsLabel('녹음 지연 보정 5밀리초 늘리기'), findsOneWidget);
      expect(find.bySemanticsLabel('녹음 지연 보정 5밀리초 줄이기'), findsOneWidget);
      expect(find.bySemanticsLabel('녹음 지연 보정을 0으로 되돌리기'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('🔴 값이 바뀌어도 시맨틱스 노드 수가 그대로다 — 글자만 바뀐다', (tester) async {
      // 생겼다 사라지는 접근성 노드가 엔진 크래시를 냈다(center_alert.dart 머리말).
      // 범위 끝에서 버튼을 끄거나 0일 때 되돌리기를 숨기면 여기서 걸린다.
      final handle = tester.ensureSemantics();
      Future<int> nodesAt(int ms) async {
        await tester.pumpWidget(
          _panel(PrompterSettings(recordingLatencyMs: ms), (_) {}),
        );
        await tester.pumpAndSettle();
        return countSemanticsNodes(tester);
      }

      await nodesAt(0);
      await _openRecordingTab(tester);
      final zero = await nodesAt(0);
      expect(await nodesAt(35), zero);
      expect(await nodesAt(-20), zero);
      expect(await nodesAt(300), zero);
      expect(await nodesAt(-300), zero);
      handle.dispose();
    });
  });

  group('녹음 > 입력 장치 「자동」 상태 줄 (v5.17.0)', () {
    const razer = '마이크(Razer Barracuda X 2.4)';
    const rode = '마이크(RØDE NT-USB Mini)';

    testWidgets('자동이 지금 어느 장치를 쓰는지 글자로 보여 준다', (tester) async {
      const status = '자동 — 지금은 $rode (소리 확인됨 · 소리 없는 장치 1개 건너뜀)';
      await tester.pumpWidget(
        _panel(
          const PrompterSettings(),
          (_) {},
          recordingDevices: const [razer, rode],
          recordingDeviceStatus: status,
        ),
      );
      await _openRecordingTab(tester);

      expect(find.text(status), findsOneWidget);
      // 「첫 번째 장치」는 더 이상 사실이 아니다 — 소리가 들어오는 마이크를 고른다.
      expect(find.text('자동 (소리가 들어오는 마이크)'), findsWidgets);
      expect(find.textContaining('첫 번째 장치'), findsNothing);
    });

    testWidgets('화면이 문구를 안 줘도 줄은 비지 않는다 — 목록과 설정으로 만든다', (tester) async {
      await tester.pumpWidget(
        _panel(
          const PrompterSettings(),
          (_) {},
          recordingDevices: const [razer, rode],
        ),
      );
      await _openRecordingTab(tester);
      expect(find.textContaining('자동 — 지금은 $razer'), findsOneWidget);

      await tester.pumpWidget(
        _panel(
          const PrompterSettings(recordingDevice: rode),
          (_) {},
          recordingDevices: const [razer, rode],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('직접 고른 장치를 그대로 씁니다'), findsOneWidget);
    });

    testWidgets('🔴 상태가 바뀌어도 시맨틱스 노드 수가 그대로다 — 글자만 바뀐다', (tester) async {
      // 생겼다 사라지는 접근성 노드가 엔진 크래시를 냈다(center_alert.dart 머리말).
      final handle = tester.ensureSemantics();
      Future<int> nodesWith(String? status) async {
        await tester.pumpWidget(
          _panel(
            const PrompterSettings(),
            (_) {},
            recordingDevices: const [razer, rode],
            recordingDeviceStatus: status,
          ),
        );
        await tester.pumpAndSettle();
        return countSemanticsNodes(tester);
      }

      await nodesWith(null);
      await _openRecordingTab(tester);
      final idle = await nodesWith(null);
      final picked = await nodesWith('자동 — 지금은 $rode (소리 확인됨)');
      final silent = await nodesWith(
        '자동 — 소리가 들어오는 마이크를 찾지 못했습니다 (확인한 장치: $razer, $rode)',
      );
      // 빈 문자열을 받아도 줄(노드)은 남는다.
      final empty = await nodesWith('');

      expect(picked, idle);
      expect(silent, idle);
      expect(empty, idle);
      handle.dispose();
    });
  });
}
