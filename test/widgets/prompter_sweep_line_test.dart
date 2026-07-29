import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/widgets/prompter_sweep_line.dart';

// 진행률 → 이미 부른 구간. 글자 수가 아니라 글리프 폭에 비례해야 한다.
void main() {
  TextPainter painterFor(String text, {double maxWidth = 1000}) =>
      TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(fontSize: 20, fontFamily: 'Roboto'),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth);

  double filledWidth(SweepGeometry g) =>
      g.filled.fold<double>(0, (sum, r) => sum + r.width);

  group('sweepGeometryFor', () {
    test('진행률 0이면 아무것도 안 켠다', () {
      final p = painterFor('가나다라마바사아');
      expect(sweepGeometryFor(painter: p, fraction: 0).filled, isEmpty);
    });

    test('진행률 1이면 줄 전체를 켠다', () {
      final p = painterFor('가나다라마바사아');
      final g = sweepGeometryFor(painter: p, fraction: 1);
      expect(g.filled, hasLength(1));
      expect(filledWidth(g), closeTo(p.computeLineMetrics().first.width, 0.5));
    });

    test('진행률이 커질수록 켜지는 폭이 줄지 않는다', () {
      final p = painterFor('가나다라마바사아자차카타');
      var previous = 0.0;
      for (var i = 0; i <= 20; i++) {
        final width = filledWidth(
          sweepGeometryFor(painter: p, fraction: i / 20),
        );
        expect(width, greaterThanOrEqualTo(previous - 0.001), reason: 'i=$i');
        previous = width;
      }
    });

    test('중간 진행률은 줄 폭 안에 머문다', () {
      final p = painterFor('가나다라마바사아');
      final total = p.computeLineMetrics().first.width;
      final width = filledWidth(sweepGeometryFor(painter: p, fraction: 0.5));
      expect(width, greaterThan(0));
      expect(width, lessThan(total));
    });

    test('문자 경계로 내림 스냅한다 — 글자가 반쯤 밝아지지 않게', () {
      final p = painterFor('가나다라');
      // 아주 조금씩 올려도 켜지는 폭은 계단식으로만 늘어난다.
      final widths = <double>{};
      for (var i = 0; i <= 100; i++) {
        widths.add(filledWidth(sweepGeometryFor(painter: p, fraction: i / 100)));
      }
      // 4글자 → 경계는 많아야 다섯 종류(0 포함).
      expect(widths.length, lessThanOrEqualTo(5));
    });

    test('줄바꿈되면 구간이 여러 개가 된다', () {
      // 좁은 폭으로 강제로 줄바꿈시킨다.
      final p = painterFor('가나다라마바사아자차카타파하', maxWidth: 60);
      expect(p.computeLineMetrics().length, greaterThan(1));

      final g = sweepGeometryFor(painter: p, fraction: 1);
      expect(g.filled.length, p.computeLineMetrics().length);
    });

    test('줄바꿈 중간 진행률은 앞 줄을 먼저 채운다', () {
      final p = painterFor('가나다라마바사아자차카타파하', maxWidth: 60);
      final metrics = p.computeLineMetrics();
      final g = sweepGeometryFor(painter: p, fraction: 0.99);
      // 마지막 줄만 부분적으로 남는다.
      expect(g.filled.length, metrics.length);
      for (var i = 0; i < g.filled.length - 1; i++) {
        expect(g.filled[i].width, closeTo(metrics[i].width, 0.5));
      }
    });

    test('빈 문자열이어도 깨지지 않는다', () {
      final p = painterFor('');
      expect(
        () => sweepGeometryFor(painter: p, fraction: 0.5),
        returnsNormally,
      );
    });
  });

  group('SweepGeometry.sameAs', () {
    test('같은 사각형이면 같다고 본다 — 불필요한 리페인트를 막는 판정', () {
      const a = SweepGeometry([Rect.fromLTRB(0, 0, 10, 20)]);
      const b = SweepGeometry([Rect.fromLTRB(0, 0, 10, 20)]);
      expect(a.sameAs(b), isTrue);
    });

    test('폭이 다르면 다르다', () {
      const a = SweepGeometry([Rect.fromLTRB(0, 0, 10, 20)]);
      const b = SweepGeometry([Rect.fromLTRB(0, 0, 11, 20)]);
      expect(a.sameAs(b), isFalse);
    });

    test('개수가 다르면 다르다', () {
      const a = SweepGeometry([Rect.fromLTRB(0, 0, 10, 20)]);
      expect(a.sameAs(SweepGeometry.empty), isFalse);
    });
  });
}
