import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:singpromfter_app/screens/song_list_screen.dart';
import 'services/app_display_controller.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

class SingPromfterApp extends StatelessWidget {
  const SingPromfterApp({super.key});

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
