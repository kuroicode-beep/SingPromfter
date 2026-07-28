// file: lib/utils/music_key.dart
//
// 조성(調性) 표기. 순수 값 객체 — 테스트 대상.
//
// 표시 규칙은 대중적인 코드 표기를 따른다: 장조는 'C', 단조는 'Am'.
// 반음 이름은 관습적으로 더 자주 쓰이는 쪽(♯/♭)을 골라 고정한다.

enum KeyMode { major, minor }

class MusicKey {
  /// 0=C, 1=C♯, ... 11=B.
  final int pitchClass;
  final KeyMode mode;

  const MusicKey(this.pitchClass, this.mode);

  static const List<String> pitchNames = [
    'C',
    'C♯',
    'D',
    'E♭',
    'E',
    'F',
    'F♯',
    'G',
    'A♭',
    'A',
    'B♭',
    'B',
  ];

  /// 화면에 쓰는 이름. 장조 'C', 단조 'Am'.
  String get label {
    final name = pitchNames[pitchClass % 12];
    return mode == KeyMode.minor ? '${name}m' : name;
  }

  /// 반음만큼 옮긴 조성. 조성의 성격(장/단)은 그대로다.
  MusicKey transposed(int semitones) {
    final next = ((pitchClass + semitones) % 12 + 12) % 12;
    return MusicKey(next, mode);
  }

  String get storageValue => '$pitchClass:${mode.name}';

  static MusicKey? fromStorage(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    final pc = int.tryParse(parts[0]);
    if (pc == null || pc < 0 || pc > 11) return null;
    final mode = KeyMode.values.where((m) => m.name == parts[1]);
    if (mode.isEmpty) return null;
    return MusicKey(pc, mode.first);
  }

  /// 'C', 'Am', 'F♯m', 'Bb' 같은 사용자 입력을 읽는다. 못 읽으면 null.
  static MusicKey? parse(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return null;

    final minor = text.toLowerCase().endsWith('m');
    final body = (minor ? text.substring(0, text.length - 1) : text).trim();
    if (body.isEmpty) return null;

    final normalized = body
        .replaceAll('#', '♯')
        .replaceAll('b', '♭')
        .replaceAll('B♭', 'B♭'); // 'Bb' → 'B♭' 이후 대문자 B 보존
    final letter = normalized[0].toUpperCase();
    final accidental = normalized.length > 1 ? normalized.substring(1) : '';
    final candidate = '$letter$accidental';

    for (var i = 0; i < pitchNames.length; i++) {
      if (pitchNames[i] == candidate) {
        return MusicKey(i, minor ? KeyMode.minor : KeyMode.major);
      }
    }
    // 이명동음(D♯=E♭ 등)도 받아 준다.
    const enharmonic = {
      'D♭': 1,
      'D♯': 3,
      'G♭': 6,
      'G♯': 8,
      'A♯': 10,
      'C♭': 11,
      'F♭': 4,
      'E♯': 5,
      'B♯': 0,
    };
    final index = enharmonic[candidate];
    if (index == null) return null;
    return MusicKey(index, minor ? KeyMode.minor : KeyMode.major);
  }

  @override
  bool operator ==(Object other) =>
      other is MusicKey &&
      other.pitchClass == pitchClass &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(pitchClass, mode);

  @override
  String toString() => label;
}
