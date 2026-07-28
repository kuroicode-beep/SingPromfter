import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/widgets/prompter_drawer.dart';

// 하단 조작판 드로어 — 손잡이는 항상 보이고, 접히면 진짜로 죽는다.
void main() {
  Widget wrap({required bool open, ValueChanged<bool>? onChanged}) => MaterialApp(
    home: Scaffold(
      body: PrompterDrawer(
        open: open,
        onOpenChanged: onChanged ?? (_) {},
        child: const SizedBox(height: 100, child: Text('조작 내용')),
      ),
    ),
  );

  testWidgets('닫혀 있어도 손잡이는 보인다 — 못 찾는 버튼이면 안 된다', (tester) async {
    await tester.pumpWidget(wrap(open: false));
    await tester.pumpAndSettle();
    expect(find.text('조작판 열기'), findsOneWidget);
  });

  testWidgets('열리면 손잡이 라벨이 바뀐다', (tester) async {
    await tester.pumpWidget(wrap(open: true));
    await tester.pumpAndSettle();
    expect(find.text('조작판 닫기'), findsOneWidget);
  });

  testWidgets('손잡이를 누르면 반대 상태를 알린다', (tester) async {
    bool? got;
    await tester.pumpWidget(wrap(open: false, onChanged: (v) => got = v));
    await tester.pumpAndSettle();
    await tester.tap(find.text('조작판 열기'));
    await tester.pump();
    expect(got, isTrue);
  });

  testWidgets('손잡이는 최소 터치 타깃을 지킨다', (tester) async {
    await tester.pumpWidget(wrap(open: false));
    await tester.pumpAndSettle();
    final size = tester.getSize(find.text('조작판 열기'));
    expect(size.height, lessThan(drawerHandleHeight));
    final handle = tester.getSize(
      find.ancestor(
        of: find.text('조작판 열기'),
        matching: find.byType(InkWell),
      ).first,
    );
    expect(handle.height, greaterThanOrEqualTo(drawerHandleHeight));
  });

  testWidgets('닫히면 본체가 높이를 차지하지 않는다', (tester) async {
    await tester.pumpWidget(wrap(open: true));
    await tester.pumpAndSettle();
    final openHeight = tester.getSize(find.byType(PrompterDrawer)).height;

    await tester.pumpWidget(wrap(open: false));
    await tester.pumpAndSettle();
    final closedHeight = tester.getSize(find.byType(PrompterDrawer)).height;

    expect(closedHeight, lessThan(openHeight));
  });

  testWidgets('닫히면 본체가 시맨틱에서 빠진다', (tester) async {
    await tester.pumpWidget(wrap(open: false));
    await tester.pumpAndSettle();
    final excluded = tester.widget<ExcludeSemantics>(
      find
          .descendant(
            of: find.byType(PrompterDrawer),
            matching: find.byType(ExcludeSemantics),
          )
          .last,
    );
    expect(excluded.excluding, isTrue);
  });

  testWidgets('열리면 본체가 다시 살아난다', (tester) async {
    await tester.pumpWidget(wrap(open: true));
    await tester.pumpAndSettle();
    final ignoring = tester.widget<IgnorePointer>(
      find
          .descendant(
            of: find.byType(PrompterDrawer),
            matching: find.byType(IgnorePointer),
          )
          .last,
    );
    expect(ignoring.ignoring, isFalse);
  });

  testWidgets('고정 높이를 주면 그 높이를 쓴다 — 무대 밴드 계산의 전제', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrompterDrawer(
            open: true,
            onOpenChanged: (_) {},
            fixedHeight: 132,
            child: const SizedBox(height: 500),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .getSize(
            find
                .descendant(
                  of: find.byType(SizeTransition),
                  matching: find.byType(SizedBox),
                )
                .first,
          )
          .height,
      132,
    );
  });
}
