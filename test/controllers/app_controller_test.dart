import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singpromfter_app/controllers/app_controller.dart';
import 'package:singpromfter_app/models/mr_source_mode.dart';

// AppController의 제어 API 게이트 — 저작권 ack 없이는 가져오기가 거절된다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 테스트 환경에는 audioplayers 네이티브가 없다 — 채널을 무해하게 막는다.
    for (final name in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            MethodChannel(name),
            (call) async => null,
          );
    }
  });

  group('enqueueImport 게이트', () {
    late AppController app;

    tearDown(() => app.dispose());

    test('유튜브 주소가 아니면 not_youtube_url', () async {
      SharedPreferences.setMockInitialValues({});
      app = AppController();
      final outcome = await app.enqueueImport(
        'https://vimeo.com/123',
        MrSourceMode.asIs,
      );
      expect(outcome.ok, isFalse);
      expect(outcome.errorCode, 'not_youtube_url');
    });

    test('ack가 없으면 notice_not_acked — 제어 API가 우회할 수 없다', () async {
      SharedPreferences.setMockInitialValues({});
      app = AppController();
      final outcome = await app.enqueueImport(
        'https://youtu.be/abc',
        MrSourceMode.asIs,
      );
      expect(outcome.ok, isFalse);
      expect(outcome.errorCode, 'notice_not_acked');
      expect(outcome.message, contains('앱에서'));
    });

    test('ack가 있으면 큐에 들어간다', () async {
      SharedPreferences.setMockInitialValues({'yt_notice_ack': true});
      app = AppController();
      final outcome = await app.enqueueImport(
        'https://youtu.be/abc',
        MrSourceMode.asIs,
      );
      expect(outcome.ok, isTrue);
      expect(outcome.jobId, isNotEmpty);
      expect(app.importJobs.jobs, hasLength(1));
      // 테스트 환경에는 yt-dlp가 없어 잡은 실패로 끝난다 — 큐 등록만 검증.
    });
  });

  group('songById', () {
    test('없는 id는 null', () async {
      SharedPreferences.setMockInitialValues({});
      final app = AppController();
      expect(app.songById('nope'), isNull);
      app.dispose();
    });
  });
}
