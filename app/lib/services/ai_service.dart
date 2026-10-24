import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config.dart';
import '../models/chat_message.dart';
import 'native_service.dart';

class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AiService {
  static final http.Client _client = http.Client();

  // The PHP fallback endpoint (replace with your deployed URL if needed)
  static const String _phpFallbackUrl = 'https://yoursite.infinityfreeapp.com/api-proxy.php';

  Future<Map<String, dynamic>> send(List<ChatMessage> history) async {
    // 1. USE C++ NATIVE LIB
    NativeService().init();
    final latestHash = NativeService().getHash(history.last.text);
    debugPrint("C++ Native Hash for latest message: $latestHash");

    final recentHistory = history.length > 10 ? history.sublist(history.length - 10) : history;
    final payload = recentHistory
        .where((m) => m.isUser || m.role == 'assistant')
        .map((m) {
          String content = m.text;
          if (m.fileText != null) {
            content = "$content\n\n[Attached File: ${m.fileName}]\n${m.fileText}";
          }
          return {'role': m.role, 'content': content, 'image': m.imageBase64};
        })
        .toList();

    http.Response response;
    try {
      // 2. PRIMARY: SUPABASE (Fast)
      response = await _client
          .post(
            Uri.parse(kBackendUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'messages': payload}),
          )
          .timeout(const Duration(seconds: 15));
          
      if (response.statusCode != 200) {
        throw Exception("Supabase failed");
      }
    } catch (_) {
      // 3. FALLBACK: PHP BACKEND (If Supabase goes down)
      try {
        response = await _client
            .post(
              Uri.parse(_phpFallbackUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'message': history.last.text}),
            )
            .timeout(const Duration(seconds: 15));
      } catch (e) {
        throw AiException('Could not reach CourseDeep (Supabase or PHP). Check internet.');
      }
    }

    final data = _parse(response.body);
    if (data == null) {
      throw AiException('Server sent an unexpected response (HTTP ${response.statusCode}).\nBody: ${response.body}');
    }
    if (response.statusCode != 200 || data['error'] != null) {
      throw AiException(data['error']?.toString() ?? 'Server error (HTTP ${response.statusCode}).');
    }
    final reply = data['reply'];
    if (reply is! String || reply.trim().isEmpty) {
      throw AiException('The AI returned an empty answer. Please try again.');
    }
    return {
      'reply': reply.trim(),
      'sources': data['sources'] ?? [],
    };
  }

  Map<String, dynamic>? _parse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
