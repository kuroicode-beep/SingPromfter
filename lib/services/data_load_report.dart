// file: lib/services/data_load_report.dart
//
// 부팅 때 데이터 파일을 정본에서 못 읽었으면 큰 경고(CenterAlert)에 실을 글을 만든다.
//
// 못 읽은 목록은 빈 목록(또는 한 박자 낡은 백업)으로 뜬다. 말없이 넘기면 사용자는
// 「곡이 다 사라졌다」고만 본다 — 파일은 그대로 있고 저장이 그것을 지키고 있다는 것을
// 알려야 한다. 큰 경고는 한 번에 한 장뿐이라 여러 파일의 상태를 한 장에 모은다.
import 'atomic_json_file.dart';

/// 읽기 상태를 점검할 데이터 파일 하나. [label]은 화면에 보일 이름이다.
typedef DataLoadEntry = ({String label, AtomicLoadState state});

/// 큰 경고의 제목·본문을 만든다. 전부 정상이면 null. (순수 함수)
({String title, String detail})? buildDataLoadAlert(
  List<DataLoadEntry> entries,
) {
  final recovered = [
    for (final entry in entries)
      if (entry.state == AtomicLoadState.recoveredFromBackup) entry.label,
  ];
  final unreadable = [
    for (final entry in entries)
      if (entry.state == AtomicLoadState.unreadable) entry.label,
  ];
  if (recovered.isEmpty && unreadable.isEmpty) return null;

  final lines = <String>[
    for (final label in unreadable) '$label — 지금 읽을 수 없어 비운 채로 시작합니다',
    for (final label in recovered) '$label — 직전 백업(.bak)에서 되살렸습니다',
    '',
    // 「못 읽음」에는 깨진 파일과 **지금 못 여는** 파일(잠김·오프라인)이 다 들어 있다.
    // 뒤쪽은 .corrupt 사본이 생기지 않으니 「깨진 파일이면」이라고 조건을 단다.
    if (unreadable.isNotEmpty) ...[
      '· 파일은 지우지 않았습니다 — 다시 읽히면 합쳐서 저장합니다',
      '· 깨진 파일이면 저장할 때 .corrupt 사본을 옆에 남깁니다',
      // 상위 schemaVersion(구버전 exe로 되돌아간 경우)도 「못 읽음」으로 온다 — 그때는
      // 파일이 멀쩡하니 고칠 것은 앱 쪽이다. 상태는 색이 아니라 글자로 전한다.
      '· 앱이 더 새 버전으로 저장한 파일이면 앱을 업데이트해 주세요',
    ],
    if (recovered.isNotEmpty) '· 되살린 쪽은 가장 최근 변경 한 번이 빠졌을 수 있습니다',
  ];

  return (
    title: unreadable.isNotEmpty ? '데이터 파일을 읽지 못했습니다' : '데이터를 백업에서 되살렸습니다',
    detail: lines.join('\n'),
  );
}
