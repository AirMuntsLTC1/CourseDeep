
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'download_service.dart';
import '../models/chat_message.dart';
import '../util/segments.dart';
import 'native_service.dart';

const int kMaxTextPerFile = 60000; // characters sent to the AI per attachment
const int kMaxFileBytes = 25 * 1024 * 1024;
const int kMaxBinaryBytes = 7 * 1024 * 1024; // images / PDFs are sent as base64

const _imageExt = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'};
const _textExt = {
  'txt', 'md', 'markdown', 'csv', 'tsv', 'json', 'jsonl', 'xml', 'yaml', 'yml', 'toml', 'ini', 'cfg', 'conf', 'env', 'log',
  'html', 'htm', 'css', 'scss', 'js', 'mjs', 'jsx', 'ts', 'tsx', 'vue', 'svelte', 'dart', 'py', 'java', 'kt', 'kts', 'swift',
  'c', 'h', 'cpp', 'hpp', 'cc', 'cs', 'go', 'rs', 'rb', 'php', 'sh', 'bash', 'bat', 'ps1', 'sql', 'gradle', 'properties',
  'lua', 'r', 'm', 'scala', 'dockerfile', 'makefile', 'tex', 'srt', 'svg', 'gitignore', 'lock', 'pro', 'plist',
};
const _skipDirs = ['node_modules/', '.git/', 'build/', '.dart_tool/', '__pycache__/', '.gradle/', 'Pods/', 'dist/', '.idea/'];

String extOf(String name) {
  final i = name.lastIndexOf('.');
  return i < 0 ? name.toLowerCase() : name.substring(i + 1).toLowerCase();
}

bool _textName(String n) => _textExt.contains(extOf(n));

String fmtSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

// ───────────── runs in a background isolate (no UI jank) ─────────────
String _unescape(String s) =>
    s.replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&apos;', "'").replaceAll('&amp;', '&');

String _str(ArchiveFile f) => utf8.decode((f.content as List).cast<int>(), allowMalformed: true);

ArchiveFile? _find(Archive a, String name) {
  for (final f in a.files) {
    if (f.name == name) return f;
  }
  return null;
}

String _docx(Archive a) {
  final f = _find(a, 'word/document.xml');
  if (f == null) return '';
  final xml = _str(f)
      .replaceAll('</w:p>', '\n')
      .replaceAll(RegExp(r'<w:tab/>'), '\t')
      .replaceAll(RegExp(r'<w:br[^>]*/>'), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  return _unescape(xml);
}

String _pptx(Archive a) {
  final slides = a.files.where((f) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(f.name)).toList()
    ..sort((x, y) => _num(x.name).compareTo(_num(y.name)));
  final sb = StringBuffer();
  var i = 1;
  for (final s in slides) {
    final xml = _str(s).replaceAll('</a:p>', '\n');
    final t = RegExp(r'<a:t>(.*?)</a:t>|\n', dotAll: true).allMatches(xml).map((m) => m.group(0) == '\n' ? '\n' : m.group(1) ?? '').join();
    sb.writeln('--- Slide ${i++} ---\n${_unescape(t).trim()}\n');
  }
  return sb.toString();
}

int _num(String s) => int.tryParse(RegExp(r'(\d+)').firstMatch(s.split('/').last)?.group(1) ?? '0') ?? 0;

String _xlsx(Archive a) {
  final shared = <String>[];
  final ss = _find(a, 'xl/sharedStrings.xml');
  if (ss != null) {
    for (final m in RegExp(r'<si>(.*?)</si>', dotAll: true).allMatches(_str(ss))) {
      final inner = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true).allMatches(m.group(1)!).map((x) => x.group(1) ?? '').join();
      shared.add(_unescape(inner));
    }
  }
  final sheets = a.files.where((f) => RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(f.name)).toList()
    ..sort((x, y) => _num(x.name).compareTo(_num(y.name)));
  final sb = StringBuffer();
  for (final sh in sheets) {
    sb.writeln('--- Sheet ${_num(sh.name)} ---');
    var rows = 0;
    for (final r in RegExp(r'<row\b[^>]*>(.*?)</row>', dotAll: true).allMatches(_str(sh))) {
      if (rows++ > 800) {
        sb.writeln('…[more rows omitted]');
        break;
      }
      final cells = <String>[];
      for (final c in RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true).allMatches(r.group(1)!)) {
        final attrs = c.group(1) ?? '';
        final body = c.group(2) ?? '';
        final type = RegExp(r't="(\w+)"').firstMatch(attrs)?.group(1);
        final v = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(body)?.group(1) ?? '';
        if (type == 's') {
          final idx = int.tryParse(v) ?? -1;
          cells.add(idx >= 0 && idx < shared.length ? shared[idx] : '');
        } else if (type == 'inlineStr') {
          cells.add(_unescape(RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true).firstMatch(body)?.group(1) ?? ''));
        } else {
          cells.add(_unescape(v));
        }
      }
      sb.writeln(cells.join('\t'));
    }
    sb.writeln();
  }
  return sb.toString();
}

Map<String, dynamic> extractInIsolate(Map<String, dynamic> a) {
  final path = a['path'] as String;
  final name = a['name'] as String;
  final ext = extOf(name);
  var kind = 'text';
  var text = '';
  String? note;
  try {
    if (ext == 'zip') {
      kind = 'archive';
      final arc = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
      final files = arc.files.where((f) => f.isFile && !_skipDirs.any((d) => f.name.contains(d))).toList();
      final sb = StringBuffer('[ZIP archive: $name — ${files.length} files]\nStructure:\n');
      for (final f in files.take(150)) {
        sb.writeln('  ${f.name}');
      }
      if (files.length > 150) sb.writeln('  …and ${files.length - 150} more');
      var used = 0, read = 0;
      for (final f in files) {
        if (!_textName(f.name) || f.size > 400000) continue;
        String c;
        try {
          c = utf8.decode((f.content as List).cast<int>());
        } catch (_) {
          continue;
        }
        if (used + c.length > kMaxTextPerFile) {
          sb.writeln('\n[Remaining files skipped: size limit reached]');
          break;
        }
        sb.writeln('\n--- File: ${f.name} ---\n$c');
        used += c.length;
        read++;
      }
      if (read == 0) sb.writeln('\nNo readable text/code files found in this ZIP.');
      text = sb.toString();
      note = '$read files read';
    } else if (ext == 'docx' || ext == 'xlsx' || ext == 'pptx') {
      kind = 'document';
      final arc = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
      text = ext == 'docx' ? _docx(arc) : ext == 'xlsx' ? _xlsx(arc) : _pptx(arc);
      if (text.trim().isEmpty) note = 'No text found';
    } else if (ext == 'pdf') {
      kind = 'pdf';
    } else {
      final bytes = File(path).readAsBytesSync();
      var nul = 0;
      for (var i = 0; i < bytes.length && i < 4000; i++) {
        if (bytes[i] == 0) nul++;
      }
      if (nul > 3 && !_textExt.contains(ext)) {
        note = 'Binary file — the AI can only read text, code, images, PDF, Word/Excel/PowerPoint and ZIP files.';
      } else {
        text = utf8.decode(bytes, allowMalformed: true);
      }
    }
  } catch (e) {
    note = 'Could not read this file ($e)';
  }
  if (text.isNotEmpty) {
    text = NativeService().squeeze(text);
    if (text.length > kMaxTextPerFile) {
      text = '${text.substring(0, kMaxTextPerFile)}\n…[file shortened to fit the AI limit]';
      note = 'Shortened';
    }
  }
  return {'kind': kind, 'text': text, 'note': note};
}

String _b64Isolate(String path) => base64Encode(File(path).readAsBytesSync());
String encodeJsonIsolate(Map<String, dynamic> m) => jsonEncode(m);

class FileService {
  static Future<Directory> _dir(String sub) async {
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, sub));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static String _safe(String n) => n.replaceAll(RegExp(r'[^\w.\- ]'), '_');

  static Future<File> _copyIn(String src, String name) async {
    final d = await _dir('attachments');
    return File(src).copy(p.join(d.path, '${DateTime.now().microsecondsSinceEpoch}_${_safe(name)}'));
  }

  static bool isImageName(String n) => _imageExt.contains(extOf(n));

  /// Image from gallery/camera -> stored copy.
  static Future<Attachment> image(String srcPath, String name) async {
    final f = await _copyIn(srcPath, name);
    final len = await f.length();
    if (len > kMaxBinaryBytes) {
      throw 'This image is too large (${fmtSize(len)}). Max ${fmtSize(kMaxBinaryBytes)}.';
    }
    return Attachment(name: name, kind: AttachKind.image, mime: 'image/jpeg', path: f.path, size: len);
  }

  /// Any file -> stored copy + text extracted in a background isolate.
  static Future<Attachment> file(String srcPath, String name) async {
    if (isImageName(name)) return image(srcPath, name);
    final len = await File(srcPath).length();
    if (len > kMaxFileBytes) throw 'File too large (${fmtSize(len)}). Max ${fmtSize(kMaxFileBytes)}.';
    final f = await _copyIn(srcPath, name);
    final r = await compute(extractInIsolate, {'path': f.path, 'name': name});
    final kind = AttachKind.values.firstWhere((k) => k.name == r['kind'], orElse: () => AttachKind.text);
    if (kind == AttachKind.pdf && len > kMaxBinaryBytes) throw 'PDF too large (${fmtSize(len)}). Max ${fmtSize(kMaxBinaryBytes)}.';
    final text = r['text'] as String;
    return Attachment(
      name: name,
      kind: kind,
      mime: kind == AttachKind.pdf ? 'application/pdf' : 'text/plain',
      path: f.path,
      text: text.isEmpty ? null : text,
      size: len,
      note: r['note'] as String?,
    );
  }

  static Future<String> base64Of(String path) => compute(_b64Isolate, path);

  // ───────────── files created BY the AI ─────────────

  static Future<String> saveFile(FileSeg f) =>
      DownloadService.save(f.name, Uint8List.fromList(utf8.encode(f.content)));

  /// SVG text blocks written by the AI.
  static Future<String> saveImage(ImageSeg img) =>
      DownloadService.save(img.name, Uint8List.fromList(utf8.encode(img.content)));

  /// Several files are bundled into one ZIP (keeps folders).
  static Future<String> saveZip(List<FileSeg> files, {String name = 'coursedeep-files.zip'}) async {
    final arc = Archive();
    for (final f in files) {
      final clean = f.name.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty && s != '..' && s != '.').join('/');
      final bytes = utf8.encode(f.content);
      arc.addFile(ArchiveFile.bytes(clean.isEmpty ? 'file.txt' : clean, Uint8List.fromList(bytes)));
    }
    final data = ZipEncoder().encode(arc);
    return DownloadService.save(name, Uint8List.fromList(data), mime: 'application/zip');
  }

  /// Images produced by the AI image generator (stored in the app folder).
  static Future<String> saveGeneratedImage(String path, String name) => DownloadService.saveFromPath(path, name: name);

  /// Stores base64 image bytes from the server in the app folder and returns the file.
  static Future<File> storeImageBytes(Uint8List bytes, String name) async {
    final d = await _dir('attachments');
    final f = File(p.join(d.path, '${DateTime.now().microsecondsSinceEpoch}_${_safe(name)}'));
    return f.writeAsBytes(bytes, flush: true);
  }
}
