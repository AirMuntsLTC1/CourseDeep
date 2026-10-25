import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pages/chat_page.dart';
import 'pages/email_code_login_page.dart';
import 'services/ai_service.dart';
import 'services/native_service.dart';
import 'theme/app_theme.dart';

const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String _supabasePublishableKey =
    String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final configured = _supabaseUrl.startsWith('https://') &&
      _supabasePublishableKey.isNotEmpty;

  if (configured) {
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabasePublishableKey,
    );
  }

  NativeService().init(); // load libcoursedeep.so (C++)
  AiService.warmUp(); // free ping: wakes the edge function, uses no AI quota
  runApp(CourseDeepApp(supabaseConfigured: configured));
}

class CourseDeepApp extends StatefulWidget {
  const CourseDeepApp({super.key, required this.supabaseConfigured});

  final bool supabaseConfigured;
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
        builder: (c) => _CourseDeepAuthGate(
          configured: widget.supabaseConfigured,
          isDark: _isDark(c),
          onToggleTheme: () => _toggle(c),
        ),
      ),
    );
  }
}


class _CourseDeepAuthGate extends StatelessWidget {
  const _CourseDeepAuthGate({
    required this.configured,
    required this.isDark,
    required this.onToggleTheme,
  });

  final bool configured;
  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    if (!configured) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'CourseDeep is not configured for Supabase. '
              'Check the SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY '
              'build settings, then rebuild the app.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      );
    }

    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          return ChatPage(
            isDark: isDark,
            onToggleTheme: onToggleTheme,
          );
        }
        return const EmailCodeLoginPage();
      },
    );
  }
}
