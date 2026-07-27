import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/theme/app_theme.dart';
import 'package:singpromfter_app/widgets/prompter_progress_bar.dart';

/// 전체화면 프롬프터가 재생 위치를 "값 스냅샷"이 아니라 리스너블로 받도록
/// 바꾼 뒤의 회귀 방지 테스트.
///
/// 이전 구조에서는 position이 라우트 생성 시점에 값으로 고정돼
/// 전체화면 진행바가 멈춰 있었다. 여기서는 알림만으로 표시가 갱신되는지 본다.
void main() {
  testWidgets('위치 리스너블이 바뀌면 진행바 시간 표시가 갱신된다', (tester) async {
    final position = ValueNotifier<Duration>(Duration.zero);
    addTearDown(position.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: ValueListenableBuilder<Duration>(
            valueListenable: position,
            builder: (context, value, _) => PrompterProgressBar(
              position: value,
              duration: const Duration(minutes: 3),
              enabled: true,
              onSeek: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('03:00'), findsOneWidget);

    // 부모 setState 없이 리스너블만 갱신한다 — 전체화면 라우트와 같은 상황.
    position.value = const Duration(seconds: 95);
    await tester.pump();

    expect(find.text('01:35'), findsOneWidget);
    expect(find.text('00:00'), findsNothing);
  });

  testWidgets('길이를 모르면 00:00으로 표시하고 예외를 내지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: PrompterProgressBar(
            position: Duration.zero,
            duration: Duration.zero,
            enabled: false,
            onSeek: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('00:00'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
