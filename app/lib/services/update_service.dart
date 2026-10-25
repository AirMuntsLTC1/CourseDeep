import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../widgets/update_dialog.dart';

class UpdateInfo {
  UpdateInfo({required this.version, required this.apkUrl, required this.notes});
  final String version;
  final String apkUrl;
  final String notes;
}

class UpdateService {
  static bool _shown = false;

  /// Compares versions like 2.3.0.7 (any number of parts).
  static bool isNewer(String a, String b) {
    List<int> p(String v) => v.split(RegExp(r'[.+\-]')).map((e) => int.tryParse(e.replaceAll(RegExp(r'\D'), '')) ?? 0).toList();
    final x = p(a), y = p(b);
    for (var i = 0; i < 4; i++) {
      final xi = i < x.length ? x[i] : 0, yi = i < y.length ? y[i] : 0;
      if (xi != yi) return xi > yi;
    }
    return false;
  }

  /// Reads the latest GitHub release. Returns null when the app is already up to date.
  static Future<UpdateInfo?> fetchLatest() async {
    final r = await http
        .get(Uri.parse(kReleasesApi), headers: {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final j = jsonDecode(r.body) as Map;
    final tag = (j['tag_name'] ?? '').toString().replaceFirst(RegExp(r'^[vV]'), '');
    if (tag.isEmpty || !isNewer(tag, kAppVersion)) return null;
    String? apk;
    for (final a in (j['assets'] as List? ?? [])) {
      final name = (a['name'] ?? '').toString().toLowerCase();
      if (name.endsWith('.apk')) {
        apk = a['browser_download_url']?.toString();
        break;
      }
    }
    if (apk == null) return null;
    var notes = (j['body'] ?? '').toString().trim();
    if (notes.isEmpty || notes.startsWith('Automatic build')) {
      notes = 'A new version of CourseDeep is ready with improvements and bug fixes.';
    }
    return UpdateInfo(version: tag, apkUrl: apk, notes: notes);
  }

  /// Shows the blocking "Update required" dialog when an older app version is running.
  /// [navKey] is the MaterialApp navigator key (a context above MaterialApp cannot show dialogs).
  static Future<void> checkAndShow(GlobalKey<NavigatorState> navKey) async {
    if (_shown) return;
    try {
      final info = await fetchLatest();
      if (info == null) return;
      final ctx = navKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      _shown = true;
      await showDialog<void>(
        context: ctx,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (_) => UpdateDialog(info: info),
      );
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
  }
}
