// file: lib/utils/file_name_sanitizer.dart
//
// 파일명에 쓸 수 없는 문자를 정리한다. (순수 함수 — 테스트 대상)
// Windows 금지문자를 공백으로 바꾸고, 끝의 점·공백을 제거한다.

String sanitizeFileName(String input, {String fallback = 'file'}) {
  final sanitized = input
      .replaceAll(RegExp(r'[<>:"/\\|?*]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  return sanitized.isEmpty ? fallback : sanitized;
}
