// file: test/utils/platform_capabilities_test.dart
//
// 플랫폼 능력 게이트. 모바일에서는 설정을 어떻게 만져도 로컬 AI가 켜지지
// 않아야 한다 — PC 설정을 백업으로 옮겨 오면 켜진 값이 그대로 따라온다.
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/models/app_destination.dart';
import 'package:singpromfter_app/models/prompter_settings.dart';
import 'package:singpromfter_app/utils/platform_capabilities.dart';

void main() {
  tearDown(() => PlatformCapabilities.debugIsMobileOverride = null);

  group('데스크탑(기본 실행 환경)', () {
    test('외부 도구·로컬AI·녹음·제어서버가 모두 가능', () {
      expect(PlatformCapabilities.isMobile, isFalse);
      expect(PlatformCapabilities.hasExternalTools, isTrue);
      expect(PlatformCapabilities.hasLocalAi, isTrue);
      expect(PlatformCapabilities.hasDeviceRecording, isTrue);
      expect(PlatformCapabilities.hasControlServer, isTrue);
    });

    test('탭은 하나도 빠지지 않는다', () {
      expect(unavailableDestinations, isEmpty);
    });
  });

  group('모바일', () {
    setUp(() => PlatformCapabilities.debugIsMobileOverride = true);

    test('외부 도구·로컬AI·녹음·제어서버가 모두 불가', () {
      expect(PlatformCapabilities.hasExternalTools, isFalse);
      expect(PlatformCapabilities.hasLocalAi, isFalse);
      expect(PlatformCapabilities.hasDeviceRecording, isFalse);
      expect(PlatformCapabilities.hasControlServer, isFalse);
      expect(PlatformCapabilities.hasWindowControl, isFalse);
    });

    test('AI 설정이 켜져 있어도 로컬AI는 죽어 있다 — PC 백업을 옮겨 와도', () {
      const s = PrompterSettings(aiEnabled: true, localAiEnabled: true);
      expect(s.localAiActive, isFalse);
    });

    test('쓸 수 없는 탭은 목록에서 빠진다', () {
      expect(
        unavailableDestinations,
        containsAll(<AppDestination>{
          AppDestination.recordings,
          AppDestination.youtube,
          AppDestination.jobs,
          AppDestination.compose,
        }),
      );
    });

    test('AI 없이 되는 화면은 남는다 — 오폭 방지', () {
      for (final keep in [
        AppDestination.home,
        AppDestination.search,
        AppDestination.favorites,
        AppDestination.training,
        AppDestination.help,
        AppDestination.settings,
      ]) {
        expect(unavailableDestinations, isNot(contains(keep)));
      }
    });
  });
}
