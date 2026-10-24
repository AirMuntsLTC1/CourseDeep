import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/chat_page.dart';
import 'services/ai_service.dart';
import 'services/native_service.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  NativeService().init(); // load libcoursedeep.so (C++)
  AiService.warmUp(); // free ping: wakes the edge function, uses no AI quota
  runApp(const CourseDeepApp());
}

class CourseDeepApp extends StatefulWidget {
  const CourseDeepApp({super.key});
  @override
  State<CourseDeepApp> createState() => _CourseDeepAppState();
}

class _CourseDeepAppState extends State<CourseDeepApp> {
  ThemeMode _mode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _loadMode();
  }

  Future<void> _loadMode() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString('theme_mode');
      if (v != null && mounted) setState(() => _mode = v == 'light' ? ThemeMode.light : ThemeMode.dark);
    } catch (_) {}
  }

  bool _isDark(BuildContext c) => _mode == ThemeMode.dark || (_mode == ThemeMode.system && MediaQuery.platformBrightnessOf(c) == Brightness.dark);

  Future<void> _toggle(BuildContext c) async {
    final next = _isDark(c) ? ThemeMode.light : ThemeMode.dark;
    setState(() => _mode = next);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('theme_mode', next == ThemeMode.light ? 'light' : 'dark');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CourseDeep',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: _mode,
      home: Builder(
        builder: (c) => ChatPage(isDark: _isDark(c), onToggleTheme: () => _toggle(c)),
      ),
    );
  }
}
