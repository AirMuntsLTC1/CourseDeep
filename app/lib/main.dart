import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pages/chat_page.dart';
import 'pages/email_code_login_page.dart';
import 'services/ai_service.dart';
import 'services/app_settings.dart';
import 'services/native_service.dart';
import 'theme/app_theme.dart';
import 'widgets/brand.dart';

const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String _supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Show our own logo screen on the very first frame; load everything behind it.
  runApp(const _Boot());
}

class _Boot extends StatefulWidget {
  const _Boot();
  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  bool? _configured;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final configured = _supabaseUrl.startsWith('https://') && _supabasePublishableKey.isNotEmpty;
    await Future.wait([
      AppSettings.I.load(),
      if (configured) Supabase.initialize(url: _supabaseUrl, publishableKey: _supabasePublishableKey),
    ]);
    NativeService().init(); // load libcoursedeep.so (C++)
    AiService.warmUp(); // free ping: wakes the edge function, uses no AI quota
    if (mounted) setState(() => _configured = configured);
  }

  @override
  Widget build(BuildContext context) {
    final c = _configured;
    if (c != null) return CourseDeepApp(supabaseConfigured: c);
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFF0B0B12),
        body: Center(child: AiOrb(size: 96)),
      ),
    );
  }
}

class CourseDeepApp extends StatelessWidget {
  const CourseDeepApp({super.key, required this.supabaseConfigured});
  final bool supabaseConfigured;

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.I;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => MaterialApp(
        title: 'CourseDeep',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: s.themeMode,
        themeAnimationDuration: const Duration(milliseconds: 160),
        home: _AuthGate(configured: supabaseConfigured),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate({required this.configured});
  final bool configured;

  @override
  Widget build(BuildContext context) {
    if (!configured) {
      final pal = Pal.of(context);
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const AiMark(size: 64),
              const SizedBox(height: 18),
              Text('CourseDeep is not configured',
                  style: TextStyle(color: pal.text, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                'This build has no Supabase settings. Add the SUPABASE_PUBLISHABLE_KEY secret in GitHub '
                '(Settings → Secrets → Actions) and run the build again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: pal.dim, height: 1.5),
              ),
            ]),
          ),
        ),
      );
    }

    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      initialData: AuthState(AuthChangeEvent.initialSession, auth.currentSession),
      builder: (context, snap) {
        final session = snap.data?.session ?? auth.currentSession;
        if (session != null) return const ChatPage();
        return const EmailCodeLoginPage();
      },
    );
  }
}
