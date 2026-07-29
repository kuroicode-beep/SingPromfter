import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/vocal_segments.dart';
import 'package:singpromfter_app/services/lyrics_progress_service.dart';

// 노래 구간 검출과 구간 기반 줄 배분.
//
// 배경: 줄을 곡 전체에 고르게 뿌리면 전주 동안 가사가 흘러가고 간주에도
// 진행된다(실측: 「선물」은 224초 중 노래가 55%뿐, 전주만 13.7초).
// 노래 구간 안에서만 시간이 흐르는 축을 검증한다.
void main() {
  const fps = 25;

  /// [spans](ms) 구간에만 보컬(10dB)이 있는 존재도 신호.
  List<double> presenceWith(List<(int, int)> spans, {int lengthMs = 200000}) {
    final frames = List<double>.filled(lengthMs * fps ~/ 1000, 0);
    for (final (start, end) in spans) {
      for (var i = start * fps ~/ 1000; i < end * fps ~/ 1000; i++) {
        if (i < frames.length) frames[i] = 10;
      }
    }
    return frames;
  }

  group('detectVocalSegments', () {
    test('전주·간주를 사이에 둔 구간들을 찾는다', () {
      final segs = detectVocalSegments(
        presenceWith([(13000, 25000), (40000, 60000), (95000, 105000)]),
      );
      expect(segs, hasLength(3));
      expect(segs.first.startMs, closeTo(13000, 100));
      expect(segs.first.endMs, closeTo(25000, 100));
      expect(segs[1].startMs, closeTo(40000, 100));
    });

    test('1.5초 미만의 쉼은 구간을 끊지 않는다', () {
      final segs = detectVocalSegments(
        presenceWith([(10000, 20000), (21000, 30000)]),
      );
      expect(segs, hasLength(1));
      expect(segs.single.startMs, closeTo(10000, 100));
      expect(segs.single.endMs, closeTo(30000, 100));
    });

    test('1초 미만 조각은 버린다', () {
      final segs = detectVocalSegments(
        presenceWith([(10000, 10500), (20000, 30000)]),
      );
      expect(segs, hasLength(1));
      expect(segs.single.startMs, closeTo(20000, 100));
    });

    test('빈 신호는 빈 목록', () {
      expect(detectVocalSegments(const []), isEmpty);
    });
  });

  group('VocalSegments 직렬화', () {
    test('왕복이 값을 보존한다', () {
      const original = VocalSegments([
        VocalSegment(startMs: 13000, endMs: 25000),
        VocalSegment(startMs: 40000, endMs: 60000),
      ]);
      final decoded = VocalSegments.decode(original.encode());
      expect(decoded, isNotNull);
      expect(decoded!.segments, hasLength(2));
      expect(decoded.segments.first.startMs, 13000);
      expect(decoded.totalSungMs, original.totalSungMs);
    });

    test('버전이 다르면 null — 정확 일치 가드', () {
      // "상위 버전만 거부"는 낡은 캐시를 영영 서빙한다(레벨 캐시에서 겪은 버그).
      final tampered = encodedWithVersion(0);
      expect(VocalSegments.decode(tampered), isNull);
      expect(VocalSegments.decode(encodedWithVersion(99)), isNull);
    });

    test('깨진 입력은 null', () {
      expect(VocalSegments.decode('not json'), isNull);
      expect(VocalSegments.decode('{"version":1}'), isNull);
    });
  });

  group('segmentLineProgress — 노래 구간에만 줄을 배분', () {
    // 노래 20초×2구간(합 40초), 전주 10초 + 간주 20초.
    const segments = VocalSegments([
      VocalSegment(startMs: 10000, endMs: 30000),
      VocalSegment(startMs: 50000, endMs: 70000),
    ]);

    test('전주 동안은 첫 줄에서 대기한다', () {
      final p = LyricsProgressService.segmentLineProgress(
        position: const Duration(seconds: 5),
        segments: segments,
        lineCount: 10,
      );
      expect(p.index, 0);
      expect(p.fraction, 0);
    });

    test('첫 구간의 절반이면 전체 줄의 1/4 지점', () {
      // 노래 축 20초/40초 = 0.5? 아니다 — 첫 구간 절반은 노래 축 10초/40초 = 1/4.
      final p = LyricsProgressService.segmentLineProgress(
        position: const Duration(seconds: 20),
        segments: segments,
        lineCount: 8,
      );
      expect(p.index, 2); // 8줄 × 1/4
    });

    test('간주에서는 직전 줄에 멈춘다', () {
      final atGapStart = LyricsProgressService.segmentLineProgress(
        position: const Duration(seconds: 30),
        segments: segments,
        lineCount: 8,
      );
      final midGap = LyricsProgressService.segmentLineProgress(
        position: const Duration(seconds: 45),
        segments: segments,
        lineCount: 8,
      );
      expect(midGap.index, atGapStart.index);
      expect(midGap.fraction, atGapStart.fraction);
    });

    test('마지막 구간 끝에서 마지막 줄·진행 1.0', () {
      final p = LyricsProgressService.segmentLineProgress(
        position: const Duration(seconds: 70),
        segments: segments,
        lineCount: 8,
      );
      expect(p.index, 7);
      expect(p.fraction, 1);
    });

    test('구간이 없으면 0에서 멈춘다 (호출부가 균등 배분으로 폴백)', () {
      final p = LyricsProgressService.segmentLineProgress(
        position: const Duration(seconds: 30),
        segments: const VocalSegments([]),
        lineCount: 8,
      );
      expect(p.index, 0);
    });
  });

  group('positionForLineIndexWithSegments — 역함수', () {
    const segments = VocalSegments([
      VocalSegment(startMs: 10000, endMs: 30000),
      VocalSegment(startMs: 50000, endMs: 70000),
    ]);

    test('0번 줄은 전주를 건너뛰고 첫 노래 구간으로 간다', () {
      final pos = LyricsProgressService.positionForLineIndexWithSegments(
        index: 0,
        segments: segments,
        lineCount: 8,
      );
      expect(pos, const Duration(milliseconds: 10000));
    });

    test('후반 줄은 둘째 구간 안의 위치로 간다', () {
      final pos = LyricsProgressService.positionForLineIndexWithSegments(
        index: 6, // 노래 축 30초/40초 지점 → 둘째 구간 10초째 = 60초
        segments: segments,
        lineCount: 8,
      );
      expect(pos!.inMilliseconds, closeTo(60000, 200));
    });

    test('왕복: 역함수가 준 위치는 같은 줄로 돌아온다', () {
      for (final index in [0, 1, 3, 5, 7]) {
        final pos = LyricsProgressService.positionForLineIndexWithSegments(
          index: index,
          segments: segments,
          lineCount: 8,
        );
        final back = LyricsProgressService.segmentLineProgress(
          position: pos!,
          segments: segments,
          lineCount: 8,
        );
        expect(back.index, index, reason: '줄 $index 왕복');
      }
    });
  });
}

/// 버전 필드만 바꾼 직렬화 문자열.
String encodedWithVersion(int version) =>
    '{"version":$version,"segments":[{"startMs":0,"endMs":1000}]}';
