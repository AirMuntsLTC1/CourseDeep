import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Saves files straight into the phone's public Downloads folder - no share sheet, no Bluetooth.
/// Android: native MediaStore (see MainActivity.kt, written by the GitHub build).
/// iOS: there is no public Downloads folder, so the file goes to the app's Documents folder,
/// which shows up in the Files app (needs UIFileSharingEnabled in Info.plist - see README).
class DownloadService {
  static const _ch = MethodChannel('coursedeep/files');

  static const _mimes = {
    'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'gif': 'image/gif', 'webp': 'image/webp',
    'svg': 'image/svg+xml', 'pdf': 'application/pdf', 'zip': 'application/zip', 'json': 'application/json',
    'html': 'text/html', 'htm': 'text/html', 'css': 'text/css', 'js': 'text/javascript', 'csv': 'text/csv',
    'md': 'text/markdown', 'txt': 'text/plain', 'xml': 'text/xml', 'apk': 'application/vnd.android.package-archive',
  };

  static String mimeOf(String name) {
    final i = name.lastIndexOf('.');
    final e = i < 0 ? '' : name.substring(i + 1).toLowerCase();
    return _mimes[e] ?? 'application/octet-stream';
  }

  static String _safe(String n) {
    final base = n.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty && s != '..' && s != '.').lastOrNull ?? 'file';
    return base.replaceAll(RegExp(r'[<>:"|?*\x00-\x1F]'), '_');
  }

  /// Returns a human-readable location of the saved file.
  static Future<String> save(String name, Uint8List bytes, {String? mime}) async {
    final safe = _safe(name);
    if (Platform.isAndroid) {
      final r = await _ch.invokeMethod<String>('saveToDownloads', {
        'name': safe,
        'mime': mime ?? mimeOf(safe),
        'bytes': bytes,
      });
      return r ?? 'Downloads/$safe';
    }
    final dir = await getApplicationDocumentsDirectory();
    final f = File(p.join(dir.path, safe));
    await f.writeAsBytes(bytes, flush: true);
    return 'Files app > CourseDeep > $safe';
  }

  static Future<String> saveFromPath(String path, {String? name}) async {
    final bytes = await File(path).readAsBytes();
    return save(name ?? p.basename(path), bytes);
  }
}
