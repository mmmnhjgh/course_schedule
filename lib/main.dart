import 'package:material_ui/material_ui.dart';

import 'pages/home_page.dart';

void main() {
  runApp(const CourseScheduleApp());
}

class CourseScheduleApp extends StatefulWidget {
  const CourseScheduleApp({super.key});

  @override
  State<CourseScheduleApp> createState() => _CourseScheduleAppState();
}

class _CourseScheduleAppState extends State<CourseScheduleApp> {
  int _seedColorValue = 0xFF2B7FFF;
  ThemeMode _themeMode = ThemeMode.system;

  void _updateAppearance(int colorValue, String modeStr) {
    final nextMode = switch (modeStr) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    if (_seedColorValue == colorValue && _themeMode == nextMode) return;
    setState(() {
      _seedColorValue = colorValue;
      _themeMode = nextMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    final seed = Color(_seedColorValue);
    return MaterialApp(
      title: '轻课表',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
      ),
      home: HomePage(onAppearanceChanged: _updateAppearance),
    );
  }
}
