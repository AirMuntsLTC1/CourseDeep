import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pages/chat_page.dart';
import 'pages/email_code_login_page.dart';
import 'services/ai_service.dart';
import 'services/app_settings.dart';
import 'services/native_service.dart';
import 'services/update_service.dart';
import 'theme/app_theme.dart';

const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String _supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final configured = _supabaseUrl.startsWith('https://') && _supabasePublishableKey.isNotEmpty;

  // Supabase and the saved settings load in parallel.
  await Future.wait([
    if (configured) Supabase.initialize(url: _supabaseUrl, publishableKey: _supabasePublishableKey),
    AppSettings.I.load(),
  ]);

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
  @override
  void initState() {
    super.initState();
    // Old version of the app? Show the blocking update dialog (works on top of login and chat).
    WidgetsBinding.instance.addPostFrameCallback((_) => UpdateService.checkAndShow(navigatorKey));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.I,
      builder: (context, _) => MaterialApp(
        title: 'CourseDeep',
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: AppSettings.I.themeMode,
        home: _CourseDeepAuthGate(configured: widget.supabaseConfigured),
      ),
    );
  }
}

class _CourseDeepAuthGate extends StatelessWidget {
  const _CourseDeepAuthGate({required this.configured});
  final bool configured;

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
        if (session != null) return const ChatPage();
        return const EmailCodeLoginPage();
      },
    );
  }
}
