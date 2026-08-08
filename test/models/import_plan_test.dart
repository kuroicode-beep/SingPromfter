import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/import_plan.dart';
import 'package:singpromfter_app/models/track_variant.dart';

// 링크 하나가 만들 반주들의 슬롯 배치 규칙.
void main() {
  group('빈 곡에 새로 만들 때', () {
    test('기본 구성은 원곡 1 / MR 2 / 키조절 3', () {
      final result = resolveImportPlan(plan: const ImportPlan.full());

      expect(result.tracks.map((t) => t.slot), [1, 2, 3]);
      expect(result.tracks.map((t) => t.variant), [
        TrackVariant.original,
        TrackVariant.mr,
        TrackVariant.pitch,
      ]);
      expect(result.dropped, isEmpty);
    });

    test('키조절본에 반음이 구워진다', () {
      final result = resolveImportPlan(
        plan: const ImportPlan.full(semitones: -2),
      );
      final pitch = result.forVariant(TrackVariant.pitch)!;
      expect(pitch.bakedSemitones, -2);
      expect(result.forVariant(TrackVariant.mr)!.bakedSemitones, 0);
    });

    test('기존 동작(single)은 MR 한 개만', () {
      final result = resolveImportPlan(plan: const ImportPlan.single());
      expect(result.tracks, hasLength(1));
      expect(result.tracks.first.variant, TrackVariant.mr);
      expect(result.dropped, isEmpty);
    });

    test('키조절 0은 만들지 않는다', () {
      final result = resolveImportPlan(
        plan: const ImportPlan(pitchSemitones: 0),
      );
      expect(result.forVariant(TrackVariant.pitch), isNull);
    });
  });

  group('이미 찬 슬롯이 있을 때', () {
    test('기본 슬롯이 차 있으면 남은 낮은 슬롯으로 간다', () {
      final result = resolveImportPlan(
        plan: const ImportPlan(makeOriginal: true, makeInstrumental: true),
        occupiedSlots: {1},
      );
      // 원곡의 기본 슬롯 1이 차 있으니 2로, MR은 자기 기본 2가 차서 3으로.
      expect(result.forVariant(TrackVariant.original)!.slot, 2);
      expect(result.forVariant(TrackVariant.mr)!.slot, 3);
    });

    test('슬롯이 모자라면 우선순위가 낮은 쪽이 빠진다', () {
      final result = resolveImportPlan(
        plan: const ImportPlan.full(),
        occupiedSlots: {1, 2, 3},
      );
      // 남은 자리는 4번 하나 — 원곡만 들어가고 나머지는 dropped.
      expect(result.tracks, hasLength(1));
      expect(result.tracks.first.variant, TrackVariant.original);
      expect(result.dropped, [TrackVariant.mr, TrackVariant.pitch]);
    });

    test('자리가 하나도 없으면 전부 dropped', () {
      final result = resolveImportPlan(
        plan: const ImportPlan.full(),
        occupiedSlots: {1, 2, 3, 4},
      );
      expect(result.tracks, isEmpty);
      expect(result.dropped, hasLength(3));
    });
  });

  test('슬롯은 항상 오름차순으로 정렬된다', () {
    final result = resolveImportPlan(plan: const ImportPlan.full());
    final slots = result.tracks.map((t) => t.slot).toList();
    final sorted = [...slots]..sort();
    expect(slots, sorted);
  });

  test('키조절 라벨을 바꿔 넣을 수 있다', () {
    final result = resolveImportPlan(
      plan: const ImportPlan.full(),
      pitchLabel: '키조절 2키 낮춤',
    );
    expect(result.forVariant(TrackVariant.pitch)!.label, '키조절 2키 낮춤');
  });

  test('ImportPlan JSON 왕복', () {
    const plan = ImportPlan(
      makeOriginal: true,
      makeInstrumental: false,
      pitchSemitones: -3,
    );
    final back = ImportPlan.fromJson(plan.toJson());
    expect(back.makeOriginal, isTrue);
    expect(back.makeInstrumental, isFalse);
    expect(back.pitchSemitones, -3);
  });

  test('필드가 없는 JSON은 기존 동작으로 읽힌다', () {
    final plan = ImportPlan.fromJson(const {});
    expect(plan.makeOriginal, isFalse);
    expect(plan.makeInstrumental, isTrue);
    expect(plan.pitchSemitones, isNull);
  });

  // v2.13.0 남자키 프리셋 — MR 슬롯 자체가 키조절본.
  group('instrumentalSemitones (남자키)', () {
    test('maleKey 기본은 원곡 / MR−5 / 키조절−7', () {
      const plan = ImportPlan.maleKey();
      expect(plan.makeOriginal, isTrue);
      expect(plan.makeInstrumental, isTrue);
      expect(plan.instrumentalSemitones, -5);
      expect(plan.pitchSemitones, -7);
      expect(plan.wantsPitchedInstrumental, isTrue);
    });

    test('MR 슬롯의 구운 키와 라벨이 계획에 반영된다', () {
      final result = resolveImportPlan(
        plan: const ImportPlan.maleKey(),
        instrumentalLabel: 'MR 5키 낮춤',
        pitchLabel: '키조절 7키 낮춤',
      );
      final mr = result.forVariant(TrackVariant.mr)!;
      expect(mr.slot, 2);
      expect(mr.bakedSemitones, -5);
      expect(mr.label, 'MR 5키 낮춤');
      final pitch = result.forVariant(TrackVariant.pitch)!;
      expect(pitch.bakedSemitones, -7);
      expect(pitch.label, '키조절 7키 낮춤');
    });

    test('키 0이면 MR 라벨은 평소 그대로', () {
      final result = resolveImportPlan(
        plan: const ImportPlan.full(),
        instrumentalLabel: '이 라벨은 무시돼야 한다',
      );
      expect(result.forVariant(TrackVariant.mr)!.label, 'MR');
      expect(result.forVariant(TrackVariant.mr)!.bakedSemitones, 0);
    });

    test('JSON 왕복에 instrumentalSemitones가 실린다', () {
      const plan = ImportPlan.maleKey(mrSemitones: -4, pitchSemitones: -6);
      final back = ImportPlan.fromJson(plan.toJson());
      expect(back.instrumentalSemitones, -4);
      expect(back.pitchSemitones, -6);
    });

    test('v2.12 이전 JSON(필드 없음)은 0으로 읽힌다', () {
      final plan = ImportPlan.fromJson(const {'makeInstrumental': true});
      expect(plan.instrumentalSemitones, 0);
      expect(plan.wantsPitchedInstrumental, isFalse);
    });
  });
}
