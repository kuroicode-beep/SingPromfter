// file: test/utils/youtube_subtitle_test.dart
//
// 유튜브 json3 자막 파서 — 텍스트 조립·장식 줄 제외·중복 정리.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/utils/youtube_subtitle.dart';

String json3(List<Map<String, dynamic>> events) =>
    jsonEncode({'events': events});

void main() {
  test('segs를 합쳐 한 줄로, 시각은 ms→초', () {
    final segs = segmentsFromJson3(
      json3([
        {
          'tStartMs': 30500,
          'dDurationMs': 4000,
          'segs': [
            {'utf8': '너를 사랑'},
            {'utf8': '하고도'},
          ],
        },
      ]),
    );
    expect(segs.single.text, '너를 사랑하고도');
    expect(segs.single.startSeconds, 30.5);
    expect(segs.single.endSeconds, 34.5);
  });

  test('빈 줄·장식(♪) 줄은 버린다', () {
    final segs = segmentsFromJson3(
      json3([
        {
          'tStartMs': 0,
          'segs': [
            {'utf8': '♪ ♪'},
          ],
        },
        {
          'tStartMs': 1000,
          'segs': [
            {'utf8': '\n'},
          ],
        },
        {
          'tStartMs': 2000,
          'segs': [
            {'utf8': '진짜 가사'},
          ],
        },
      ]),
    );
    expect(segs.map((s) => s.text), ['진짜 가사']);
  });

  test('같은 시각의 같은 텍스트(스타일 이벤트)는 하나로', () {
    final segs = segmentsFromJson3(
      json3([
        {
          'tStartMs': 5000,
          'segs': [
            {'utf8': '후렴'},
          ],
        },
        {
          'tStartMs': 5010,
          'segs': [
            {'utf8': '후렴'},
          ],
        },
      ]),
    );
    expect(segs, hasLength(1));
  });

  test('형식이 아니면 빈 목록', () {
    expect(segmentsFromJson3('not json'), isEmpty);
    expect(segmentsFromJson3('{"foo":1}'), isEmpty);
  });
}
