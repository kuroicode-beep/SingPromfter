// file: test/models/routine_step_spec_test.dart
//
// 따라하기 실행 스펙 검증 — 17개 스텝 완전성, 호흡 값, 음역-피아노 파일 매핑.
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/constants/voice_clips.dart';
import 'package:singpromfter_app/models/routine_step_spec.dart';
import 'package:singpromfter_app/models/vocal_routine.dart';

void main() {
  test('모든 루틴 스텝에 실행 스펙이 있다', () {
    for (final routine in VocalRoutines.all) {
      for (final step in routine.steps) {
        final spec = RoutineStepSpecs.byStepId(step.id);
        expect(spec, isNotNull, reason: '스펙 누락: ${step.id}');
        expect(VoiceClips.byId(spec!.announceClipId), isNotNull,
            reason: '안내 클립 누락: ${spec.announceClipId}');
      }
    }
  });

  test('스펙 테이블에 루틴에 없는 유령 스텝이 없다', () {
    final known = {
      for (final r in VocalRoutines.all)
        for (final s in r.steps) s.id,
    };
    for (final id in RoutineStepSpecs.all.keys) {
      expect(known.contains(id), isTrue, reason: '유령 스펙: $id');
    }
  });

  test('호흡 블록 값은 전부 양수이고 박자가 성립한다', () {
    for (final entry in RoutineStepSpecs.all.entries) {
      for (final block in entry.value.breathing) {
        expect(block.inhaleBeats, greaterThan(0), reason: entry.key);
        expect(block.exhaleBeats, greaterThan(0), reason: entry.key);
        expect(block.holdBeats, greaterThanOrEqualTo(0), reason: entry.key);
        expect(block.reps, greaterThan(0), reason: entry.key);
        expect(block.bpm, greaterThan(0), reason: entry.key);
        expect(block.beat.inMilliseconds, 60000 ~/ block.bpm);
      }
    }
  });

  test('호흡 스텝은 호흡 종류에만, 스케일 스펙은 스케일 종류에만 붙는다', () {
    for (final routine in VocalRoutines.all) {
      for (final step in routine.steps) {
        final spec = RoutineStepSpecs.byStepId(step.id)!;
        if (spec.breathing.isNotEmpty) {
          expect(step.kind, RoutineStepKind.breathing, reason: step.id);
        }
        if (spec.scale != null) {
          expect(step.kind, RoutineStepKind.scale, reason: step.id);
        }
      }
    }
  });

  group('TrainingVoiceRange', () {
    test('저장값 해석 — 기본 남성, female만 여성', () {
      expect(TrainingVoiceRange.fromStorage(null), TrainingVoiceRange.male);
      expect(TrainingVoiceRange.fromStorage('male'), TrainingVoiceRange.male);
      expect(TrainingVoiceRange.fromStorage('없는값'), TrainingVoiceRange.male);
      expect(
        TrainingVoiceRange.fromStorage('female'),
        TrainingVoiceRange.female,
      );
    });

    test('음역 루트는 생성된 피아노 런 파일 범위(48~65) 안이다', () {
      for (final range in TrainingVoiceRange.values) {
        expect(range.rootLow, greaterThanOrEqualTo(48), reason: range.name);
        expect(range.rootHigh, lessThanOrEqualTo(65), reason: range.name);
        expect(range.rootLow, lessThan(range.rootHigh), reason: range.name);
      }
      // 여성은 남성보다 완전4도(+5반음) 위.
      expect(
        TrainingVoiceRange.female.rootLow - TrainingVoiceRange.male.rootLow,
        5,
      );
    });
  });
}
