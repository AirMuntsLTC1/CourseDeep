import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

/// Chats are stored in TWO places:
///   1. Local JSON file (fast, offline, instant)
///   2. Supabase `chats` table (permanent, survives reinstall / new phone)
///
/// Save = write local immediately + push to Supabase (debounced).
/// Load = read local first; if empty, pull from Supabase (e.g. after reinstall).
class ChatStore {
  final Map<String, Timer> _timers = {};
  Directory? _dirCache;

  SupabaseClient? get _db {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null; // Supabase not initialised (rare, but safe)
    }
  }

  String? get _userId => _db?.auth.currentUser?.id;

  Future<Directory> _dir() async {
    if (_dirCache != null) return _dirCache!;
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, 'chats'));
    if (!await d.exists()) await d.create(recursive: true);
    return _dirCache = d;
  }

  // ─────────────── LOAD ───────────────
  Future<List<ChatSession>> load() async {
    // 1) Local first
    final local = await _loadLocal();

    // 2) If we're signed in, refresh from Supabase so reinstalls restore history
    final db = _db;
    final uid = _userId;
    if (db != null && uid != null) {
      try {
        final rows = await db
            .from('chats')
            .select()
            .order('updated_at', ascending: false);
        final remote = <ChatSession>[];
        for (final row in (rows as List)) {
          try {
            remote.add(_fromRow(Map<String, dynamic>.from(row as Map)));
          } catch (_) {}
        }
        if (remote.isNotEmpty) {
          // Merge: remote wins for updated_at, but keep any local-only chats
          final byId = <String, ChatSession>{};
          for (final s in remote) byId[s.id] = s;
          for (final s in local) {
            if (!byId.containsKey(s.id)) byId[s.id] = s;
          }
          final merged = byId.values.toList()..sort((a, b) => b.updated.compareTo(a.updated));
          // Persist the merged result locally so future loads are instant
          for (final s in merged) {
            await _writeLocal(s);
          }
          return merged;
        }
      } catch (e) {
        debugPrint('ChatStore: remote load failed ($e) — using local only');
      }
    }

    if (local.isNotEmpty) return local;

    // 3) Fallback: migrate very old SharedPreferences store
    return _migrateOld();
  }

  Future<List<ChatSession>> _loadLocal() async {
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
    return list;
  }

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
        await save(s, now: true);
      }
      await prefs.remove('coursedeep_sessions_v1');
      return list;
    } catch (_) {
      return [];
    }
  }

  // ─────────────── SAVE ───────────────
  void save(ChatSession s, {bool now = false}) {
    _timers[s.id]?.cancel();
    if (now) {
      _saveNow(s);
      return;
    }
    _timers[s.id] = Timer(const Duration(milliseconds: 500), () => _saveNow(s));
  }

  Future<void> _saveNow(ChatSession s) async {
    // 1) Local — immediate, offline-safe
    await _writeLocal(s);

    // 2) Supabase — background, doesn't block UI
    final db = _db;
    final uid = _userId;
    if (db == null || uid == null) return;
    try {
      await db.from('chats').upsert({
        'id': s.id,
        'user_id': uid,
        'title': s.title,
        'messages': s.messages.where((m) => !m.streaming).map((m) => m.toJson()).toList(),
      }, onConflict: 'id');
    } catch (e) {
      debugPrint('ChatStore: remote save failed ($e) — kept locally');
    }
  }

  Future<void> _writeLocal(ChatSession s) async {
    final d = await _dir();
    final f = File(p.join(d.path, '${s.id}.json'));
    await f.writeAsString(jsonEncode(s.toJson()), flush: true);
  }

  ChatSession _fromRow(Map<String, dynamic> row) {
    final msgs = <ChatMessage>[];
    for (final m in (row['messages'] as List? ?? [])) {
      try {
        msgs.add(ChatMessage.fromJson(Map<String, dynamic>.from(m as Map)));
      } catch (_) {}
    }
    return ChatSession(
      id: row['id'] as String,
      title: row['title'] as String? ?? 'New chat',
      updated: DateTime.tryParse(row['updated_at'] as String? ?? ''),
      messages: msgs,
    );
  }

  // ─────────────── DELETE ───────────────
  Future<void> delete(ChatSession s) async {
    _timers[s.id]?.cancel();
    final d = await _dir();
    final f = File(p.join(d.path, '${s.id}.json'));
    if (await f.exists()) await f.delete();
    try {
      await _db?.from('chats').delete().eq('id', s.id);
    } catch (_) {}
  }

  Future<void> clear() async {
    _timers.forEach((_, t) => t.cancel());
    _timers.clear();
    final d = await _dir();
    for (final f in d.listSync().whereType<File>()) {
      if (f.path.endsWith('.json')) {
        try { await f.delete(); } catch (_) {}
      }
    }
    try {
      final db = _db;
      final uid = _userId;
      if (db != null && uid != null) {
        await db.from('chats').delete().eq('user_id', uid);
      }
    } catch (_) {}
  }

  Future<void> purgeAttachments(ChatSession s) async {
    for (final m in s.messages) {
      for (final a in m.attachments) {
        if (a.path != null) {
          try { await File(a.path!).delete(); } catch (_) {}
        }
      }
    }
  }
}
