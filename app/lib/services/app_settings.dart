import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One place for every user setting. Pages listen to it, so a change in Settings
/// is applied everywhere instantly (theme, font size, language, defaults).
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings I = AppSettings._();

  ThemeMode themeMode = ThemeMode.dark;
  double fontSize = 16.5;
  String language = 'English';
  bool searchDefault = true;
  bool thinkDefault = false;
  bool haptics = true;
  bool voiceEnabled = false;

  SharedPreferences? _p;

  Future<void> load() async {
    try {
      final p = _p = await SharedPreferences.getInstance();
      final t = p.getString('theme_mode');
      themeMode = t == 'light' ? ThemeMode.light : t == 'system' ? ThemeMode.system : ThemeMode.dark;
      fontSize = p.getDouble('ai_font_size') ?? 16.5;
      language = p.getString('app_language') ?? 'English';
      searchDefault = p.getBool('search_default') ?? true;
      thinkDefault = p.getBool('think_default') ?? false;
      haptics = p.getBool('haptics') ?? true;
      voiceEnabled = p.getBool('voice_enabled') ?? false;
    } catch (_) {}
  }

  bool isDark(BuildContext c) =>
      themeMode == ThemeMode.dark || (themeMode == ThemeMode.system && MediaQuery.platformBrightnessOf(c) == Brightness.dark);

  Future<void> _save(Future<bool> Function(SharedPreferences p) f) async {
    notifyListeners();
    try {
      final p = _p ??= await SharedPreferences.getInstance();
      await f(p);
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode m) {
    themeMode = m;
    return _save((p) => p.setString('theme_mode', m == ThemeMode.light ? 'light' : m == ThemeMode.system ? 'system' : 'dark'));
  }

  Future<void> toggleTheme(BuildContext c) => setThemeMode(isDark(c) ? ThemeMode.light : ThemeMode.dark);

  Future<void> setFontSize(double v) {
    fontSize = v;
    return _save((p) => p.setDouble('ai_font_size', v));
  }

  Future<void> setLanguage(String v) {
    language = v;
    return _save((p) => p.setString('app_language', v));
  }

  Future<void> setSearchDefault(bool v) {
    searchDefault = v;
    return _save((p) => p.setBool('search_default', v));
  }

  Future<void> setThinkDefault(bool v) {
    thinkDefault = v;
    return _save((p) => p.setBool('think_default', v));
  }

  Future<void> setHaptics(bool v) {
    haptics = v;
    return _save((p) => p.setBool('haptics', v));
  }

  Future<void> setVoiceEnabled(bool v) {
    voiceEnabled = v;
    return _save((p) => p.setBool('voice_enabled', v));
  }
}

/// Vibration feedback that respects the Haptics switch in Settings.
void haptic(Future<void> Function() f) {
  if (AppSettings.I.haptics) f();
}
