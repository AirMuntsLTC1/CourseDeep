import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';

List<Map<String, dynamic>> _parseAll(List<String> raw) {
  final out = <Map<String, dynamic>>[];
  for (final r in raw) {
    try {
      out.add(Map<String, dynamic>.from(jsonDecode(r) as Map));
    } catch (_) {}
  }
  return out;
}

/// One JSON file per chat, written in the background and debounced — no more
/// re-encoding every chat (and every image) on the UI thread after each message.
class ChatStore {
  final Map<String, Timer> _timers = {};
  Directory? _dirCache;

  Future<Directory> _dir() async {
    if (_dirCache != null) return _dirCache!;
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, 'chats'));
    if (!await d.exists()) await d.create(recursive: true);
    return _dirCache = d;
  }

  Future<List<ChatSession>> load() async {
    final d = await _dir();
    final raws = <String>[];
    for (final f in d.listSync().whereType<File>()) {
      if (f.path.endsWith('.json')) raws.add(await f.readAsString());
    }
    final maps = await compute(_parseAll, raws);
    final list = <ChatSession>[];
    for (final m in maps) {
      try {
        list.add(ChatSession.fromJson(m));
      } catch (_) {}
    }
    list.sort((a, b) => b.updated.compareTo(a.updated));
    if (list.isEmpty) return _migrateOld();
    return list;
  }

  /// Imports chats saved by the previous app version (SharedPreferences), once.
  Future<List<ChatSession>> _migrateOld() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('coursedeep_sessions_v1');
      if (raw == null) return [];
      final list = <ChatSession>[];
      for (final e in jsonDecode(raw) as List) {
        final j = Map<String, dynamic>.from(e as Map);
        final msgs = <ChatMessage>[];
        for (final m in (j['messages'] as List? ?? [])) {
          final mm = Map<String, dynamic>.from(m as Map);
          msgs.add(ChatMessage(
            role: mm['role'] as String? ?? 'assistant',
            text: mm['text'] as String? ?? '',
            time: DateTime.tryParse(mm['time'] as String? ?? ''),
            sources: (mm['sources'] as List? ?? []).map((s) => Source.fromJson(Map<String, dynamic>.from(s as Map))).toList(),
            attachments: [
              if (mm['fileName'] != null)
                Attachment(name: mm['fileName'] as String, kind: AttachKind.text, text: mm['fileText'] as String?),
            ],
          ));
        }
        list.add(ChatSession(
          id: j['id'] as String,
          title: j['title'] as String? ?? 'New chat',
          updated: DateTime.tryParse(j['updated'] as String? ?? ''),
          messages: msgs,
        ));
      }
      for (final s in list) {
        await _write(s);
      }
      await prefs.remove('coursedeep_sessions_v1');
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(ChatSession s) async {
    final d = await _dir();
    final f = File(p.join(d.path, '${s.id}.json'));
    await f.writeAsString(jsonEncode(s.toJson()), flush: true);
  }

  /// Debounced save of ONE chat.
  void save(ChatSession s, {bool now = false}) {
    _timers[s.id]?.cancel();
    if (now) {
      _write(s);
      return;
    }
    _timers[s.id] = Timer(const Duration(milliseconds: 500), () => _write(s));
  }

  /// Removes the chat file right away (attachments are kept so "Undo" still works).
  Future<void> delete(ChatSession s) async {
    _timers[s.id]?.cancel();
    final d = await _dir();
    final f = File(p.join(d.path, '${s.id}.json'));
    if (await f.exists()) await f.delete();
  }

  /// Deletes ALL chats and their files.
  Future<void> clear() async {
    _timers.forEach((_, t) => t.cancel());
    _timers.clear();
    final d = await _dir();
    for (final f in d.listSync().whereType<File>()) {
      if (f.path.endsWith('.json')) {
        try { await f.delete(); } catch (_) {}
      }
    }
  }

  /// Deletes the stored copies of a chat's images/files (call after Undo expired).
  Future<void> purgeAttachments(ChatSession s) async {
    for (final m in s.messages) {
      for (final a in m.attachments) {
        if (a.path != null) {
          try {
            await File(a.path!).delete();
          } catch (_) {}
        }
      }
    }
  }
}
