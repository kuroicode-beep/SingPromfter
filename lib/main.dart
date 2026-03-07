import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/song_list_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
    return MaterialApp(
      title: 'SingPromfter',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const SongListScreen(),
    );
  }
}
