// file: lib/services/process/external_tool_locator.dart
//
// yt-dlp·ffmpeg 실행 파일을 찾는다. 앱에 번들하지 않고 사용자 환경의 도구를
// 호출하는 방침이라, 경로 탐색과 "없을 때 안내"가 중요하다.
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'process_runner.dart';

enum ExternalTool { ytDlp, ffmpeg }

extension ExternalToolInfo on ExternalTool {
  String get executableName =>
      this == ExternalTool.ytDlp ? 'yt-dlp' : 'ffmpeg';

  String get displayName =>
      this == ExternalTool.ytDlp ? 'yt-dlp' : 'ffmpeg';

  /// 사용자가 직접 설치할 때 안내할 명령.
  String get installHint => this == ExternalTool.ytDlp
      ? 'winget install yt-dlp'
      : 'winget install Gyan.FFmpeg';

  String get prefsKey => 'tool_path_$executableName';
}

class ToolLocation {
  final ExternalTool tool;
  final String? path;
  final String? version;

  const ToolLocation({required this.tool, this.path, this.version});

  bool get found => path != null && path!.isNotEmpty;
}

class ExternalToolLocator {
  final ProcessRunner _runner;

  ExternalToolLocator({ProcessRunner runner = const SystemProcessRunner()})
    : _runner = runner;

  final Map<ExternalTool, ToolLocation> _cache = {};

  /// 후보 경로를 우선순위대로 정렬한다. (순수 함수 — 테스트 대상)
  ///
  /// 1) 사용자가 직접 지정한 경로
  /// 2) PATH에서 찾은 경로
  /// 3) 알려진 설치 위치
  static List<String> rankCandidates({
    String? userPath,
    String? pathLookup,
    List<String> knownPaths = const [],
  }) {
    final ordered = <String>[
      if (userPath != null && userPath.trim().isNotEmpty) userPath.trim(),
      if (pathLookup != null && pathLookup.trim().isNotEmpty) pathLookup.trim(),
      ...knownPaths.where((p) => p.trim().isNotEmpty),
    ];
    // 중복 제거하되 순서는 유지한다.
    final seen = <String>{};
    return ordered
        .where((p) => seen.add(p.toLowerCase()))
        .toList(growable: false);
  }

  /// 이 환경에서 흔한 설치 위치들.
  static List<String> knownPathsFor(
    ExternalTool tool, {
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    final localAppData = env['LOCALAPPDATA'];
    final programFiles = env['ProgramFiles'];
    final name = tool.executableName;
    final exe = Platform.isWindows ? '$name.exe' : name;

    return [
      if (localAppData != null) ...[
        '$localAppData\\Microsoft\\WinGet\\Links\\$exe',
        '$localAppData\\Programs\\Python\\Python313\\Scripts\\$exe',
        '$localAppData\\Programs\\Python\\Python312\\Scripts\\$exe',
      ],
      if (programFiles != null) '$programFiles\\$name\\bin\\$exe',
      'C:\\$name\\bin\\$exe',
    ];
  }

  Future<ToolLocation> locate(ExternalTool tool, {bool refresh = false}) async {
    if (!refresh && _cache.containsKey(tool)) return _cache[tool]!;

    final prefs = await SharedPreferences.getInstance();
    final userPath = prefs.getString(tool.prefsKey);
    final fromPath = await _lookupOnPath(tool.executableName);

    final candidates = rankCandidates(
      userPath: userPath,
      pathLookup: fromPath,
      knownPaths: knownPathsFor(tool),
    );

    for (final candidate in candidates) {
      if (!await _exists(candidate)) continue;
      final version = await _readVersion(tool, candidate);
      if (version == null) continue;
      final location = ToolLocation(
        tool: tool,
        path: candidate,
        version: version,
      );
      _cache[tool] = location;
      return location;
    }

    final missing = ToolLocation(tool: tool);
    _cache[tool] = missing;
    return missing;
  }

  /// 사용자가 파일 선택으로 직접 지정한 경로를 저장한다.
  Future<ToolLocation> setUserPath(ExternalTool tool, String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(tool.prefsKey, path);
    _cache.remove(tool);
    return locate(tool, refresh: true);
  }

  Future<bool> _exists(String path) async {
    // PATH에서 온 이름뿐인 값은 존재 검사를 건너뛴다(실행 시 확인).
    if (!path.contains(Platform.pathSeparator) && !path.contains('/')) {
      return true;
    }
    return File(path).exists();
  }

  Future<String?> _lookupOnPath(String name) async {
    final finder = Platform.isWindows ? 'where' : 'which';
    final result = await _runner.run(finder, [name]);
    if (!result.ok) return null;
    final first = result.stdout
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return first.isEmpty ? null : first.first;
  }

  Future<String?> _readVersion(ExternalTool tool, String path) async {
    final args = tool == ExternalTool.ytDlp ? ['--version'] : ['-version'];
    final result = await _runner.run(path, args);
    if (!result.ok) return null;
    final line = result.stdout.split(RegExp(r'\r?\n')).first.trim();
    return line.isEmpty ? tool.displayName : line;
  }
}
