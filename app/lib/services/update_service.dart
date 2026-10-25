import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../widgets/update_dialog.dart';

class UpdateService {
  // 🔁 Replace this with the raw URL of your version.json file
  static const String _versionUrl = 'https://raw.githubusercontent.com/AirMuntsLTC1/CourseDeep/main/version.json';

  static Future<void> checkForUpdates(BuildContext context) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await http.get(Uri.parse(_versionUrl)).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final latestVersion = data['version'] as String;
        final downloadUrl = data['downloadUrl'] as String;
        final description = data['description'] as String? ?? 'A new version of CourseDeep is available with bug fixes and improvements.';

        if (latestVersion != currentVersion) {
          if (context.mounted) {
            showDialog(
              context: context,
              barrierDismissible: false, // Force update - user cannot close dialog
              builder: (ctx) => UpdateDialog(
                latestVersion: latestVersion,
                downloadUrl: downloadUrl,
                description: description,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
  }
}
