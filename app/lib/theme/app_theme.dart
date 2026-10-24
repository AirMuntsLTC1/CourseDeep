import 'package:flutter/material.dart';

class Brand {
  static const violet = Color(0xFF7C5CFF);
  static const cyan = Color(0xFF22D3EE);
  static const pink = Color(0xFFFF6BCB);
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [violet, Color(0xFF4F8CFF), cyan],
  );
}

class Pal {
  const Pal({
    required this.isDark,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.border,
    required this.text,
    required this.dim,
    required this.userBubble,
    required this.codeBg,
  });
  final bool isDark;
  final Color bg, surface, surface2, border, text, dim, userBubble, codeBg;

  static const dark = Pal(
    isDark: true,
    bg: Color(0xFF0B0B12),
    surface: Color(0xFF14141F),
    surface2: Color(0xFF1C1C2B),
    border: Color(0x1FFFFFFF),
    text: Color(0xFFF1F1F7),
    dim: Color(0xFF9A9AB0),
    userBubble: Color(0xFF232338),
    codeBg: Color(0xFF10101A),
  );
  static const light = Pal(
    isDark: false,
    bg: Color(0xFFF7F6FC),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEFEDF9),
    border: Color(0x1A1B1B3A),
    text: Color(0xFF16162A),
    dim: Color(0xFF6B6B84),
    userBubble: Color(0xFFE9E5FF),
    codeBg: Color(0xFFF1EFFA),
  );

  static Pal of(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? dark : light;
}

ThemeData buildTheme(Brightness b) {
  final p = b == Brightness.dark ? Pal.dark : Pal.light;
  final scheme = ColorScheme.fromSeed(seedColor: Brand.violet, brightness: b).copyWith(
    surface: p.bg,
    primary: b == Brightness.dark ? const Color(0xFF9D86FF) : Brand.violet,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    splashFactory: InkRipple.splashFactory,
    dividerColor: p.border,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.surface2,
      contentTextStyle: TextStyle(color: p.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: p.bg, surfaceTintColor: Colors.transparent),
  );
}
