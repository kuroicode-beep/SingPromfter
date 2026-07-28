import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:singpromfter_app/services/level_analysis_service.dart';
import 'package:singpromfter_app/services/pitch_variant_service.dart';
import 'package:singpromfter_app/services/track_asset_service.dart';

/// 임시 폴더를 Documents로 쓰게 만드는 테스트용 path_provider.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

// 반주 파일이 바뀌면 그 파일에서 파생된 캐시만 지운다.
// 안 지우면 예전 오디오의 키 변형본·EQ 파형이 그대로 서빙된다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late TrackAssetService service;
  late Directory pitchDir;
  late Directory levelsDir;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sp_assets_');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
    // 도구 탐색이 실제 프로세스를 띄우지 않도록 SharedPreferences만 목으로 둔다.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (call) async => <String, Object>{},
        );

    final pitch = PitchVariantService();
    final levels = LevelAnalysisService();
    service = TrackAssetService(pitch: pitch, levels: levels);

    pitchDir = await pitch.cacheDir;
    levelsDir = await levels.cacheDir;
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> write(Directory dir, String name) =>
      File('${dir.path}/$name').writeAsString('x');

  Future<bool> exists(Directory dir, String name) =>
      File('${dir.path}/$name').exists();

  test('그 반주의 키 변형본을 전부 지운다', () async {
    await write(pitchDir, '밤편지_mr2__p-2.m4a');
    await write(pitchDir, '밤편지_mr2__p+3.m4a');

    final removed = await service.invalidate('밤편지_mr2.mp3');

    expect(removed, 2);
    expect(await exists(pitchDir, '밤편지_mr2__p-2.m4a'), isFalse);
    expect(await exists(pitchDir, '밤편지_mr2__p+3.m4a'), isFalse);
  });

  test('레벨 분석 캐시를 지운다', () async {
    await write(levelsDir, '밤편지_mr2.mp3.levels.json');

    final removed = await service.invalidate('밤편지_mr2.mp3');

    expect(removed, 1);
    expect(await exists(levelsDir, '밤편지_mr2.mp3.levels.json'), isFalse);
  });

  test('다른 반주·다른 슬롯의 캐시는 남긴다', () async {
    await write(pitchDir, '밤편지_mr2__p-2.m4a');
    await write(pitchDir, '밤편지_mr3__p-2.m4a');
    await write(pitchDir, '봄날_mr2__p-2.m4a');
    await write(levelsDir, '밤편지_mr2.mp3.levels.json');
    await write(levelsDir, '봄날_mr2.mp3.levels.json');

    await service.invalidate('밤편지_mr2.mp3');

    expect(await exists(pitchDir, '밤편지_mr3__p-2.m4a'), isTrue);
    expect(await exists(pitchDir, '봄날_mr2__p-2.m4a'), isTrue);
    expect(await exists(levelsDir, '봄날_mr2.mp3.levels.json'), isTrue);
  });

  test('지울 게 없으면 0', () async {
    expect(await service.invalidate('없는파일_mr1.mp3'), 0);
  });

  test('빈 파일명은 아무것도 하지 않는다', () async {
    await write(pitchDir, '밤편지_mr2__p-2.m4a');
    expect(await service.invalidate('  '), 0);
    expect(await exists(pitchDir, '밤편지_mr2__p-2.m4a'), isTrue);
  });
}
