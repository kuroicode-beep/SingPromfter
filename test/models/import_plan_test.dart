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
}
