// file: test/constants/app_shortcuts_test.dart
//
// 단축키 정본 검증 — clipId 유일성, 낭독 텍스트 형식.
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/constants/app_shortcuts.dart';

void main() {
  test('항목이 있고 clipId는 전체에서 유일하다', () {
    final all = [...AppShortcuts.entries, ...AppShortcuts.trainingEntries];
    expect(AppShortcuts.entries.length, greaterThanOrEqualTo(24));
    expect(AppShortcuts.trainingEntries.length, 2);
    final ids = <String>{};
    for (final entry in all) {
      expect(ids.add(entry.clipId), isTrue, reason: '중복 clipId: ${entry.clipId}');
      expect(entry.keys.trim(), isNotEmpty);
      expect(entry.description.trim(), isNotEmpty);
      expect(entry.spokenKeys.trim(), isNotEmpty);
      expect(entry.spokenDescription.trim(), isNotEmpty);
    }
  });

  test('낭독 전문은 키 이름과 설명을 잇는다', () {
    final entry = AppShortcuts.entries.first;
    expect(entry.spokenText, '${entry.spokenKeys}. ${entry.spokenDescription}');
  });

  test('v4.0.0 신규 키가 표에 있다', () {
    final keys = AppShortcuts.entries.map((e) => e.keys).toList();
    expect(keys, contains('+ / -'));
    expect(keys, contains('PgUp / PgDn'));
  });
}
