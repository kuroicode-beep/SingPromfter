// v2 스키마 — 반주 조각·믹스 설정·분리 보컬 필드의 하위호환을 고정한다.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/recording_take.dart';

void main() {
  group('RecordingTake v2 스키마', () {
    test('v1 JSON(새 필드 없음)은 기본값으로 읽힌다', () {
      final t = RecordingTake.fromJson({
        'id': 'old',
        'songId': 's1',
        'songTitle': '봄날',
        'fileName': 'old.wav',
        'recordedAt': '2026-07-01T10:00:00',
        'durationMs': 60000,
      });
      expect(t.sourceAudioPath, isNull);
      expect(t.tempoScale, 1.0);
      expect(t.accompanimentFileName, isNull);
      expect(t.hasAccompaniment, isFalse);
      expect(t.mixBalance, 0.5);
      expect(t.reverbPreset, ReverbPreset.none);
      expect(t.noiseReduction, isFalse);
      expect(t.separatedFileName, isNull);
      expect(t.hasSeparatedVocal, isFalse);
    });

    test('v2 필드가 왕복 후 보존된다', () {
      final original = RecordingTake(
        id: 'x',
        songId: 's1',
        songTitle: '거리에서',
        fileName: 'x.wav',
        recordedAt: DateTime(2026, 8, 8, 12),
        durationMs: 90000,
        sourceAudioPath: r'C:\data\cache\pitch\mr__p-2.m4a',
        tempoScale: 0.9,
        accompanimentFileName: 'x_acc.m4a',
        mixBalance: 0.7,
        reverbPreset: ReverbPreset.karaoke,
        noiseReduction: true,
        separatedFileName: 'x_sep.wav',
      );
      final restored = RecordingTake.fromJson(original.toJson());
      expect(restored.sourceAudioPath, original.sourceAudioPath);
      expect(restored.tempoScale, 0.9);
      expect(restored.accompanimentFileName, 'x_acc.m4a');
      expect(restored.hasAccompaniment, isTrue);
      expect(restored.mixBalance, 0.7);
      expect(restored.reverbPreset, ReverbPreset.karaoke);
      expect(restored.noiseReduction, isTrue);
      expect(restored.separatedFileName, 'x_sep.wav');
    });

    test('mixBalance는 0~1로 제한한다', () {
      expect(RecordingTake.fromJson({'mixBalance': 5}).mixBalance, 1.0);
      expect(RecordingTake.fromJson({'mixBalance': -1}).mixBalance, 0.0);
    });

    test('모르는 리버브 값은 none으로 읽는다', () {
      expect(
        RecordingTake.fromJson({'reverbPreset': 'cathedral'}).reverbPreset,
        ReverbPreset.none,
      );
    });
  });

  group('dualChannel — 2채널 녹음 표시 (v5.11.0)', () {
    test('기본은 false, 옛 기록도 false로 읽힌다', () {
      expect(RecordingTake.fromJson(const {}).dualChannel, isFalse);
    });

    test('JSON 왕복에 살아남는다', () {
      final take = RecordingTake(
        id: 't1',
        songId: 's1',
        songTitle: '곡',
        fileName: 't1.wav',
        recordedAt: DateTime(2026, 9, 21),
        durationMs: 1000,
        accompanimentFileName: 't1_acc.wav',
        dualChannel: true,
      );
      expect(RecordingTake.fromJson(take.toJson()).dualChannel, isTrue);
    });

    test('copyWith로 뒤집을 수 있다', () {
      final take = RecordingTake(
        id: 't1',
        songId: 's1',
        songTitle: '곡',
        fileName: 't1.wav',
        recordedAt: DateTime(2026, 9, 21),
        durationMs: 1000,
        dualChannel: true,
      );
      expect(take.copyWith(dualChannel: false).dualChannel, isFalse);
      // 다른 필드만 바꿀 때는 유지된다.
      expect(take.copyWith(rating: 5).dualChannel, isTrue);
    });
  });

  group('songPositionMs — 조각 이어붙이기 좌표 (v5.12.0)', () {
    RecordingTake make({int? pos}) => RecordingTake(
      id: 't1',
      songId: 's1',
      songTitle: '곡',
      fileName: 't1.wav',
      recordedAt: DateTime(2026, 9, 21),
      durationMs: 5000,
      songPositionMs: pos,
    );

    test('옛 기록에는 없어서 null — 조각 대상이 아니다', () {
      final old = RecordingTake.fromJson(const {});
      expect(old.songPositionMs, isNull);
      expect(old.hasSongPosition, isFalse);
    });

    test('JSON 왕복에 살아남는다', () {
      final t = make(pos: 126161);
      expect(RecordingTake.fromJson(t.toJson()).songPositionMs, 126161);
      expect(t.hasSongPosition, isTrue);
    });

    test('0도 유효한 좌표다 (곡 처음부터)', () {
      final t = make(pos: 0);
      expect(RecordingTake.fromJson(t.toJson()).songPositionMs, 0);
      expect(t.hasSongPosition, isTrue);
    });

    test('alignOffsetMs와 별개로 남는다', () {
      // 2채널은 alignOffsetMs가 0이어도 곡 위치는 지켜져야 한다.
      final t = make(pos: 120380).copyWith(alignOffsetMs: 0);
      expect(t.alignOffsetMs, 0);
      expect(t.songPositionMs, 120380);
    });
  });

  group('leadInMs — 고정 조각의 리드인 (v5.16.0)', () {
    RecordingTake make({int? leadIn}) => RecordingTake(
      id: 't1',
      songId: 's1',
      songTitle: '곡',
      fileName: 't1.wav',
      recordedAt: DateTime(2026, 9, 22),
      durationMs: 2700,
      songPositionMs: 83000,
      leadInMs: leadIn,
    );

    test('옛 기록에는 키가 없어서 null — 그래도 읽힌다(additive)', () {
      final old = RecordingTake.fromJson({
        'id': 'old',
        'songId': 's1',
        'songTitle': '봄날',
        'fileName': 'old.wav',
        'recordedAt': '2026-09-21T10:00:00',
        'durationMs': 1800,
        'songPositionMs': 126161,
      });
      expect(old.leadInMs, isNull);
      // 다른 필드는 그대로 읽혀야 한다 — 새 키가 옛 파일을 깨면 목록이 통째로 빈다.
      expect(old.songPositionMs, 126161);
      expect(old.durationMs, 1800);
    });

    test('JSON 왕복에 살아남는다', () {
      final t = make(leadIn: 300);
      expect(t.toJson()['leadInMs'], 300);
      expect(RecordingTake.fromJson(t.toJson()).leadInMs, 300);
    });

    test('0도 유효하다 — 곡 맨 앞에서는 리드인을 못 담는다', () {
      final t = make(leadIn: 0);
      expect(RecordingTake.fromJson(t.toJson()).leadInMs, 0);
    });

    test('null은 null로 왕복한다(R 녹음)', () {
      final t = make();
      expect(t.toJson().containsKey('leadInMs'), isTrue);
      expect(RecordingTake.fromJson(t.toJson()).leadInMs, isNull);
    });

    test('소수로 저장돼 있어도 정수로 읽는다', () {
      expect(RecordingTake.fromJson({'leadInMs': 285.0}).leadInMs, 285);
    });

    test('copyWith — 주면 바뀌고, 다른 필드만 바꿀 때는 유지된다', () {
      final t = make(leadIn: 300);
      expect(t.copyWith(leadInMs: 120).leadInMs, 120);
      expect(t.copyWith(comment: '복구됨').leadInMs, 300);
      expect(t.copyWith(accompanimentFileName: 't1_acc.m4a').leadInMs, 300);
    });
  });

  group('latencyAppliedMs — 테이크에 구워진 녹음 지연 보정 (v5.17.0)', () {
    RecordingTake make({int applied = 0}) => RecordingTake(
      id: 'r1',
      songId: 's1',
      songTitle: '곡',
      fileName: 'r1.wav',
      recordedAt: DateTime(2026, 9, 22),
      durationMs: 1800,
      alignOffsetMs: 59565,
      songPositionMs: 59565,
      leadInMs: 300,
      latencyAppliedMs: applied,
    );

    test('옛 기록에는 키가 없어서 0(보정 없이 받은 테이크) — 그래도 읽힌다(additive)', () {
      final old = RecordingTake.fromJson({
        'id': 'old',
        'songId': 's1',
        'songTitle': '봄날',
        'fileName': 'old.wav',
        'recordedAt': '2026-09-21T10:00:00',
        'durationMs': 1800,
        'alignOffsetMs': 126161,
        'songPositionMs': 126161,
        'leadInMs': 300,
      });
      expect(old.latencyAppliedMs, 0);
      // 다른 필드는 그대로 읽혀야 한다 — 옛 테이크의 좌표를 소급해 고치지 않는다.
      expect(old.songPositionMs, 126161);
      expect(old.alignOffsetMs, 126161);
      expect(old.leadInMs, 300);
    });

    test('JSON 왕복에 살아남는다(음수 보정 포함)', () {
      for (final applied in [120, -40, 0]) {
        final back = RecordingTake.fromJson(
          jsonDecode(jsonEncode(make(applied: applied).toJson()))
              as Map<String, dynamic>,
        );
        expect(back.latencyAppliedMs, applied);
        expect(back.songPositionMs, 59565);
      }
    });

    test('소수·문자로 저장돼 있어도 목록 읽기를 깨지 않는다', () {
      expect(
        RecordingTake.fromJson({'latencyAppliedMs': 120.0}).latencyAppliedMs,
        120,
      );
      expect(
        () => RecordingTake.fromJson({'latencyAppliedMs': null}),
        returnsNormally,
      );
    });

    test('보정 전 좌표 = 저장된 좌표 + 적용값 — 설정을 나중에 바꿔도 해석할 수 있다', () {
      final t = make(applied: 120);
      expect(t.songPositionMs! + t.latencyAppliedMs, 59685);
    });

    test('copyWith — 주면 바뀌고, 다른 필드만 바꿀 때는 유지된다', () {
      final t = make(applied: 120);
      expect(t.copyWith(latencyAppliedMs: 0).latencyAppliedMs, 0);
      expect(t.copyWith(comment: '메모').latencyAppliedMs, 120);
      expect(t.copyWith(mixedFileName: 'r1_mix.m4a').latencyAppliedMs, 120);
    });
  });

  group('stitched — 이어붙인 결과물 표식 (v5.17.0)', () {
    RecordingTake make({bool stitched = false, int? songPositionMs = 0}) =>
        RecordingTake(
          id: 'r1',
          songId: 's1',
          songTitle: '곡',
          fileName: 'r1.wav',
          recordedAt: DateTime(2026, 9, 22),
          durationMs: 40000,
          songPositionMs: songPositionMs,
          stitched: stitched,
        );

    test('옛 기록에는 키가 없어서 false — 그래도 읽힌다(additive)', () {
      final old = RecordingTake.fromJson({
        'id': 'old',
        'songId': 's1',
        'songTitle': '봄날',
        'fileName': 'old.wav',
        'recordedAt': '2026-09-21T10:00:00',
        'durationMs': 1800,
        'songPositionMs': 126161,
        'leadInMs': 300,
      });
      expect(old.stitched, isFalse);
      expect(old.isStitchable, isTrue);
      // 다른 필드는 그대로 읽혀야 한다.
      expect(old.songPositionMs, 126161);
      expect(old.leadInMs, 300);
    });

    test('JSON 왕복에 살아남는다', () {
      final t = make(stitched: true);
      expect(t.toJson()['stitched'], isTrue);
      expect(RecordingTake.fromJson(t.toJson()).stitched, isTrue);
      expect(RecordingTake.fromJson(make().toJson()).stitched, isFalse);
      // 파일에서도 그대로다(목록은 jsonEncode를 거친다).
      final viaText =
          jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>;
      expect(RecordingTake.fromJson(viaText).stitched, isTrue);
    });

    test('bool이 아닌 값이 들어 있어도 목록 읽기를 깨지 않는다', () {
      expect(RecordingTake.fromJson({'stitched': null}).stitched, isFalse);
    });

    test('🔴 결과물은 곡 좌표가 있어도 이어붙이기의 재료가 아니다', () {
      // 결과물은 곡 좌표 0이다 — 좌표만 보면 「0:00에서 받은 조각」과 구분이 안 된다.
      expect(make(stitched: true).hasSongPosition, isTrue);
      expect(make(stitched: true).isStitchable, isFalse);
      expect(make().isStitchable, isTrue);
      // 좌표가 없는 옛 테이크는 원래 재료가 아니다.
      expect(make(songPositionMs: null).isStitchable, isFalse);
    });

    test('결과물은 「0:00 조각」이라고 말하지 않는다', () {
      expect(make(stitched: true).displayPositionMs, isNull);
      expect(make().displayPositionMs, 0);
    });

    test('copyWith — 주면 바뀌고, 다른 필드만 바꿀 때는 유지된다', () {
      final t = make(stitched: true);
      expect(t.copyWith(mixedFileName: 'r1_mix.m4a').stitched, isTrue);
      expect(t.copyWith(rating: 5).stitched, isTrue);
      expect(make().copyWith(stitched: true).stitched, isTrue);
    });
  });

  group('displayPositionMs — 사용자에게 말하는 조각 위치 (v5.16.0)', () {
    RecordingTake make({int? songPositionMs, int? leadInMs}) => RecordingTake(
      id: 't1',
      songId: 's1',
      songTitle: '곡',
      fileName: 't1.wav',
      recordedAt: DateTime(2026, 9, 22),
      durationMs: 2000,
      songPositionMs: songPositionMs,
      leadInMs: leadInMs,
    );

    test('🔴 고정 조각은 리드인을 더해 「스페이스를 누른 자리」로 말한다', () {
      // P0 = 1:23.10 → 파일 좌표는 83100 − 15 − 300 = 82785(1:22). 저장 토스트는
      // 1:23이라고 했는데 목록·취소 토스트가 1:22라고 하면 다른 조각으로 읽힌다.
      final take = make(songPositionMs: 82785, leadInMs: 300);
      expect(take.displayPositionMs, 83085);
      // 저장 좌표(이어붙이기·반주 자르기)는 그대로다.
      expect(take.songPositionMs, 82785);
    });

    test('리드인이 없는 테이크(R 녹음·옛 기록)는 값이 그대로다', () {
      expect(make(songPositionMs: 126161).displayPositionMs, 126161);
      expect(make(songPositionMs: 0, leadInMs: 0).displayPositionMs, 0);
    });

    test('좌표가 없으면 null — 「0:00 조각」을 지어내지 않는다', () {
      expect(make().displayPositionMs, isNull);
      expect(make(leadInMs: 300).displayPositionMs, isNull);
    });
  });

  group('peakDbfs — 저장된 소리의 최대 레벨 (v5.16.0)', () {
    RecordingTake make({double? peak}) => RecordingTake(
      id: 't1',
      songId: 's1',
      songTitle: '곡',
      fileName: 't1.wav',
      recordedAt: DateTime(2026, 9, 22),
      durationMs: 2700,
      songPositionMs: 83000,
      peakDbfs: peak,
    );

    test('옛 기록에는 키가 없어서 null — 그래도 읽힌다(additive)', () {
      final old = RecordingTake.fromJson({
        'id': 'old',
        'songId': 's1',
        'fileName': 'old.wav',
        'recordedAt': '2026-09-21T10:00:00',
        'durationMs': 1800,
        'songPositionMs': 126161,
      });
      expect(old.peakDbfs, isNull);
      expect(old.songPositionMs, 126161);
    });

    test('JSON 문자열 왕복에 살아남는다', () {
      final t = make(peak: -21.5);
      final back = RecordingTake.fromJson(
        jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>,
      );
      expect(back.peakDbfs, -21.5);
    });

    test('정수로 저장돼 있어도 읽는다(-100 = 완전 무음)', () {
      expect(RecordingTake.fromJson({'peakDbfs': -100}).peakDbfs, -100.0);
    });

    test('NaN·무한대여도 jsonEncode가 죽지 않는다 — 목록 저장이 통째로 막히면 안 된다', () {
      expect(() => jsonEncode(make(peak: double.nan).toJson()), returnsNormally);
      expect(make(peak: double.nan).toJson()['peakDbfs'], isNull);
      // 완전 무음의 -inf는 캡처 쪽 표기(-100)로 남겨 무음 판정이 유지되게 한다.
      expect(make(peak: double.negativeInfinity).toJson()['peakDbfs'], -100);
      expect(
        () => jsonEncode(make(peak: double.negativeInfinity).toJson()),
        returnsNormally,
      );
      expect(make(peak: double.infinity).toJson()['peakDbfs'], 0);
    });

    test('copyWith — 주면 바뀌고, 다른 필드만 바꿀 때는 유지된다', () {
      final t = make(peak: -18);
      expect(t.copyWith(peakDbfs: -30).peakDbfs, -30);
      expect(t.copyWith(accompanimentFileName: 't1_acc.m4a').peakDbfs, -18);
      expect(t.copyWith(comment: '메모').peakDbfs, -18);
    });
  });
}
