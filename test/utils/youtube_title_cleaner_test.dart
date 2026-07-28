import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/utils/youtube_title_cleaner.dart';

// 유튜브 제목 정제 — MR/노래방/키 표기 제거 + "가수 - 제목" 분리.
void main() {
  group('노이즈 괄호 제거', () {
    test('[MR]과 키 표기를 지우고 가수-제목을 분리한다', () {
      final r = cleanYoutubeSongName('아이유 - 밤편지 [MR] (-2키)');
      expect(r.title, '밤편지');
      expect(r.artist, '아이유');
    });

    test('(Official Audio)를 지운다', () {
      final r = cleanYoutubeSongName('IU - Through the Night (Official Audio)');
      expect(r.title, 'Through the Night');
      expect(r.artist, 'IU');
    });

    test('(Inst.)와 노래방 표기를 지운다', () {
      final r = cleanYoutubeSongName('[TJ 노래방] 벚꽃 엔딩 (Inst.)');
      expect(r.title, '벚꽃 엔딩');
      expect(r.artist, isNull);
    });

    test('복합 괄호 내용(노래방 MR)도 노이즈로 본다', () {
      final r = cleanYoutubeSongName('사건의 지평선 (노래방 MR)');
      expect(r.title, '사건의 지평선');
    });

    test('(feat. …)는 보존한다', () {
      final r = cleanYoutubeSongName('가수 - 제목 (feat. 다른가수) [MR]');
      expect(r.title, '제목 (feat. 다른가수)');
      expect(r.artist, '가수');
    });

    test('【】 괄호도 처리한다', () {
      final r = cleanYoutubeSongName('【노래방】 좋은 날');
      expect(r.title, '좋은 날');
    });
  });

  group('괄호 밖 노이즈 토큰', () {
    test('끝에 붙은 MR과 키 표기를 지운다', () {
      final r = cleanYoutubeSongName('밤편지 MR -2키');
      expect(r.title, '밤편지');
    });

    test('여자키 표기를 지운다', () {
      final r = cleanYoutubeSongName('사랑했나봐 노래방 여자키');
      expect(r.title, '사랑했나봐');
    });

    test('단어 일부는 건드리지 않는다 (Semi-Final)', () {
      final r = cleanYoutubeSongName('Semi-Final');
      expect(r.title, 'Semi-Final');
    });
  });

  group('가수-제목 분리', () {
    test('구분자가 없으면 제목만 남긴다', () {
      final r = cleanYoutubeSongName('밤편지 [MR]');
      expect(r.title, '밤편지');
      expect(r.artist, isNull);
    });

    test('업로더와 비슷한 조각을 가수로 고른다 (제목 - 가수 순서)', () {
      final r = cleanYoutubeSongName('밤편지 - 아이유', uploader: '아이유 Official');
      expect(r.title, '밤편지');
      expect(r.artist, '아이유');
    });

    test('구분자 3조각이면 분리하지 않는다', () {
      final r = cleanYoutubeSongName('A - B - C');
      expect(r.title, 'A - B - C');
      expect(r.artist, isNull);
    });

    test('| 구분자도 지원한다', () {
      final r = cleanYoutubeSongName('아이유 | 밤편지');
      expect(r.title, '밤편지');
      expect(r.artist, '아이유');
    });
  });

  group('방어', () {
    test('노이즈만 있는 제목은 원제를 돌려준다', () {
      final r = cleanYoutubeSongName('[MR] (Inst.)');
      expect(r.title, '[MR] (Inst.)');
    });

    test('빈 입력', () {
      final r = cleanYoutubeSongName('   ');
      expect(r.title, '');
      expect(r.artist, isNull);
    });

    test('구분자 찌꺼기를 정리한다', () {
      final r = cleanYoutubeSongName('밤편지 - [MR]');
      expect(r.title, '밤편지');
    });
  });
}
