// file: lib/utils/korean_text.dart
//
// 한글 초성 추출·검색 매칭 유틸. 곡 검색과 녹음 검색이 공유한다.

/// 한글 음절 → 초성 변환 및 초성 검색 매칭.
class KoreanText {
  KoreanText._();

  static const List<String> _initials = [
    'ㄱ',
    'ㄲ',
    'ㄴ',
    'ㄷ',
    'ㄸ',
    'ㄹ',
    'ㅁ',
    'ㅂ',
    'ㅃ',
    'ㅅ',
    'ㅆ',
    'ㅇ',
    'ㅈ',
    'ㅉ',
    'ㅊ',
    'ㅋ',
    'ㅌ',
    'ㅍ',
    'ㅎ',
  ];

  static const int _syllableStart = 0xAC00;
  static const int _syllableEnd = 0xD7A3;
  static const int _syllableBlock = 588; // 초성 1개가 차지하는 음절 수

  /// 한글 음절은 초성으로, 나머지는 소문자로 바꾼 문자열을 만든다.
  /// 예: '봄날' → 'ㅂㄴ'
  static String initials(String value) {
    final buffer = StringBuffer();
    for (final codeUnit in value.runes) {
      if (codeUnit >= _syllableStart && codeUnit <= _syllableEnd) {
        buffer.write(_initials[(codeUnit - _syllableStart) ~/ _syllableBlock]);
      } else {
        buffer.write(String.fromCharCode(codeUnit).toLowerCase());
      }
    }
    return buffer.toString();
  }

  /// 검색어가 대상 문자열에 매칭되는지 확인한다.
  ///
  /// 1) 일반 부분 문자열 매칭 (대소문자 무시)
  /// 2) 초성 매칭 — 질의어도 초성으로 정규화하므로
  ///    'ㅂㄴ'뿐 아니라 '봄ㄴ'·'봄날'도 '봄날'에 매칭된다.
  static bool matches(String value, String query) {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return true;

    final normalizedValue = value.toLowerCase();
    final normalizedQuery = trimmedQuery.toLowerCase();
    if (normalizedValue.contains(normalizedQuery)) return true;

    return initials(value).contains(initials(trimmedQuery));
  }
}
