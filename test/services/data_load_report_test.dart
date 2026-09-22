// file: test/services/data_load_report_test.dart
//
// 부팅 때 데이터 파일을 못 읽었을 때 큰 경고에 실을 글(순수 함수).
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/services/atomic_json_file.dart';
import 'package:singpromfter_app/services/data_load_report.dart';

void main() {
  test('전부 정상이면 알릴 것이 없다(null)', () {
    expect(
      buildDataLoadAlert([
        (label: '곡 목록', state: AtomicLoadState.ok),
        (label: '연습 기록', state: AtomicLoadState.ok),
      ]),
      isNull,
    );
    expect(buildDataLoadAlert(const []), isNull);
  });

  test('못 읽은 파일이 있으면 그 이름과 「지우지 않았다」를 알린다', () {
    final alert = buildDataLoadAlert([
      (label: '녹음 목록', state: AtomicLoadState.ok),
      (label: '곡 목록', state: AtomicLoadState.unreadable),
    ])!;
    expect(alert.title, '데이터 파일을 읽지 못했습니다');
    expect(alert.detail, contains('곡 목록 — 지금 읽을 수 없어'));
    expect(alert.detail, contains('파일은 지우지 않았습니다'));
    // 「지금 못 여는」 파일에는 .corrupt 사본이 생기지 않는다 — 조건을 달아 말한다.
    expect(alert.detail, contains('깨진 파일이면'));
    // 상위 schemaVersion(구버전 exe로 되돌아간 경우)도 같은 「못 읽음」으로 온다.
    expect(alert.detail, contains('앱을 업데이트해 주세요'));
    expect(alert.detail, isNot(contains('녹음 목록')));
    expect(alert.detail, isNot(contains('되살린 쪽은')));
  });

  test('백업에서 되살렸으면 최근 변경 한 번이 빠졌을 수 있음을 알린다', () {
    final alert = buildDataLoadAlert([
      (label: '생성곡 목록', state: AtomicLoadState.recoveredFromBackup),
    ])!;
    expect(alert.title, '데이터를 백업에서 되살렸습니다');
    expect(alert.detail, contains('생성곡 목록 — 직전 백업(.bak)에서 되살렸습니다'));
    expect(alert.detail, contains('가장 최근 변경 한 번이 빠졌을 수 있습니다'));
    expect(alert.detail, isNot(contains('.corrupt')));
  });

  test('둘이 섞이면 한 장에 모으고, 제목은 더 무거운 쪽을 따른다', () {
    final alert = buildDataLoadAlert([
      (label: '녹음 목록', state: AtomicLoadState.recoveredFromBackup),
      (label: '곡 목록', state: AtomicLoadState.unreadable),
      (label: '일일 목표', state: AtomicLoadState.ok),
    ])!;
    expect(alert.title, '데이터 파일을 읽지 못했습니다');
    expect(alert.detail, contains('녹음 목록 — 직전 백업'));
    expect(alert.detail, contains('곡 목록 — 지금 읽을 수 없어'));
    expect(alert.detail, isNot(contains('일일 목표')));
    // 큰 경고는 스크롤이 없다 — 줄 수를 묶어 둔다.
    expect('\n'.allMatches(alert.detail).length, lessThanOrEqualTo(8));
  });
}
