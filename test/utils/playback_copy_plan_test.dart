// file: test/utils/playback_copy_plan_test.dart
//
// 위치 보정본의 이름·ffmpeg 인자·축출 계획·안내 문구(전부 순수 함수).
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/utils/playback_copy_plan.dart';

void main() {
  group('사본 이름 — 원본의 크기+수정시각 지문이 들어간다', () {
    test('<줄기>__play_<크기16진>_<수정시각16진>.wav', () {
      expect(
        playbackCopyFileName(
          '내 남자친구에게_mr1.mp3',
          sizeBytes: 7732365,
          modifiedMs: 1758500000000,
        ),
        '내 남자친구에게_mr1__play_75fc8d_1996ec49100.wav',
      );
    });

    test('🔴 같은 이름의 원본이라도 크기나 수정시각이 다르면 다른 사본 이름이다', () {
      String name({int size = 100, int mtime = 5000}) =>
          playbackCopyFileName('곡_mr1.mp3', sizeBytes: size, modifiedMs: mtime);
      expect(name(), name());
      expect(name(size: 101), isNot(name()));
      expect(name(mtime: 5001), isNot(name()));
    });

    test('머리(prefix)는 지문과 무관하다 — 파일명 기준 무효화가 옛 지문까지 쓸어 담는다', () {
      const source = '곡_mr1.mp3';
      final old = playbackCopyFileName(source, sizeBytes: 1, modifiedMs: 2);
      final fresh = playbackCopyFileName(source, sizeBytes: 3, modifiedMs: 4);
      expect(isPlaybackCopyOf(old, source), isTrue);
      expect(isPlaybackCopyOf(fresh, source), isTrue);
      expect(
        isPlaybackCopyOf('$fresh$kPlaybackCopyPartSuffix', source),
        isTrue,
      );
      // 다른 슬롯의 사본은 건드리지 않는다.
      expect(isPlaybackCopyOf(old, '곡_mr2.mp3'), isFalse);
      expect(playbackCopyPrefixOf(old), playbackCopyPrefix(source));
    });

    test('우리가 만든 파일이 아니면 머리를 못 뗀다', () {
      expect(playbackCopyPrefixOf('desktop.ini'), isNull);
      expect(playbackCopyPrefixOf('__play_x.wav'), isNull);
    });

    test('확장자가 없는 이름도 줄기로 쓴다', () {
      expect(playbackCopyStem('noext'), 'noext');
      expect(playbackCopyStem('a.b.mp3'), 'a.b');
    });

    test('🔴 긴 제목은 40자 + 해시로 줄인다 — 캐시 경로가 260자에 닿지 않게', () {
      final long = '${'가' * 120}_mr1.mp3';
      final stem = playbackCopyStem(long);
      expect(stem.runes.length, 40 + 1 + 8);
      expect(stem, startsWith('가' * 40));
      // 앞 40자가 같은 두 곡도 이름이 갈린다.
      final other = playbackCopyStem('${'가' * 120}_mr2.mp3');
      expect(other, isNot(stem));
      // 같은 입력이면 언제나 같은 이름(실행마다 바뀌면 캐시를 못 찾는다).
      expect(playbackCopyStem(long), stem);
    });

    test('이모지를 반쪽으로 자르지 않는다(코드포인트 단위)', () {
      final long = '${'🎤' * 60}_mr1.mp3';
      final stem = playbackCopyStem(long);
      expect(stem, startsWith('🎤' * 40));
      expect(stem.substring(0, 80), '🎤' * 40); // 코드유닛 80개 = 이모지 40개
    });
  });

  group('buildPlaybackCopyArgs', () {
    test('실측으로 검증한 인자 그대로 — 원본 샘플레이트·채널을 건드리지 않는다', () {
      final args = buildPlaybackCopyArgs(
        input: r'C:\data\mp3\곡_mr1.mp3',
        output: r'C:\cache\곡_mr1__play_1_2.wav.part',
      );
      expect(args, [
        '-hide_banner',
        '-nostdin',
        '-y',
        '-i',
        r'C:\data\mp3\곡_mr1.mp3',
        '-vn',
        '-map_metadata',
        '-1',
        '-c:a',
        'pcm_s16le',
        '-f',
        'wav',
        r'C:\cache\곡_mr1__play_1_2.wav.part',
      ]);
      // 리샘플·채널 변환·시작 자르기가 끼면 시간축이 원본과 달라진다.
      for (final forbidden in ['-ar', '-ac', '-ss', '-af', '-filter:a']) {
        expect(args, isNot(contains(forbidden)));
      }
    });

    test('🔴 출력이 .part라 형식을 -f wav로 못 박는다(확장자로는 못 고른다)', () {
      final args = buildPlaybackCopyArgs(input: 'a.mp3', output: 'b.wav.part');
      expect(args[args.indexOf('-f') + 1], 'wav');
      expect(args.last, endsWith(kPlaybackCopyPartSuffix));
    });
  });

  group('planPlaybackCopyEviction — 오래 안 쓴 것부터', () {
    const entries = <PlaybackCopyEntry>[
      (name: 'new.wav', bytes: 50, lastUsedMs: 300),
      (name: 'old.wav', bytes: 50, lastUsedMs: 100),
      (name: 'mid.wav', bytes: 50, lastUsedMs: 200),
    ];

    test('상한 안이면 아무것도 버리지 않는다', () {
      expect(planPlaybackCopyEviction(entries, maxBytes: 150), isEmpty);
    });

    test('넘는 만큼만, 오래된 순으로 버린다', () {
      expect(planPlaybackCopyEviction(entries, maxBytes: 120), ['old.wav']);
      expect(planPlaybackCopyEviction(entries, maxBytes: 60), [
        'old.wav',
        'mid.wav',
      ]);
    });

    test('🔴 keep(방금 구운 것·재생 중인 것)은 상한을 넘어도 버리지 않는다', () {
      expect(
        planPlaybackCopyEviction(entries, maxBytes: 0, keep: const {'old.wav'}),
        ['mid.wav', 'new.wav'],
      );
    });
  });

  group('안내 문구', () {
    test('보정본을 쓸 때만 「재생: 위치 보정본」이 붙는다', () {
      expect(playbackSourceNote(PlaybackSourceKind.seekCopy), '재생: 위치 보정본');
      expect(playbackSourceNote(PlaybackSourceKind.vbrOriginal), isNull);
      expect(playbackSourceNote(PlaybackSourceKind.plain), isNull);
    });

    test('VBR 안내는 기존 토스트 뒤에 붙는다 — 없으면 그대로', () {
      expect(withPlaybackCopyNotice('녹음을 시작했습니다.', null), '녹음을 시작했습니다.');
      expect(
        withPlaybackCopyNotice('녹음을 시작했습니다.', kVbrOriginalNotice),
        '녹음을 시작했습니다.\n$kVbrOriginalNotice',
      );
    });

    test('문구가 요구된 그대로다', () {
      expect(
        kVbrOriginalNotice,
        '이 반주는 이동 후 위치가 어긋날 수 있는 형식(VBR)입니다 — '
        '보정본을 준비하는 중이에요. 다음에 이 곡을 열면 적용돼요.',
      );
    });
  });

  group('VbrNoticeGate — 곡마다 한 번', () {
    test('VBR 원본일 때만, 같은 곡은 한 번만 알린다', () {
      final gate = VbrNoticeGate();
      expect(
        gate.take(songId: 'a', kind: PlaybackSourceKind.vbrOriginal),
        kVbrOriginalNotice,
      );
      expect(
        gate.take(songId: 'a', kind: PlaybackSourceKind.vbrOriginal),
        isNull,
      );
      // 다른 곡은 따로 센다.
      expect(
        gate.take(songId: 'b', kind: PlaybackSourceKind.vbrOriginal),
        kVbrOriginalNotice,
      );
    });

    test('🔴 보정본을 쓰고 있으면 아무것도 알리지 않고, 「알렸음」으로 치지도 않는다', () {
      final gate = VbrNoticeGate();
      expect(gate.take(songId: 'a', kind: PlaybackSourceKind.seekCopy), isNull);
      expect(gate.take(songId: 'a', kind: PlaybackSourceKind.plain), isNull);
      expect(
        gate.take(songId: null, kind: PlaybackSourceKind.vbrOriginal),
        isNull,
      );
      expect(
        gate.take(songId: 'a', kind: PlaybackSourceKind.vbrOriginal),
        kVbrOriginalNotice,
      );
    });
  });
}
