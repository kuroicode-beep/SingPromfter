// v2 스키마 — 반주 조각·믹스 설정·분리 보컬 필드의 하위호환을 고정한다.
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
}
