// file: test/fakes/semantics_count.dart
//
// 시맨틱스 트리의 노드 수를 센다 — 「상태가 바뀌어도 노드가 생기거나 사라지지
// 않는다」를 고정하는 테스트용.
//
// 왜 세는가: 떴다 사라지는 접근성 노드가 Flutter 엔진 크래시를 냈다(2026-09-22,
// lib/widgets/center_alert.dart 머리말). 라벨만 확인하는 테스트로는 노드가 통째로
// 빠졌다 들어오는 것을 못 잡는다 — 크기 0인 노드는 라벨이 있어도 트리에서 빠진다.
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 지금 시맨틱스 트리의 노드 수. 부르기 전에 `tester.ensureSemantics()`가 필요하다.
int countSemanticsNodes(WidgetTester tester) {
  var count = 0;
  void visit(SemanticsNode node) {
    count++;
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  final owner = tester.binding.renderViews.first.owner!.semanticsOwner!;
  visit(owner.rootSemanticsNode!);
  return count;
}
