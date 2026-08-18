// file: test/utils/ai_gate_test.dart
//
// AI 게이트 진리표. 마스터가 꺼져 있으면 하위 스위치가 켜져 있어도
// 전부 차단돼야 한다 — 이게 마스터 도입의 유일한 존재 이유다.
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/prompter_settings.dart';
import 'package:singpromfter_app/utils/ai_gate.dart';

AiGate gateOf({
  required bool ai,
  required bool local,
  required bool cloud,
}) =>
    AiGate(PrompterSettings(
      aiEnabled: ai,
      localAiEnabled: local,
      cloudAiEnabled: cloud,
    ));

void main() {
  group('AiGate 진리표(마스터 × 로컬 × 클라우드 8조합)', () {
    test('마스터가 꺼지면 하위가 켜져 있어도 전부 차단', () {
      for (final local in [false, true]) {
        for (final cloud in [false, true]) {
          final gate = gateOf(ai: false, local: local, cloud: cloud);
          expect(gate.local, isFalse, reason: 'local=$local cloud=$cloud');
          expect(gate.cloud, isFalse, reason: 'local=$local cloud=$cloud');
          expect(gate.composeTab, AiVisibility.labeledOff);
          expect(gate.sttLyricsButton, AiVisibility.hidden);
          expect(gate.pitchCheckButton, AiVisibility.hidden);
          expect(gate.correctButton, AiVisibility.hidden);
          expect(gate.separatorChip, AiVisibility.hidden);
          expect(gate.deepSeekOption, AiVisibility.labeledOff);
        }
      }
    });

    test('마스터만 켜고 하위가 모두 꺼지면 여전히 차단', () {
      final gate = gateOf(ai: true, local: false, cloud: false);
      expect(gate.local, isFalse);
      expect(gate.cloud, isFalse);
      expect(gate.sttLyricsButton, AiVisibility.hidden);
      expect(gate.deepSeekOption, AiVisibility.labeledOff);
    });

    test('마스터 + 로컬이면 로컬 진입점만 열린다', () {
      final gate = gateOf(ai: true, local: true, cloud: false);
      expect(gate.local, isTrue);
      expect(gate.cloud, isFalse);
      expect(gate.composeTab, AiVisibility.shown);
      expect(gate.sttLyricsButton, AiVisibility.shown);
      expect(gate.pitchCheckButton, AiVisibility.shown);
      expect(gate.correctButton, AiVisibility.shown);
      expect(gate.separatorChip, AiVisibility.shown);
      expect(gate.deepSeekOption, AiVisibility.labeledOff);
    });

    test('마스터 + 클라우드면 DeepSeek만 열린다', () {
      final gate = gateOf(ai: true, local: false, cloud: true);
      expect(gate.deepSeekOption, AiVisibility.shown);
      expect(gate.composeTab, AiVisibility.labeledOff);
      expect(gate.separatorChip, AiVisibility.hidden);
    });

    test('셋 다 켜지면 전부 열린다', () {
      final gate = gateOf(ai: true, local: true, cloud: true);
      expect(gate.composeTab, AiVisibility.shown);
      expect(gate.sttLyricsButton, AiVisibility.shown);
      expect(gate.deepSeekOption, AiVisibility.shown);
    });
  });

  group('탭은 숨기지 않는다', () {
    test('작곡 탭은 꺼져도 labeledOff — 고정 내비의 공간 기준점이라 유지한다', () {
      expect(gateOf(ai: false, local: true, cloud: true).composeTab,
          AiVisibility.labeledOff);
    });
  });
}
