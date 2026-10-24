import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/chat_message.dart';
import 'file_service.dart';
import 'native_service.dart';

class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AiEvent {
  AiEvent(this.type, {this.text = '', this.sources = const [], this.provider = ''});
  final String type; // status | sources | delta | done
  final String text;
  final List<Source> sources;
  final String provider;
}

Map<String, String> _headers() => {
      'Content-Type': 'application/json',
      if (kAppKey.isNotEmpty) 'x-app-key': kAppKey,
    };

class AiService {
  /// Wakes the edge function. The server answers `ping` instantly without calling any AI API,
  /// so it no longer burns your Groq/Tavily quota on every app start.
  static Future<void> warmUp() async {
    try {
      await http
          .post(Uri.parse(kBackendUrl), headers: _headers(), body: jsonEncode({'ping': true}))
          .timeout(const Duration(seconds: 6));
    } catch (_) {}
  }
}

/// One in-flight request. Call [cancel] for the Stop button.
class AiRequest {
  final http.Client _client = http.Client();
  bool cancelled = false;

  void cancel() {
    cancelled = true;
    _client.close();
  }

  Future<String> _payload(List<ChatMessage> history, bool search) async {
    final h = history.where((m) => (m.isUser || m.isAssistant) && (m.text.trim().isNotEmpty || m.attachments.isNotEmpty)).toList();
    final recent = h.length > 10 ? h.sublist(h.length - 10) : h;
    final msgs = <Map<String, dynamic>>[];
    for (var i = 0; i < recent.length; i++) {
      final m = recent[i];
      final last = i == recent.length - 1;
      final map = <String, dynamic>{'role': m.isUser ? 'user' : 'assistant', 'content': m.text};
      if (m.isUser && m.attachments.isNotEmpty) {
        final sb = StringBuffer();
        final images = <String>[];
        final files = <Map<String, String>>[];
        for (final a in m.attachments) {
          if (a.kind == AttachKind.image && a.path != null) {
            if (last) {
              images.add(await FileService.base64Of(a.path!));
            } else {
              sb.writeln('[Image attached earlier: ${a.name}]');
            }
          } else if (a.kind == AttachKind.pdf && a.path != null) {
            if (last) {
              files.add({'name': a.name, 'mime': 'application/pdf', 'data': await FileService.base64Of(a.path!)});
            } else {
              sb.writeln('[PDF attached earlier: ${a.name}]');
            }
          } else if (a.text != null) {
            var t = a.text!;
            if (!last && t.length > 3000) t = '${t.substring(0, 3000)}\n…[older attachment shortened]';
            sb.writeln('[Attached file: ${a.name}]\n$t\n');
          }
        }
        if (sb.isNotEmpty) map['fileText'] = sb.toString().trim();
        if (images.isNotEmpty) map['images'] = images;
        if (files.isNotEmpty) map['files'] = files;
      }
      msgs.add(map);
    }
    final rid = NativeService().hashHex('${DateTime.now().microsecondsSinceEpoch}${recent.isEmpty ? '' : recent.last.text}');
    final body = await compute(encodeJsonIsolate, <String, dynamic>{'messages': msgs, 'search': search, 'stream': true, 'rid': rid});
    if (body.length > 13500000) throw AiException('Your attachments are too large to send. Try fewer or smaller files.');
    return body;
  }

  Stream<AiEvent> run(List<ChatMessage> history, {required bool search}) async* {
    final body = await _payload(history, search);
    var gotData = false;
    try {
      final req = http.Request('POST', Uri.parse(kBackendUrl))
        ..headers.addAll(_headers())
        ..body = body;
      final resp = await _client.send(req).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        final txt = await resp.stream.bytesToString();
        String msg;
        try {
          msg = (jsonDecode(txt) as Map)['error']?.toString() ?? 'Server error (HTTP ${resp.statusCode}).';
        } catch (_) {
          msg = 'Server error (HTTP ${resp.statusCode}).';
        }
        throw AiException(msg);
      }
      final lines = resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 45), onTimeout: (sink) {
            sink.addError(TimeoutException('stalled'));
            sink.close();
          });
      await for (final line in lines) {
        if (line.trim().isEmpty) continue;
        Map<String, dynamic> j;
        try {
          j = Map<String, dynamic>.from(jsonDecode(line) as Map);
        } catch (_) {
          continue;
        }
        switch (j['t']) {
          case 'status':
            yield AiEvent('status', text: j['text']?.toString() ?? '');
            break;
          case 'sources':
            yield AiEvent('sources',
                sources: (j['sources'] as List? ?? []).map((e) => Source.fromJson(Map<String, dynamic>.from(e as Map))).where((s) => s.url.isNotEmpty).toList());
            break;
          case 'delta':
            gotData = true;
            yield AiEvent('delta', text: j['d']?.toString() ?? '');
            break;
          case 'done':
            yield AiEvent('done', provider: j['provider']?.toString() ?? '');
            break;
          case 'error':
            throw AiException(j['message']?.toString() ?? 'The AI could not answer.');
        }
      }
    } catch (e) {
      if (cancelled) return;
      if (e is AiException) rethrow;
      if (gotData) {
        yield AiEvent('delta', text: '\n\n_…connection lost. Tap regenerate to continue._');
        return;
      }
      // Network failure before any answer: try the optional PHP gateway once.
      if (kFallbackUrl.isNotEmpty) {
        yield* _fallback(body);
        return;
      }
      throw AiException('Could not reach CourseDeep servers. Check your internet connection and try again.');
    } finally {
      _client.close();
    }
  }

  Stream<AiEvent> _fallback(String body) async* {
    final map = Map<String, dynamic>.from(jsonDecode(body) as Map)..['stream'] = false;
    final c = http.Client();
    try {
      yield AiEvent('status', text: 'Switching to backup route');
      final r = await c.post(Uri.parse(kFallbackUrl), headers: _headers(), body: jsonEncode(map)).timeout(const Duration(seconds: 60));
      final d = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
      if (r.statusCode != 200 || d['error'] != null) throw AiException(d['error']?.toString() ?? 'Backup route failed (HTTP ${r.statusCode}).');
      final src = (d['sources'] as List? ?? []).map((e) => Source.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      if (src.isNotEmpty) yield AiEvent('sources', sources: src);
      yield AiEvent('delta', text: d['reply']?.toString() ?? '');
      yield AiEvent('done', provider: d['provider']?.toString() ?? 'Backup');
    } on AiException {
      rethrow;
    } catch (_) {
      throw AiException('Could not reach CourseDeep servers. Check your internet connection and try again.');
    } finally {
      c.close();
    }
  }
}
