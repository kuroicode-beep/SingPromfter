import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:singpromfter_app/screens/song_list_screen.dart';
import 'package:window_manager/window_manager.dart';
import 'services/app_display_controller.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 보더리스 풀스크린 — 노래방 프롬프터답게 화면 전체를 쓴다.
  // 창 조작이 필요하면 F11로 창 모드를 오갈 수 있다(아래 토글).
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        titleBarStyle: TitleBarStyle.hidden,
        fullScreen: true,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  await AppDisplayController.load();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.surface,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const SingPromfterApp());
}

class SingPromfterApp extends StatefulWidget {
  const SingPromfterApp({super.key});

  @override
  State<SingPromfterApp> createState() => _SingPromfterAppState();
}

class _SingPromfterAppState extends State<SingPromfterApp> {
  /// F11 — 보더리스 풀스크린 ↔ 창 모드 토글.
  ///
  /// 포커스와 무관하게 동작해야 해서(다이얼로그·입력창 안에서도)
  /// HardwareKeyboard 전역 핸들러를 쓴다. 기존 단축키 체계(PrompterKeyboardScope)
  /// 는 F11을 쓰지 않으므로 충돌이 없다.
  bool _handleKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.f11 &&
        Platform.isWindows) {
      () async {
        final full = await windowManager.isFullScreen();
        await windowManager.setFullScreen(!full);
      }();
      return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppDisplaySettings>(
      valueListenable: AppDisplayController.notifier,
      builder: (context, display, _) {
        return MaterialApp(
          title: 'SingPromfter',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(
            fontFamily: AppDisplayController.familyFor(display.fontKey),
          ),
          builder: (context, child) => MediaQuery(
            // 앱 크롬에 글자 크기 배율 적용. (무대 프롬프터는 자체 배율로 초기화)
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(display.textScale)),
            child: child!,
          ),
          home: const SongListScreen(),
        );
      },
    );
  }
}
