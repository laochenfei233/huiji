import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yanji/database_init.dart';
import 'package:yanji/screens/home_screen.dart';
import 'package:yanji/screens/meeting_setup_screen.dart';
import 'package:yanji/screens/meeting_recording_screen.dart';
import 'package:yanji/screens/meeting_summary_screen.dart';
import 'package:yanji/providers/meeting_provider.dart';
import 'package:yanji/providers/meeting_session_provider.dart';
import 'package:provider/provider.dart';
import 'package:yanji/utils/theme_utils.dart';

/// 全局 themeMode 通知器，设置页切换时实时生效
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.system);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initSqlite();

  // 读取暗色模式偏好
  final prefs = await SharedPreferences.getInstance();
  final darkMode = prefs.getBool('dark_mode') ?? false;
  themeModeNotifier.value = darkMode ? ThemeMode.dark : ThemeMode.light;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) => MeetingProvider(),
        ),
        ChangeNotifierProvider(
          create: (context) => MeetingSessionProvider(),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: '言记',
          theme: ThemeUtils.lightTheme,
          darkTheme: ThemeUtils.darkTheme,
          themeMode: mode,
          home: const HomeScreen(),
          routes: {
            '/meeting-setup': (context) => const MeetingSetupScreen(),
            '/meeting-recording': (context) => const MeetingRecordingScreen(),
            '/meeting-summary': (context) => const MeetingSummaryScreen(),
          },
          debugShowCheckedModeBanner: false,
          showPerformanceOverlay: false,
        );
      },
    );
  }
}
