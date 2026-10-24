import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'config.dart';
import 'pages/chat_page.dart';


void _preWarmBackend() async {
  try {
    // Send a tiny dummy request to wake up the Supabase Edge Function
    await http.post(
      Uri.parse(kBackendUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'messages': [{'role': 'user', 'content': 'ping'}]}),
    ).timeout(const Duration(seconds: 5));
  } catch (_) {
    // Ignore errors, this is just to warm up the server
  }
}

void main() {
  _preWarmBackend(); // Fire and forget
  runApp(const CourseDeepApp());
}


class CourseDeepApp extends StatefulWidget {
  const CourseDeepApp({super.key});

  @override
  State<CourseDeepApp> createState() => _CourseDeepAppState();
}

class _CourseDeepAppState extends State<CourseDeepApp> {
  ThemeMode _mode = ThemeMode.system;

  bool get _isDark {
    if (_mode == ThemeMode.dark) return true;
    if (_mode == ThemeMode.light) return false;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  ThemeData _theme(Brightness b) => ThemeData(
        useMaterial3: true,
        colorScheme:
            ColorScheme.fromSeed(seedColor: const Color(0xFF6C4CF5), brightness: b),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CourseDeep',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _mode,
      home: ChatPage(
        isDark: _isDark,
        onToggleTheme: () =>
            setState(() => _mode = _isDark ? ThemeMode.light : ThemeMode.dark),
      ),
    );
  }
}
